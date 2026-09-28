#!/usr/bin/env python3
"""
asm_mini.py - A tiny two-pass RV32I assembler, written for this project
because no riscv32/64-unknown-elf-gcc toolchain was available on the
development machine (checked: riscv64-unknown-elf-gcc, riscv32-unknown-elf-gcc,
riscv-none-elf-gcc, riscv64-elf-gcc, riscv32-elf-gcc were all absent).

It supports exactly the subset of RV32I needed by firmware/program.asm:
real instructions  lui, addi, ori, andi, xori, add, sub, lw, sw,
                    beq, bne, jal, jalr
pseudo-instructions li (32-bit load-immediate, standard lui+addi expansion),
                    j, nop, beqz, bnez
directives          label:, .word <value>

Output: a plain hex file, one 32-bit word per line, suitable for
Verilog's $readmemh (word 0 = byte address 0, word 1 = byte address 4, ...).

This is a teaching/portfolio tool, not a general-purpose assembler: it
deliberately does not support the full RISC-V ISA or GNU-as syntax.
"""

import re
import sys

REGS = {
    "zero": 0, "ra": 1, "sp": 2, "gp": 3, "tp": 4,
    "t0": 5, "t1": 6, "t2": 7,
    "s0": 8, "fp": 8, "s1": 9,
    "a0": 10, "a1": 11, "a2": 12, "a3": 13, "a4": 14, "a5": 15, "a6": 16, "a7": 17,
    "s2": 18, "s3": 19, "s4": 20, "s5": 21, "s6": 22, "s7": 23, "s8": 24, "s9": 25,
    "s10": 26, "s11": 27,
    "t3": 28, "t4": 29, "t5": 30, "t6": 31,
}
for i in range(32):
    REGS.setdefault(f"x{i}", i)


def reg(name):
    name = name.strip()
    if name not in REGS:
        raise ValueError(f"unknown register '{name}'")
    return REGS[name]


def parse_imm(tok, labels=None, here=None):
    tok = tok.strip()
    if labels is not None and tok in labels:
        return labels[tok] - (here if here is not None else 0)
    return int(tok, 0)


def parse_mem_operand(tok):
    # "imm(reg)" -> (imm, reg_num)
    m = re.match(r"^(-?\w+)\((\w+)\)$", tok.strip())
    if not m:
        raise ValueError(f"bad memory operand '{tok}'")
    return int(m.group(1), 0), reg(m.group(2))


# ---------------------------------------------------------------------
# Encoders
# ---------------------------------------------------------------------

