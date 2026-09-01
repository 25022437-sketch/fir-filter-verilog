module d_flip_flop (
    input clk;
    input signed [7:0] x_in;
    output signed [7:0] x0, x1, x2, x3, x4;
    ref signed [7:0] x0, x1, x2, x3, x4;
);
    always @(posedge clk) begin
        x0 <= x_in;
        x1 <= x0;
        x2 <= x1;
        x3 <= x2;
        x4 <= x3;
    end
endmodule