// tb_soc_top.v - Testbench for soc-minimal-riscv
//
// Role of this testbench:
//   - Generates clk/resetn and loads firmware/program.hex into the RAM
//     via $readmemh (hierarchical reference into soc_top.ram_inst.mem).
//   - Plays the part of "the outside computer" on the UART: it snoops
//     the bus every time the CPU writes to UART_TX_DATA, decodes the
//     byte, and assembles/prints the received string on the console
//     with $write, so "HELLO SOC" really shows up when you run vvp.
//   - Drives GPIO_IN with a fixed test value so the firmware's
//     read-GPIO_IN / invert / write-GPIO_OUT round trip has something
//     meaningful to operate on.
//   - Dumps a VCD so GPIO_OUT (and everything else) can be inspected in
//     GTKWave / EPWave.
//   - Ends the simulation with $finish (with a watchdog timeout so it
//     can never hang forever).
//
// ---------------------------------------------------------------------
// WHAT TO LOOK AT IN THE WAVEFORM (waveform.vcd):
//   dut.gpio_out                 -> goes 0x00000000 -> 0xA5A5A5A5
//                                    (first store) -> 0x...  (bitwise
//                                    NOT of GPIO_IN, second store).
//   dut.uart_inst.tx              -> the actual serial bit stream for
//                                    each transmitted character (idle
//                                    high, then start/data/stop bits).
//   dut.uart_inst.busy (state!=0) -> pulses busy while each byte is
//                                    shifting out; the firmware polls
//                                    this through UART_TX_STATUS.
//   dut.mem_addr / mem_wdata      -> every bus transaction the CPU
//                                    issues, useful to see the UART and
//                                    GPIO writes happen in program order.
// ---------------------------------------------------------------------

`timescale 1ns / 1ps
`default_nettype none

