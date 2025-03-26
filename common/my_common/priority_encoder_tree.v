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

module priority_encoder_tree #
(
    parameter WIDTH = 64,
    parameter EN_REVERSE = 0    // Reverse input in the root encoder to encode LSB first 
)
(
    input  wire [WIDTH-1:0]         input_unencoded,
    output wire                     output_valid,
    output wire [$clog2(WIDTH)-1:0] output_encoded
);

// reverse input
wire [WIDTH-1:0]         unencoded_word;
wire [$clog2(WIDTH)-1:0] encoded_word;

genvar i;
generate
    if (EN_REVERSE == 1) begin
        for (i = 0; i < WIDTH; i = i + 1) begin
            assign unencoded_word[i] = input_unencoded[WIDTH-1-i];
        end
        assign output_encoded = WIDTH-1 - encoded_word;
    end else begin
        assign unencoded_word = input_unencoded;
        assign output_encoded = encoded_word;
    end
endgenerate

// power-of-two width
localparam W1 = 2**$clog2(WIDTH);
localparam W2 = W1/2;

generate
    if (WIDTH == 1) begin
        // one input
        assign output_valid = unencoded_word;
        assign encoded_word = 0;
    end else if (WIDTH == 2) begin
        // two inputs
        assign output_valid = |unencoded_word;
        assign encoded_word = unencoded_word[1];
    end else begin
        // more than two inputs - split into two parts and recurse
        // also pad input to correct power-of-two width
        wire [$clog2(W2)-1:0] out1, out2;
        wire valid1, valid2;
        priority_encoder_tree #(
            .WIDTH(W2)
        )
        priority_encoder_lo (
            .input_unencoded(unencoded_word[W2-1:0]),
            .output_valid(valid1),
            .output_encoded(out1)
        );
        priority_encoder_tree #(
            .WIDTH(W2)
        )
        priority_encoder_hi (
            .input_unencoded({{W1-WIDTH{1'b0}}, unencoded_word[WIDTH-1:W2]}),
            .output_valid(valid2),
            .output_encoded(out2)
        );
        // multiplexer to select part
        assign output_valid = valid1 | valid2;
        assign encoded_word = valid2 ? {1'b1, out2} : {1'b0, out1};
    end
endgenerate
endmodule


