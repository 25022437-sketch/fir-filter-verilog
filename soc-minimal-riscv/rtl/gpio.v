// gpio.v - Memory-mapped GPIO controller, written from scratch.
//
// Two 32-bit registers:
//   0x0  GPIO_OUT (read/write) : software-controlled output register.
//                                 Watch this one in the waveform viewer.
//   0x4  GPIO_IN  (read-only)  : reflects the `gpio_in` input port, which
//                                 the testbench drives directly to
//                                 simulate external stimulus (buttons,
//                                 sensors, ...). Writes to this offset
//                                 are ignored.

`default_nettype none

module gpio (
    input  wire        clk,
    input  wire        resetn,

    input  wire         sel,     // this module is the target of the current access
    input  wire [31:0]  addr,    // byte address, only addr[3:0] (register offset) is used
    input  wire [31:0]  wdata,
    input  wire [3:0]   wstrb,   // per-byte write enable, 0000 = read
    output reg  [31:0]  rdata,

    output reg  [31:0]  gpio_out, // memory-mapped output register (drive LEDs/etc in real HW)
    input  wire [31:0]  gpio_in   // external input value, forced by the testbench
);

    wire wr_out = sel && (addr[3:0] == 4'h0) && (wstrb != 4'b0000);

    always @(posedge clk) begin
        if (!resetn) begin
            gpio_out <= 32'h0000_0000;
        end else if (wr_out) begin
            if (wstrb[0]) gpio_out[7:0]   <= wdata[7:0];
            if (wstrb[1]) gpio_out[15:8]  <= wdata[15:8];
            if (wstrb[2]) gpio_out[23:16] <= wdata[23:16];
            if (wstrb[3]) gpio_out[31:24] <= wdata[31:24];
        end
    end

    always @* begin
        case (addr[3:0])
            4'h0:    rdata = gpio_out;
            4'h4:    rdata = gpio_in;
            default: rdata = 32'h0000_0000;
        endcase
    end

endmodule
