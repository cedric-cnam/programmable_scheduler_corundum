module find_next_valid #(
    parameter INPUT_WIDTH = 3,
    parameter SEL_WIDTH = $clog2(INPUT_WIDTH)
)(
    input  wire [INPUT_WIDTH-1:0]   all_valid,
    input  wire [SEL_WIDTH-1:0]     curr_valid,
    output wire [SEL_WIDTH-1:0]     next_valid,
    output                          found
);
    
    reg  [INPUT_WIDTH-1:0]  left_masked_all_valid, right_masked_all_valid;
    wire [INPUT_WIDTH-1:0]  mask;
    wire [SEL_WIDTH-1:0] left_reversed_encoded, right_reversed_encoded;
    wire left_found, right_found;

    // Generate mask with all bits set to 1 up to curr_valid
    assign mask = ((1 << (curr_valid + 1)) - 1);
    
    // Apply the mask to all_valid
    always @(*) begin
        left_masked_all_valid  = all_valid & ~mask;
        right_masked_all_valid = all_valid &  mask;
        right_masked_all_valid[curr_valid] = 0;
    end
    
    
    // Priority encode the masked results to find the next '1'
    // Left
    priority_encoder_tree #(
        .WIDTH(INPUT_WIDTH),
        .EN_REVERSE(1)
    ) left_priority_encoder (
        .input_unencoded(left_masked_all_valid),
        .output_valid(left_found),
        .output_encoded(left_reversed_encoded)
    );
    // Right
    priority_encoder_tree #(
        .WIDTH(INPUT_WIDTH),
        .EN_REVERSE(1)
    ) right_priority_encoder (
        .input_unencoded(right_masked_all_valid),
        .output_valid(right_found),
        .output_encoded(right_reversed_encoded)
    );

    assign found = left_found | right_found;
    assign next_valid = left_found ? left_reversed_encoded : (right_found ? right_reversed_encoded : 0);
    
endmodule
