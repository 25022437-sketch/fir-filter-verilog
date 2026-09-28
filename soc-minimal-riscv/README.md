# soc-minimal-riscv

Một SoC (System on Chip) tối giản dựa trên lõi RISC-V **PicoRV32**, mô phỏng
thuần bằng **Icarus Verilog** — không dùng board FPGA vật lý, không cần
deploy phần cứng. Đây là project thứ hai trong repo, đặt cạnh
[`fir_5tap.sv`](../fir_5tap.sv) để làm portfolio về digital/IC design.

## 1. Sơ đồ khối

```
                          soc_top.v
        +---------------------------------------------------+
        |                                                    |
        |   +-----------+        mem_valid/ready             |
        |   |           |------------------------+           |
        |   | picorv32  |  mem_addr/wdata/wstrb   |           |
        |   | (RV32I    |------------------------+|           |
        |   |  CPU core |  mem_rdata              ||          |
        |   |  - bên    |<-----------------------+||          |
        |   |  thứ 3)   |                         |||         |
        |   +-----------+                         vvv         |
        |                                    +-----------+    |
        |                                    |  bus.v    |    |
        |                                    | (của tôi) |    |
        |                                    | address   |    |
        |                                    | decode    |    |
        |                                    +-----+-----+    |
        |                        +--------------+--+----+     |
        |                        |                 |          |
        |                  sel/addr/wdata/wstrb (x3, ai chọn nấy)
        |                        |                 |          |
        |                 +------v----+   +--------v-----+  +-v----------+
        |                 |   ram.v   |   |  uart_tx.v   |  |  gpio.v    |
        |                 | (của tôi) |   |  (của tôi)   |  | (của tôi)  |
        |                 | 4KB RAM   |   |  TX shift    |  | OUT/IN reg |
        |                 | $readmemh |   |  reg + baud  |  |            |
        |                 +-----------+   +------+-------+  +-----+------+
        |                                         |                |
        +-----------------------------------------|----------------|-----+
                                                    v                v
                                            tx (serial line)   gpio_out[31:0]
                                            -> testbench giải  -> quan sát
                                               mã thành ký tự     qua waveform
                                                                gpio_in[31:0]
                                                                <- testbench
                                                                   ép giá trị
```

**Bản đồ địa chỉ (memory map)**, giải mã trong `bus.v`:

| Địa chỉ                     | Thiết bị          | Ghi chú                              |
|------------------------------|-------------------|---------------------------------------|
| `0x0000_0000 - 0x0000_0FFF`  | RAM (4 KB)         | Chương trình + dữ liệu, nạp bằng `$readmemh` |
| `0x1000_0000`                | `UART_TX_DATA`     | Ghi 1 byte (32-bit, dùng `sw`) → bắt đầu gửi |
| `0x1000_0004`                | `UART_TX_STATUS`   | Đọc, bit 0 = `busy`                    |
| `0x2000_0000`                | `GPIO_OUT`         | Thanh ghi xuất 32-bit, đọc/ghi được    |
| `0x2000_0004`                | `GPIO_IN`          | Thanh ghi nhập 32-bit, chỉ đọc (testbench ép giá trị) |

## 2. Vì sao dùng PicoRV32 có sẵn, không tự thiết kế CPU?

Thiết kế một CPU RISC-V (pipeline, hazard, decode đầy đủ RV32I) đúng đắn là
một project riêng tốn hàng trăm giờ và rất dễ có bug tinh vi (đặc biệt là
load-use hazard, branch misprediction, CSR...). Mục tiêu của project này là
**tích hợp hệ thống (SoC integration)**: chứng minh khả năng đọc datasheet/
interface của một lõi CPU thật, thiết kế bus, viết peripheral, và verify
toàn hệ thống — đây là kỹ năng thực tế mà công việc/labs về digital design
cần, khác với kỹ năng "tự thiết kế CPU" (thường học riêng ở môn Computer
Architecture).

Vì vậy, ranh giới rõ ràng trong repo này:

