module fifo_enqueue_tracker #(
    parameter NUM_FIFO = 4,       // Number of FIFOs
    parameter SEL_WIDTH = $clog2(NUM_FIFO)  // Width of the selector signal
)(
    input  wire                   clk, rst,

    // Control signals
    input  wire [NUM_FIFO-1:0]    fifo_valid,
    input  wire [NUM_FIFO-1:0]    fifo_eligible,
    input  wire                   pieo_enq_trigger,
    input  wire [NUM_FIFO-1:0]    post_deq_end,

    // Outputs
    output reg                    fifo_to_enqueue_valid, 
    output reg [SEL_WIDTH-1:0]    fifo_to_enqueue
);

    // Internal signals
    wire [SEL_WIDTH-1:0]    fifo_to_enqueue_next_w;
    wire                    found_fifo_to_enq;
    reg  [SEL_WIDTH-1:0]    fifo_to_enqueue_next_r;
    reg  [NUM_FIFO-1:0]     fifo_enqueued_mask_r,      fifo_enqueued_mask_next;

    // Compute FIFOs that are eligible but not enqueued yet
    wire [NUM_FIFO-1:0] fifo_not_enqueued_w;
    assign fifo_not_enqueued_w = ~fifo_enqueued_mask_r & fifo_valid & fifo_eligible;

    // Register update
    always @(posedge clk) begin
        if (rst) begin
            fifo_to_enqueue_valid   <= 1'b0;
            fifo_to_enqueue         <= {SEL_WIDTH{1'b0}};
            fifo_enqueued_mask_r    <= {NUM_FIFO{1'b0}};
        end else begin
            fifo_to_enqueue_valid   <= |fifo_not_enqueued_w;
            fifo_to_enqueue         <= fifo_to_enqueue_next_r;
            fifo_enqueued_mask_r    <= fifo_enqueued_mask_next;
        end
    end    

    // Find next FIFO to enqueue
    find_next_valid #(
        .INPUT_WIDTH(NUM_FIFO)
    ) find_next_valid_inst (
        .all_valid(fifo_not_enqueued_w),
        .curr_valid(fifo_to_enqueue),
        .next_valid(fifo_to_enqueue_next_w),
        .found(found_fifo_to_enq)
    );

    // Combinational logic
    always @(*) begin
        // Default assignments
        fifo_enqueued_mask_next = fifo_enqueued_mask_r;
        fifo_to_enqueue_next_r = fifo_to_enqueue;

        // Update FIFO to enqueue if a valid one is found
        if (found_fifo_to_enq) begin
            fifo_to_enqueue_next_r = fifo_to_enqueue_next_w;
        end

        // Update enqueued FIFOs after a dequeue ends
        if (post_deq_end) begin
            fifo_enqueued_mask_next = fifo_enqueued_mask_r & ~post_deq_end;
        end

        // Update enqueued FIFOs when enqueue is triggered
        if (pieo_enq_trigger) begin
            fifo_enqueued_mask_next[fifo_to_enqueue] = 1'b1;
        end
    end

endmodule