module tb_soc_top;

    // ------------------------------------------------------------------
    // Clock / reset : 100 MHz (10 ns period) system clock
    // ------------------------------------------------------------------
    localparam integer CLK_FREQ_HZ = 100_000_000;
    localparam integer BAUD_RATE   = 1_000_000;

    reg clk = 0;
    always #5 clk = ~clk; // 10 ns period -> 100 MHz

    reg resetn = 0;
    initial begin
        resetn = 0;
        repeat (20) @(posedge clk);
        resetn = 1;
    end

    // ------------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------------
    wire        uart_tx_line;
    wire [31:0] gpio_out;
    reg  [31:0] gpio_in;
    wire        trap;

    // Testbench acts as "the outside world": force a known pattern onto
    // GPIO_IN before the CPU ever reads it.
    initial gpio_in = 32'h0000_00C3;

    soc_top #(
        .CLK_FREQ_HZ (CLK_FREQ_HZ),
        .BAUD_RATE   (BAUD_RATE)
    ) dut (
        .clk      (clk),
        .resetn   (resetn),
        .uart_tx  (uart_tx_line),
        .gpio_out (gpio_out),
        .gpio_in  (gpio_in),
        .trap     (trap)
    );

    // ------------------------------------------------------------------
    // Load firmware into RAM
    // ------------------------------------------------------------------
    initial begin
        $readmemh("firmware/program.hex", dut.ram_inst.mem);
    end

    // ------------------------------------------------------------------
    // Waveform dump
    // ------------------------------------------------------------------
    initial begin
        $dumpfile("sim/waveform.vcd");
        $dumpvars(0, tb_soc_top);
    end

    // ------------------------------------------------------------------
    // "Outside computer" on the UART: snoop bus writes to UART_TX_DATA
    // (address 0x1000_0000) and rebuild the transmitted string.
    // ------------------------------------------------------------------
    localparam UART_TX_DATA_ADDR = 32'h1000_0000;
    localparam MSG_LEN           = 10; // "HELLO SOC\n"

    reg [8*64-1:0] rx_string;   // enough room for the received bytes
    integer        rx_count;
    reg            uart_done;

    initial begin
        rx_string = 0;
        rx_count  = 0;
        uart_done = 0;
        $display("---------------------------------------------------------");
        $display("[TB] soc-minimal-riscv simulation starting");
        $display("[TB] Waiting for UART bytes from the CPU...");
        $display("---------------------------------------------------------");
    end

    // A UART_TX_DATA write happens exactly when the bus accepts a write
    // request targeting that address (mem_valid && !mem_ready this cycle,
    // sel_uart, wstrb != 0, offset 0 within the peripheral).
    wire uart_data_write = dut.mem_valid && !dut.mem_ready &&
                           (dut.mem_addr == UART_TX_DATA_ADDR) &&
                           (dut.mem_wstrb != 4'b0000);

    always @(posedge clk) begin
        if (uart_data_write) begin
            rx_string[8*rx_count +: 8] <= dut.mem_wdata[7:0];
            rx_count <= rx_count + 1;
            if (dut.mem_wdata[7:0] == 8'h0A) begin
                // newline received -> whole message is in, print it now
                uart_done <= 1'b1;
            end
        end
    end

    // Print the assembled string once the newline has arrived. Building
    // it byte-by-byte above and printing it as one $write here keeps the
    // console output clean (one "HELLO SOC" line, not one $display per
    // character).
    reg printed;
    initial printed = 0;
    always @(posedge clk) begin
        if (uart_done && !printed) begin
            printed <= 1'b1;
            // rx_count already includes the '\n' itself
            $write("[UART] Received string: \"");
            begin : print_loop
                integer i;
                for (i = 0; i < rx_count; i = i + 1) begin
                    if (rx_string[8*i +: 8] != 8'h0A)
                        $write("%c", rx_string[8*i +: 8]);
                end
            end
            $write("\\n\"\n");
        end
    end

    // ------------------------------------------------------------------
    // Snoop bus writes to GPIO_OUT (address 0x2000_0000) for a console
    // trace of the read-modify-write sequence, in addition to the VCD.
    // ------------------------------------------------------------------
    localparam GPIO_OUT_ADDR = 32'h2000_0000;
    wire gpio_out_write = dut.mem_valid && !dut.mem_ready &&
                          (dut.mem_addr == GPIO_OUT_ADDR) &&
                          (dut.mem_wstrb != 4'b0000);

    integer gpio_write_count;
    initial gpio_write_count = 0;

    always @(posedge clk) begin
        if (gpio_out_write) begin
            gpio_write_count <= gpio_write_count + 1;
            $display("[GPIO] write #%0d @ t=%0t : GPIO_OUT <= 0x%08x",
                      gpio_write_count + 1, $time, dut.mem_wdata);
        end
    end

    // ------------------------------------------------------------------
    // End of test: once the string has been printed and the 2nd GPIO_OUT
    // write has happened, give it a little extra margin, check the final
    // GPIO_OUT value, and finish. A watchdog guarantees $finish is always
    // reached even if something above never happens.
    // ------------------------------------------------------------------
    localparam [31:0] EXPECTED_GPIO_FINAL = ~32'h0000_00C3; // ~gpio_in

    initial begin
        wait (printed == 1'b1);
        wait (gpio_write_count >= 2);
        repeat (10) @(posedge clk);

        $display("---------------------------------------------------------");
        if (gpio_out === EXPECTED_GPIO_FINAL) begin
            $display("[TB] PASS: final GPIO_OUT = 0x%08x (matches ~GPIO_IN)", gpio_out);
        end else begin
            $display("[TB] FAIL: final GPIO_OUT = 0x%08x, expected 0x%08x",
                      gpio_out, EXPECTED_GPIO_FINAL);
        end
        $display("[TB] simulation finished at t=%0t", $time);
        $display("---------------------------------------------------------");
        $finish;
    end

    // Watchdog: never let the simulation run forever.
    initial begin
        #2_000_000; // 2 ms of simulated time, far more than needed
        $display("[TB] WATCHDOG TIMEOUT - simulation did not complete in time!");
        $finish;
    end

endmodule
