# program.asm - firmware for soc-minimal-riscv
#
# No RISC-V C toolchain (riscv32/64-unknown-elf-gcc) was found on this
# machine, so this program is written directly in RV32I assembly and
# turned into a $readmemh hex image by our own tiny assembler
# (tools/asm_mini.py) instead of a real `as`/`gcc`. See the top-level
# README.md for the full explanation.
#
# Behavior:
#   1) Poll-send the string "HELLO SOC\n" one byte at a time over the
#      memory-mapped UART TX (UART_TX_DATA / UART_TX_STATUS).
#   2) Write a fixed test pattern (0xA5A5A5A5) to GPIO_OUT.
#   3) Read GPIO_IN (driven by the testbench), bitwise-invert it, and
#      write the result back to GPIO_OUT.
#   4) Spin forever (halt).
#
# Register usage:
#   t0 = UART_TX_DATA address      t1 = UART_TX_STATUS address
#   t2 = character being sent      t3 = UART status scratch
#   s2 = pointer into the string table (msg)
#   s0 = GPIO_OUT address          s1 = GPIO_IN address
#   a0 = GPIO test pattern         a1 = value read from GPIO_IN
#   a2 = processed (inverted) value

_start:
    li   t0, 0x10000000
    li   t1, 0x10000004
    li   s2, msg

send_loop:
    lw   t2, 0(s2)
    beqz t2, send_done

wait_uart:
    lw   t3, 0(t1)
    andi t3, t3, 1
    bnez t3, wait_uart

    sw   t2, 0(t0)
    addi s2, s2, 4
    j    send_loop

send_done:
    li   s0, 0x20000000
    li   s1, 0x20000004
    li   a0, 0xA5A5A5A5
    sw   a0, 0(s0)

    lw   a1, 0(s1)
    xori a2, a1, -1
    sw   a2, 0(s0)

halt:
    j halt

msg:
    .word 0x48
    .word 0x45
    .word 0x4C
    .word 0x4C
    .word 0x4F
    .word 0x20
    .word 0x53
    .word 0x4F
    .word 0x43
    .word 0x0A
    .word 0x00
