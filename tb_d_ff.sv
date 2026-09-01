module d_flip_flop_tb (
    reg clk;
    reg signed x_in;
    wire signed x0, x1, x2, x3, x4;
);
    d_flip_flop uut (
        .clk(clk);
        .x_in(x_in);
        .x0(x0);
        .x1(x1);
        .x2(x2);
        .x3(x3);
        .x4(x4);
);
    always #5 clk = ~clk;
    initial begin
        clk = 0;
        x_in = 0;
        x_in = 3;
        x_in = 7;
        x_in = 2;
        x_in = 9;
        x_in = 5;
        $finish;
    end
    
endmodule