
`timescale 1ns / 1ps

module sticky_en_register #
(
    parameter WIDTH = 8,
    parameter DEFAULT_OUT = 0
)
(
    input  wire                     clk, rst, en, 
    input  wire                     valid_in,
    input  wire  [WIDTH-1:0]        data_in,
    output reg   [WIDTH-1:0]        data_out
);

reg en_reg;

always @(posedge clk) begin
    if (rst) begin
        en_reg      <= 1'b0;
        data_out    <= DEFAULT_OUT;
    end else begin           
        if (en_reg && valid_in) begin
            data_out <= data_in;    // Store data when valid_in is 1
            en_reg <= 0;            // Clear enable after storing data
        end else if (en) begin
            en_reg <= 1;            // Latch enable when en goes high
        end
    end
end
endmodule