def enc_r(funct7, rs2, rs1, funct3, rd, opcode):
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def enc_i(imm, rs1, funct3, rd, opcode):
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def enc_s(imm, rs2, rs1, funct3, opcode):
    imm &= 0xFFF
    return (((imm >> 5) & 0x7F) << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | ((imm & 0x1F) << 7) | opcode


def enc_b(imm, rs2, rs1, funct3, opcode):
    assert imm % 2 == 0, "branch offset must be even"
    imm &= 0x1FFF  # 13-bit signed range
    b12 = (imm >> 12) & 0x1
    b11 = (imm >> 11) & 0x1
    b10_5 = (imm >> 5) & 0x3F
    b4_1 = (imm >> 1) & 0xF
    return (b12 << 31) | (b10_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (b4_1 << 8) | (b11 << 7) | opcode


def enc_u(imm, rd, opcode):
    return ((imm & 0xFFFFF) << 12) | (rd << 7) | opcode


def enc_j(imm, rd, opcode):
    assert imm % 2 == 0, "jump offset must be even"
    imm &= 0x1FFFFF  # 21-bit signed range
    j20 = (imm >> 20) & 0x1
    j10_1 = (imm >> 1) & 0x3FF
    j11 = (imm >> 11) & 0x1
    j19_12 = (imm >> 12) & 0xFF
    return (j20 << 31) | (j10_1 << 21) | (j11 << 20) | (j19_12 << 12) | (rd << 7) | opcode


def li_split(imm):
    """Standard GNU-as algorithm: split a 32-bit immediate into
    (upper20, lower12) such that (upper20 << 12) + sign_extend(lower12)
    == imm (mod 2**32)."""
    imm &= 0xFFFFFFFF
    upper = imm >> 12
    if imm & 0x800:
        upper = (upper + 1) & 0xFFFFF
    lower = imm - ((upper << 12) & 0xFFFFFFFF)
    # normalize lower into a signed 12-bit range for clarity (not required
    # for correctness since enc_i masks with & 0xFFF anyway)
    lower &= 0xFFFFFFFF
    if lower & 0x80000000:
        lower -= 1 << 32
    return upper & 0xFFFFF, lower


OPC_OP = 0b0110011
OPC_OPIMM = 0b0010011
OPC_LOAD = 0b0000011
OPC_STORE = 0b0100011
OPC_BRANCH = 0b1100011
OPC_LUI = 0b0110111
OPC_JAL = 0b1101111
OPC_JALR = 0b1100111


def assemble(lines):
    # ---- pass 1: compute addresses of labels ----
    labels = {}
    addr = 0
    cleaned = []  # (addr, mnemonic, args[])
    for raw in lines:
        line = raw.split("#", 1)[0].strip()
        if not line:
            continue
        while ":" in line:
            lbl, _, rest = line.partition(":")
            lbl = lbl.strip()
            if not re.match(r"^[A-Za-z_.][A-Za-z0-9_.]*$", lbl):
                break
            labels[lbl] = addr
            line = rest.strip()
        if not line:
            continue
        parts = re.split(r"[,\s]+", line, maxsplit=1)
        mnem = parts[0]
        args = [a.strip() for a in re.split(r",", parts[1])] if len(parts) > 1 else []
        cleaned.append((addr, mnem, args))
        if mnem in ("li",):
            # li may expand to 1 or 2 instructions; reserve 2 words to be
            # safe, patch with nop if only 1 is needed
            addr += 8
        else:
            addr += 4

    # ---- pass 2: encode ----
    words = []  # list of (byte_addr, 32-bit word)
    for a, mnem, args in cleaned:
        here = a
        if mnem == "li":
            rd = reg(args[0])
            imm = parse_imm(args[1], labels, None)
            upper, lower = li_split(imm)
            if upper == 0 and not (imm & 0x800):
                words.append((here, enc_i(lower, 0, 0b000, rd, OPC_OPIMM)))
                words.append((here + 4, enc_i(0, 0, 0, 0, OPC_OPIMM)))  # nop pad
            else:
                words.append((here, enc_u(upper, rd, OPC_LUI)))
                words.append((here + 4, enc_i(lower, rd, 0b000, rd, OPC_OPIMM)))
            continue

        if mnem == "nop":
            words.append((here, enc_i(0, 0, 0, 0, OPC_OPIMM)))
            continue

        if mnem == "j":
            target = parse_imm(args[0], labels, here)
            words.append((here, enc_j(target, 0, OPC_JAL)))
            continue

        if mnem in ("beqz", "bnez"):
            rs1 = reg(args[0])
            target = parse_imm(args[1], labels, here)
            f3 = 0b000 if mnem == "beqz" else 0b001
            words.append((here, enc_b(target, 0, rs1, f3, OPC_BRANCH)))
            continue

        if mnem in ("beq", "bne"):
            rs1 = reg(args[0]); rs2 = reg(args[1])
            target = parse_imm(args[2], labels, here)
            f3 = 0b000 if mnem == "beq" else 0b001
            words.append((here, enc_b(target, rs2, rs1, f3, OPC_BRANCH)))
            continue

        if mnem in ("addi", "ori", "andi", "xori", "slli", "srli", "srai", "slti", "sltiu"):
            rd = reg(args[0]); rs1 = reg(args[1]); imm = parse_imm(args[2], labels, None)
            f3 = {"addi": 0b000, "ori": 0b110, "andi": 0b111, "xori": 0b100,
                  "slli": 0b001, "srli": 0b101, "srai": 0b101,
                  "slti": 0b010, "sltiu": 0b011}[mnem]
            if mnem == "slli":
                words.append((here, enc_i(imm & 0x1F, rs1, f3, rd, OPC_OPIMM)))
            elif mnem == "srli":
                words.append((here, enc_i(imm & 0x1F, rs1, f3, rd, OPC_OPIMM)))
            elif mnem == "srai":
                words.append((here, enc_i((imm & 0x1F) | (0x20 << 5), rs1, f3, rd, OPC_OPIMM)))
            else:
                words.append((here, enc_i(imm, rs1, f3, rd, OPC_OPIMM)))
            continue

        if mnem in ("add", "sub"):
            rd = reg(args[0]); rs1 = reg(args[1]); rs2 = reg(args[2])
            f7 = 0b0100000 if mnem == "sub" else 0b0000000
            words.append((here, enc_r(f7, rs2, rs1, 0b000, rd, OPC_OP)))
            continue

        if mnem == "lw":
            rd = reg(args[0])
            imm, rs1 = parse_mem_operand(args[1])
            words.append((here, enc_i(imm, rs1, 0b010, rd, OPC_LOAD)))
            continue

        if mnem == "sw":
            rs2 = reg(args[0])
            imm, rs1 = parse_mem_operand(args[1])
            words.append((here, enc_s(imm, rs2, rs1, 0b010, OPC_STORE)))
            continue

        if mnem == "jalr":
            rd = reg(args[0])
            imm, rs1 = parse_mem_operand(args[1])
            words.append((here, enc_i(imm, rs1, 0b000, rd, OPC_JALR)))
            continue

        if mnem == "lui":
            rd = reg(args[0])
            imm = parse_imm(args[1], labels, None)
            words.append((here, enc_u(imm, rd, OPC_LUI)))
            continue

        if mnem == ".word":
            val = parse_imm(args[0], labels, None)
            words.append((here, val & 0xFFFFFFFF))
            continue

        raise ValueError(f"unsupported mnemonic '{mnem}' at addr 0x{here:x}")

    max_addr = max((a for a, _ in words), default=0)
    n_words = max_addr // 4 + 1
    image = [0] * n_words
    for a, w in words:
        image[a // 4] = w & 0xFFFFFFFF
    return image, labels


# Must match the RAM depth declared in rtl/ram.v (WORDS = 1024, i.e. 4 KiB).
# Padding the image out to the full depth avoids the (harmless but noisy)
# "$readmemh: not enough words in the file" warning from Icarus Verilog.
RAM_WORDS = 1024


def main():
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} <input.asm> <output.hex>")
        sys.exit(1)
    with open(sys.argv[1]) as f:
        lines = f.readlines()
    image, labels = assemble(lines)
    used_words = len(image)
    if len(image) < RAM_WORDS:
        image = image + [0] * (RAM_WORDS - len(image))
    with open(sys.argv[2], "w") as f:
        for w in image:
            f.write(f"{w:08x}\n")
    print(f"assembled {used_words} words ({used_words*4} bytes of code+data), "
          f"padded to {RAM_WORDS} words -> {sys.argv[2]}")
    print("labels:", {k: hex(v) for k, v in labels.items()})


if __name__ == "__main__":
    main()