| Phần | Nguồn gốc |
|------|-----------|
| `rtl/picorv32/picorv32.v` | **Lấy nguyên bản** từ [YosysHQ/picorv32](https://github.com/YosysHQ/picorv32) (file `picorv32.v`, không sửa một dòng nào). Đây là lõi CPU RV32I mã nguồn mở được dùng rộng rãi trong công nghiệp/học thuật (SymbiFlow, nhiều chip tapeout thật). |
| `rtl/bus.v` | **Tự viết.** Address decode + mux giữa CPU và 3 thiết bị, xử lý handshake `mem_valid/mem_ready` của picorv32. |
| `rtl/uart_tx.v` | **Tự viết.** Bộ phát UART thật: máy trạng thái start/data(8-bit LSB-first)/stop bit, bộ chia clock ra baud rate, thanh ghi busy. Không dùng lõi UART có sẵn nào. |
| `rtl/gpio.v` | **Tự viết.** Thanh ghi GPIO_OUT (read/write) và GPIO_IN (read-only), map qua bus. |
| `rtl/soc_top.v` | **Tự viết.** Nối picorv32 + bus + ram + uart_tx + gpio thành một SoC hoàn chỉnh. |
| `tb/tb_soc_top.v` | **Tự viết.** Testbench: cấp xung clock/reset, nạp firmware, đóng vai "máy tính ngoài" nghe UART, ép giá trị GPIO_IN, dump VCD, tự kết thúc bằng `$finish`. |
| `tools/asm_mini.py`, `firmware/program.asm` | **Tự viết** (xem mục 3). |

Nói cách khác: phần "khó, tự thiết kế RTL thật" của project nằm ở
**bus decode + UART TX + GPIO + verify toàn hệ thống**, còn CPU được tái sử
dụng có chủ đích — đúng như cách các SoC thật trong công nghiệp được thiết
kế (không ai tự vẽ lại RISC-V core cho mỗi chip).

## 3. Vì sao firmware là assembly viết tay, không phải C?

Máy dùng để làm project này **không có sẵn RISC-V toolchain**
(`riscv64-unknown-elf-gcc`, `riscv32-unknown-elf-gcc`, `riscv-none-elf-gcc`,
... đều không tìm thấy — đã kiểm tra bằng `command -v` trước khi bắt đầu).

Thay vì dừng lại, tôi tự viết:

- **`tools/asm_mini.py`**: một assembler RV32I hai-pass (two-pass) rất nhỏ,
  tự mã hoá đúng các định dạng lệnh R/I/S/B/U/J-type theo chuẩn RISC-V ISA
  (encode `lui`, `addi`, `lw`, `sw`, `beq`, `jal`, ... ra đúng bit pattern
  32-bit), hỗ trợ nhãn (label), pseudo-instruction `li` (tách thành
  `lui`+`addi` theo đúng thuật toán chuẩn của GNU `as`), và directive
  `.word` để nhúng dữ liệu (chuỗi ký tự) ngay trong ảnh nhớ.
- **`firmware/program.asm`**: chương trình RV32I viết tay bằng assembly,
  dùng `tools/asm_mini.py` để dịch ra `firmware/program.hex` (định dạng
  `$readmemh`, 1 từ 32-bit mỗi dòng, hex).

Đây **không phải là ghi tay từng bit nhị phân** — mà là tự viết công cụ dịch
(assembler) rồi dùng nó, cách làm này vẫn đúng tinh thần "hiểu được RISC-V ISA
ở mức máy" mà vẫn có một quy trình lặp lại được, dễ sửa lỗi (thấy ngay trong
mục 5, log giả lập chạy đúng ngay từ những lần thử đầu vì assembler tự động
hoá việc tính offset nhãn thay vì tính tay).

Nếu sau này cài được toolchain thật, chỉ cần thay bước dịch bằng
`riscv32-unknown-elf-gcc -march=rv32i -mabi=ilp32 ...` + `objcopy` để ra
cùng định dạng hex — phần RTL (`soc_top.v`, `bus.v`, ...) không cần đổi gì.

### Hành vi của `firmware/program.asm`

1. Gửi chuỗi `"HELLO SOC\n"` ra UART, từng ký tự một, có polling bit `busy`
   của `UART_TX_STATUS` trước mỗi lần ghi (mô phỏng đúng cách firmware thật
   giao tiếp với UART).
2. Ghi giá trị cố định `0xA5A5A5A5` ra `GPIO_OUT`.
3. Đọc `GPIO_IN` (testbench đã ép sẵn giá trị `0x000000C3`), đảo bit
   (`xori rd, rs, -1` — pseudo `not`), ghi kết quả (`0xFFFFFF3C`) ngược lại
   ra `GPIO_OUT`.
4. Lặp vô hạn tại nhãn `halt` (chương trình nhúng không có hệ điều hành để
   "return" về).

## 4. Cách chạy lại mô phỏng

