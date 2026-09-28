// ram.v - Program/data RAM for soc-minimal-riscv
//
// Written by me. A single 4 KiB word-addressable memory that is loaded
// with the firmware image via $readmemh from the testbench (hierarchical
// reference to the `mem` array below). Read is combinational (same-cycle
// data available at the current address), writes are synchronous and
// byte-strobed so that both `lw`/`sw` (word) and, if ever needed, byte
// stores work correctly.
//
// Address map: this module always assumes it owns byte addresses
// 0x0000_0000 - 0x0000_0FFF (4096 bytes = 1024 words). The address
// decoding itself (deciding *whether* this module should be selected)
// lives in bus.v, not here.

`default_nettype none

module ram (
    input  wire        clk,

    input  wire         sel,     // this module is the target of the current access
    input  wire [31:0]  addr,    // byte address (only bits [11:2] are used)
    input  wire [31:0]  wdata,
    input  wire [3:0]   wstrb,   // per-byte write enable, 0000 = read
    output wire [31:0]  rdata
);

    localparam integer WORDS = 1024; // 1024 * 4 bytes = 4 KiB

    reg [31:0] mem [0:WORDS-1];

    wire [9:0] word_addr = addr[11:2];

    // Combinational read: always reflects the word currently addressed.
    assign rdata = mem[word_addr];

    always @(posedge clk) begin
        if (sel && wstrb != 4'b0000) begin
            if (wstrb[0]) mem[word_addr][7:0]   <= wdata[7:0];
            if (wstrb[1]) mem[word_addr][15:8]  <= wdata[15:8];
            if (wstrb[2]) mem[word_addr][23:16] <= wdata[23:16];
            if (wstrb[3]) mem[word_addr][31:24] <= wdata[31:24];
        end
    end

endmodule
