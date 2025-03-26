
`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/18/2024 01:07:27 PM
// Design Name: 
// Module Name: priority_encoder
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module positive_edge_filter #
(
    parameter WIDTH = 9
)
(
    input  wire                     clk, rst,
    input  wire  [WIDTH-1:0]        data_in,
    output wire  [WIDTH-1:0]        pe_out
);

reg  [WIDTH-1:0] data_prev;

assign pe_out = data_in & ~data_prev;

always @(posedge clk) begin
    if (rst) begin
        data_prev <= 0;
    end else begin
        data_prev <= data_in;
    end
end   

endmodule


