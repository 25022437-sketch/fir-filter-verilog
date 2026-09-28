// uart_tx.v - Memory-mapped UART transmitter (TX only), written from scratch.
//
// This is real transmitter RTL (start bit, 8 data bits LSB-first, 1 stop
// bit, no parity), not a behavioral shortcut. It is driven by a simple
// baud-rate clock divider so the simulation can run at whatever baud rate
// is convenient (default: 1 Mbps assuming a 100 MHz system clock).
//
// Register map (word offset from the peripheral's base address, see
// bus.v for the base address itself):
//   0x0  TX_DATA   (write)      : write a byte -> starts sending it.
//                                 Ignored while busy (firmware must poll
//                                 TX_STATUS first).
//   0x4  TX_STATUS (read)       : bit 0 = busy (1 while a frame is being
//                                 shifted out on `tx`).
//
// There is no RX side: the spec only requires TX to demonstrate a
// self-written peripheral.

`default_nettype none

module uart_tx #(
    parameter integer CLK_FREQ_HZ = 100_000_000,
    parameter integer BAUD_RATE   = 1_000_000
) (
    input  wire        clk,
    input  wire        resetn,

    input  wire         sel,      // this module is the target of the current access
    input  wire [31:0]  addr,     // byte address, only addr[3:0] (register offset) is used
    input  wire [31:0]  wdata,
    input  wire [3:0]   wstrb,    // per-byte write enable, 0000 = read
    output reg  [31:0]  rdata,

    output reg          tx        // serial line, idles high
);

    localparam integer CLKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE;
    localparam integer DIV_WIDTH    = $clog2(CLKS_PER_BIT + 1);

    localparam [1:0] ST_IDLE  = 2'd0,
                      ST_START = 2'd1,
                      ST_DATA  = 2'd2,
                      ST_STOP  = 2'd3;

    reg [1:0]              state;
    reg [DIV_WIDTH-1:0]     div_cnt;
    reg [2:0]               bit_idx;
    reg [7:0]                shift_reg;

    wire busy = (state != ST_IDLE);

    wire wr_tx_data = sel && (addr[3:0] == 4'h0) && (wstrb != 4'b0000);

    // ------------------------------------------------------------------
    // Register readback: TX_STATUS.bit0 = busy. TX_DATA reads back as 0.
    // ------------------------------------------------------------------
    always @* begin
        case (addr[3:0])
            4'h4:    rdata = {31'b0, busy};
            default: rdata = 32'h0000_0000;
        endcase
    end

    // ------------------------------------------------------------------
    // Transmit shift register / baud generator
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (!resetn) begin
            state     <= ST_IDLE;
            tx        <= 1'b1;      // line idle = high
            div_cnt   <= 0;
            bit_idx   <= 0;
            shift_reg <= 8'h00;
        end else begin
            case (state)
                ST_IDLE: begin
                    tx <= 1'b1;
                    if (wr_tx_data) begin
                        shift_reg <= wdata[7:0];
                        state     <= ST_START;
                        div_cnt   <= 0;
                    end
                end

                ST_START: begin
                    tx <= 1'b0; // start bit
                    if (div_cnt == CLKS_PER_BIT - 1) begin
                        div_cnt <= 0;
                        bit_idx <= 0;
                        state   <= ST_DATA;
                    end else begin
                        div_cnt <= div_cnt + 1'b1;
                    end
                end

                ST_DATA: begin
                    tx <= shift_reg[0];
                    if (div_cnt == CLKS_PER_BIT - 1) begin
                        div_cnt   <= 0;
                        shift_reg <= {1'b0, shift_reg[7:1]};
                        if (bit_idx == 3'd7) begin
                            state <= ST_STOP;
                        end else begin
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end else begin
                        div_cnt <= div_cnt + 1'b1;
                    end
                end

                ST_STOP: begin
                    tx <= 1'b1; // stop bit
                    if (div_cnt == CLKS_PER_BIT - 1) begin
                        div_cnt <= 0;
                        state   <= ST_IDLE;
                    end else begin
                        div_cnt <= div_cnt + 1'b1;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