Yêu cầu: `iverilog` + `vvp` (Icarus Verilog, đã test với bản 13.0), Python 3
(chỉ để chạy assembler, không cần thư viện ngoài).

```bash
cd soc-minimal-riscv

# 1) (chỉ cần chạy lại nếu sửa firmware/program.asm)
python3 tools/asm_mini.py firmware/program.asm firmware/program.hex

# 2) Biên dịch toàn bộ RTL + testbench
iverilog -g2012 -o sim/soc_tb.vvp \
  rtl/picorv32/picorv32.v \
  rtl/ram.v rtl/uart_tx.v rtl/gpio.v rtl/bus.v rtl/soc_top.v \
  tb/tb_soc_top.v

# 3) Chạy mô phỏng
vvp sim/soc_tb.vvp
```

Sau khi chạy xong, mở `sim/waveform.vcd` bằng GTKWave (hoặc EPWave trên
web) để xem waveform. Các tín hiệu đáng xem nhất (đã ghi chú trong
`tb/tb_soc_top.v`):

- `dut.gpio_out` — đổi từ `0x00000000` → `0xA5A5A5A5` → `0xFFFFFF3C` theo
  thời gian.
- `dut.uart_inst.tx` — dạng sóng nối tiếp thật (start bit, 8 data bit, stop
  bit) cho từng ký tự.
- `dut.mem_addr` / `dut.mem_wdata` — từng giao dịch bus của CPU, để đối
  chiếu với thứ tự lệnh trong `firmware/program.asm`.

## 5. Kết quả mong đợi

Chạy `vvp sim/soc_tb.vvp` sẽ in ra console đúng như sau (đã tự chạy và xác
nhận, không phải kết quả suy đoán):

```
---------------------------------------------------------
[TB] soc-minimal-riscv simulation starting
[TB] Waiting for UART bytes from the CPU...
---------------------------------------------------------
[UART] Received string: "HELLO SOC\n"
[GPIO] write #1 @ t=94115000 : GPIO_OUT <= 0xa5a5a5a5
[GPIO] write #2 @ t=94295000 : GPIO_OUT <= 0xffffff3c
---------------------------------------------------------
[TB] PASS: final GPIO_OUT = 0xffffff3c (matches ~GPIO_IN)
[TB] simulation finished at t=94395000
---------------------------------------------------------
tb/tb_soc_top.v:197: $finish called at 94395000 (1ps)
```

Giải thích số liệu:
- `"HELLO SOC\n"` là chuỗi testbench ghép lại được từ các byte CPU ghi vào
  `UART_TX_DATA` — chứng tỏ cả chương trình assembly lẫn `uart_tx.v` đều
  hoạt động đúng ở mức bit.
- `GPIO_OUT` lần 1 = `0xa5a5a5a5` — đúng pattern cố định trong chương trình.
- `GPIO_OUT` lần 2 = `0xffffff3c` = bitwise NOT của `0x000000c3` (giá trị
  testbench ép vào `GPIO_IN`) — chứng tỏ đường đọc `GPIO_IN` → xử lý → ghi
  lại `GPIO_OUT` hoạt động đúng, không chỉ là ghi hằng số.
- Simulation tự kết thúc bằng `$finish` ở khoảng t ≈ 94.4 µs mô phỏng
  (không treo vô hạn), nhờ testbench chờ đủ 2 lần ghi GPIO rồi tự dừng, có
  watchdog timeout 2ms dự phòng nếu có gì đó không xảy ra như mong đợi.

## 6. Cấu trúc thư mục

```
soc-minimal-riscv/
├── README.md                  (file này)
├── .gitignore
├── rtl/
│   ├── picorv32/picorv32.v    (lấy nguyên bản từ YosysHQ/picorv32)
│   ├── bus.v                  (tự viết - address decode)
│   ├── ram.v                  (tự viết - RAM 4KB, $readmemh)
│   ├── uart_tx.v              (tự viết - UART TX thật)
│   ├── gpio.v                 (tự viết - GPIO_OUT/GPIO_IN)
│   └── soc_top.v              (tự viết - top-level, nối tất cả)
├── firmware/
│   ├── program.asm            (firmware RV32I viết tay)
│   └── program.hex            (sinh ra bởi tools/asm_mini.py, nạp bằng $readmemh)
├── tools/
│   └── asm_mini.py            (assembler RV32I mini tự viết)
├── tb/
│   └── tb_soc_top.v           (testbench)
└── sim/                       (artifact mô phỏng: .vvp, .vcd - không commit, xem .gitignore)
```
