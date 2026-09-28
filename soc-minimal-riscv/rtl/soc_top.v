// soc_top.v - Top-level for soc-minimal-riscv.
//
// Wires together:
//   - picorv32          : third-party RISC-V (RV32I) CPU core, unmodified
//                          (rtl/picorv32/picorv32.v, from YosysHQ/picorv32)
//   - bus                : address decode / interconnect      (mine, rtl/bus.v)
//   - ram                : program + data memory               (mine, rtl/ram.v)
//   - uart_tx             : memory-mapped UART transmitter       (mine, rtl/uart_tx.v)
//   - gpio                : memory-mapped GPIO controller        (mine, rtl/gpio.v)
//
// See soc-minimal-riscv/README.md for the block diagram and address map.

`default_nettype none

module soc_top #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer BAUD_RATE   = 1_000_000
) (
    input  wire        clk,
    input  wire        resetn,

    output wire         uart_tx,     // serial line out
    output wire [31:0]  gpio_out,    // observe in waveform / connect to LEDs on real HW
    input  wire [31:0]  gpio_in,     // testbench (or real buttons/sensors) drive this

    output wire          trap        // picorv32 trap indicator (illegal insn / debug)
);

    // ------------------------------------------------------------------
    // picorv32 <-> bus signals (plain valid/ready memory interface)
    // ------------------------------------------------------------------
    wire        mem_valid;
    wire        mem_instr;
    wire        mem_ready;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0]  mem_wstrb;
    wire [31:0] mem_rdata;

    picorv32 #(
        .ENABLE_COUNTERS (1),
        .ENABLE_MUL      (0),
        .ENABLE_DIV      (0),
        .ENABLE_IRQ      (0),
        .ENABLE_PCPI     (0),
        .BARREL_SHIFTER  (0),
        .PROGADDR_RESET  (32'h0000_0000),
        .PROGADDR_IRQ    (32'h0000_0010),
        .STACKADDR       (32'h0000_0FFC)
    ) cpu (
        .clk        (clk),
        .resetn     (resetn),
        .trap       (trap),

        .mem_valid  (mem_valid),
        .mem_instr  (mem_instr),
        .mem_ready  (mem_ready),
        .mem_addr   (mem_addr),
        .mem_wdata  (mem_wdata),
        .mem_wstrb  (mem_wstrb),
        .mem_rdata  (mem_rdata),

        .mem_la_read  (),
        .mem_la_write (),
        .mem_la_addr  (),
        .mem_la_wdata (),
        .mem_la_wstrb (),

        .pcpi_valid (),
        .pcpi_insn  (),
        .pcpi_rs1   (),
        .pcpi_rs2   (),
        .pcpi_wr    (1'b0),
        .pcpi_rd    (32'b0),
        .pcpi_wait  (1'b0),
        .pcpi_ready (1'b0),

        .irq        (32'b0),
        .eoi        (),

        .trace_valid (),
        .trace_data  ()
    );

    // ------------------------------------------------------------------
    // Bus <-> peripheral signals
    // ------------------------------------------------------------------
    wire        ram_sel;
    wire [31:0] ram_addr, ram_wdata, ram_rdata;
    wire [3:0]  ram_wstrb;

    wire        uart_sel;
    wire [31:0] uart_addr, uart_wdata, uart_rdata;
    wire [3:0]  uart_wstrb;

    wire        gpio_sel;
    wire [31:0] gpio_addr, gpio_wdata, gpio_rdata;
    wire [3:0]  gpio_wstrb;

    bus bus_inst (
        .clk        (clk),
        .resetn     (resetn),

        .mem_valid  (mem_valid),
        .mem_instr  (mem_instr),
        .mem_ready  (mem_ready),
        .mem_addr   (mem_addr),
        .mem_wdata  (mem_wdata),
        .mem_wstrb  (mem_wstrb),
        .mem_rdata  (mem_rdata),

        .ram_sel    (ram_sel),
        .ram_addr   (ram_addr),
        .ram_wdata  (ram_wdata),
        .ram_wstrb  (ram_wstrb),
        .ram_rdata  (ram_rdata),

        .uart_sel   (uart_sel),
        .uart_addr  (uart_addr),
        .uart_wdata (uart_wdata),
        .uart_wstrb (uart_wstrb),
        .uart_rdata (uart_rdata),

        .gpio_sel   (gpio_sel),
        .gpio_addr  (gpio_addr),
        .gpio_wdata (gpio_wdata),
        .gpio_wstrb (gpio_wstrb),
        .gpio_rdata (gpio_rdata)
    );

    ram ram_inst (
        .clk    (clk),
        .sel    (ram_sel),
        .addr   (ram_addr),
        .wdata  (ram_wdata),
        .wstrb  (ram_wstrb),
        .rdata  (ram_rdata)
    );

    uart_tx #(
        .CLK_FREQ_HZ (CLK_FREQ_HZ),
        .BAUD_RATE   (BAUD_RATE)
    ) uart_inst (
        .clk    (clk),
        .resetn (resetn),
        .sel    (uart_sel),
        .addr   (uart_addr),
        .wdata  (uart_wdata),
        .wstrb  (uart_wstrb),
        .rdata  (uart_rdata),
        .tx     (uart_tx)
    );

    gpio gpio_inst (
        .clk      (clk),
        .resetn   (resetn),
        .sel      (gpio_sel),
        .addr     (gpio_addr),
        .wdata    (gpio_wdata),
        .wstrb    (gpio_wstrb),
        .rdata    (gpio_rdata),
        .gpio_out (gpio_out),
        .gpio_in  (gpio_in)
    );

endmodule
