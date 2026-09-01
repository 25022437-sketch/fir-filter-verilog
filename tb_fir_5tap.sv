`timescale 1ns/1ps

module tb_fir_5tap;

    reg clk;
    reg rst_n;
    reg signed [7:0] x_in;
    wire signed [7:0] y_out;

    fir_5tap uut (
        .clk(clk),
        .rst_n(rst_n),
        .x_in(x_in),
        .y_out(y_out)
    );

    always #5 clk = ~clk;

    initial begin
        $dumpfile("waveform.vcd");
        $dumpvars(0, tb_fir_5tap);
    end

    initial begin
        clk = 0;
        rst_n = 0;
        x_in = 0;

        #15 rst_n = 1;

        #10 x_in = 8'sd10;
        #10 x_in = 8'sd10;
        #10 x_in = 8'sd10;
        #10 x_in = 8'sd10;
        #10 x_in = 8'sd10;
        #10 x_in = 8'sd10;

        #10 x_in = 8'sd0;
        #10 x_in = 8'sd0;
        #10 x_in = 8'sd0;
        #10 x_in = 8'sd0;
        #10 x_in = 8'sd0;

        #30 $finish;
    end

endmodule
