
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

module wall_clock #
(
    parameter TIME_LOG = 32
)
(

    input  wire                     clk, rst,
    output reg  [TIME_LOG-1:0]      curr_time

);


always @(posedge clk) begin
    if (rst) begin
        curr_time <= 0;
    end else begin
        curr_time <= curr_time + 1;
    end
end

endmodule


