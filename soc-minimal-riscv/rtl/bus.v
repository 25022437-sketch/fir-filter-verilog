// bus.v - Minimal address-decoded interconnect for soc-minimal-riscv.
//
// Written from scratch. This is *not* AXI/Wishbone: it is the simplest
// thing that correctly implements picorv32's plain valid/ready memory
// interface while fanning it out to three memory-mapped targets.
//
// Handshake: this bus adds exactly one wait state per transaction. That
// is the same pattern used in picorv32's own README "minimal example"
// testbench (mem_ready <= mem_valid && !mem_ready), chosen deliberately
// because it is a well-understood, well-tested way to interface picorv32
// to synchronous-style peripherals without creating combinational loops
// between mem_valid and mem_ready.
//
// Address map:
//   0x0000_0000 - 0x0000_0FFF  RAM (program + data, 4 KiB)
//   0x1000_0000 - 0x1000_00FF  UART TX (see uart_tx.v for register layout)
//   0x2000_0000 - 0x2000_00FF  GPIO     (see gpio.v for register layout)
//
// Accesses outside all three windows are acknowledged (so the CPU never
// hangs) but return 0 and write nowhere.

`default_nettype none

module bus (
    input  wire        clk,
    input  wire        resetn,

    // ---- CPU-facing side (connects straight to picorv32's mem_*) ----
    input  wire        mem_valid,
    input  wire        mem_instr,
    output reg         mem_ready,
    input  wire [31:0] mem_addr,
    input  wire [31:0] mem_wdata,
    input  wire [3:0]  mem_wstrb,
    output reg  [31:0] mem_rdata,

    // ---- RAM port ----
    output wire         ram_sel,
    output wire [31:0]  ram_addr,
    output wire [31:0]  ram_wdata,
    output wire [3:0]   ram_wstrb,
    input  wire [31:0]  ram_rdata,

    // ---- UART port ----
    output wire         uart_sel,
    output wire [31:0]  uart_addr,
    output wire [31:0]  uart_wdata,
    output wire [3:0]   uart_wstrb,
    input  wire [31:0]  uart_rdata,

    // ---- GPIO port ----
    output wire         gpio_sel,
    output wire [31:0]  gpio_addr,
    output wire [31:0]  gpio_wdata,
    output wire [3:0]   gpio_wstrb,
    input  wire [31:0]  gpio_rdata
);

    localparam [31:0] RAM_BASE  = 32'h0000_0000, RAM_TOP  = 32'h0000_0FFF;
    localparam [31:0] UART_BASE = 32'h1000_0000, UART_TOP = 32'h1000_00FF;
    localparam [31:0] GPIO_BASE = 32'h2000_0000, GPIO_TOP = 32'h2000_00FF;

    wire sel_ram  = mem_valid && (mem_addr >= RAM_BASE)  && (mem_addr <= RAM_TOP);
    wire sel_uart = mem_valid && (mem_addr >= UART_BASE) && (mem_addr <= UART_TOP);
    wire sel_gpio = mem_valid && (mem_addr >= GPIO_BASE) && (mem_addr <= GPIO_TOP);

    assign ram_sel   = sel_ram;
    assign ram_addr  = mem_addr;
    assign ram_wdata = mem_wdata;
    assign ram_wstrb = sel_ram ? mem_wstrb : 4'b0000;

    assign uart_sel   = sel_uart;
    assign uart_addr  = mem_addr;
    assign uart_wdata = mem_wdata;
    assign uart_wstrb = sel_uart ? mem_wstrb : 4'b0000;

    assign gpio_sel   = sel_gpio;
    assign gpio_addr  = mem_addr;
    assign gpio_wdata = mem_wdata;
    assign gpio_wstrb = sel_gpio ? mem_wstrb : 4'b0000;

    // One-wait-state handshake: ready pulses high exactly one cycle after
    // a fresh request (mem_valid && !mem_ready), then drops again once
    // the CPU deasserts mem_valid for the next request.
    always @(posedge clk) begin
        if (!resetn)
            mem_ready <= 1'b0;
        else
            mem_ready <= mem_valid && !mem_ready;
    end

    // Registered read-data mux, sampled on the same edge that mem_ready
    // is produced. All three targets present combinational read data at
    // their current `addr`, so this simply captures whichever one was
    // selected for this request.
    always @(posedge clk) begin
        if (mem_valid && !mem_ready) begin
            if (sel_ram)
                mem_rdata <= ram_rdata;
            else if (sel_uart)
                mem_rdata <= uart_rdata;
            else if (sel_gpio)
                mem_rdata <= gpio_rdata;
            else
                mem_rdata <= 32'h0000_0000; // unmapped address
        end
    end

endmodule
