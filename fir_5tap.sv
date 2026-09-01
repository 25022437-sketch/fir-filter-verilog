module fir_5tap (
    input  wire clk,
    input  wire rst_n,
    input  wire signed [7:0] x_in,
    output reg  signed [7:0] y_out
);

    reg signed [7:0] d0, d1, d2, d3, d4;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            d0 <= 8'sd0;
            d1 <= 8'sd0;
            d2 <= 8'sd0;
            d3 <= 8'sd0;
            d4 <= 8'sd0;
        end else begin
            d0 <= x_in;
            d1 <= d0;
            d2 <= d1;
            d3 <= d2;
            d4 <= d3;
        end
    end

    wire signed [10:0] sum;
    assign sum = d0 + d1 + d2 + d3 + d4;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y_out <= 8'sd0;
        end else begin
            y_out <= sum / 5;
        end
    end

endmodule
