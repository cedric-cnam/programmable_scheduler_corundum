module pieo_pre_enq_dynamic #(
    parameter NUM_FIFO = 3,
    parameter FIFO_STATUS_WIDTH = $clog2(4096),
    parameter PKT_LEN_WIDTH = 16,
    parameter TB_SCALE = 4,
    parameter TB_WIDTH = PKT_LEN_WIDTH + TB_SCALE,
    parameter ID_LOG = 2,
    parameter RANK_LOG = 1,
    parameter TIME_LOG = 1
)(
    input  wire                                   clk, rst,

    // from pieo
    input  wire                                   pieo_ready,
    
    // from enq fifo tracker
    input  wire                                   fifos_not_enq_flag,
    input  wire [ID_LOG-1:0]                      fifo_id,
    
    // from fifos
    input wire  [NUM_FIFO*PKT_LEN_WIDTH-1:0]      fifo_packet_length,
    input wire  [NUM_FIFO*FIFO_STATUS_WIDTH-1:0]  fifo_status_depth,
    input wire  [NUM_FIFO-1:0]                    pe_tlast,

    // from parameter store
    input wire  [NUM_FIFO*RANK_LOG-1:0]           fifo_priority,
    input wire  [NUM_FIFO-1:0]                    fifo_enable_shaping,
    /* 
    actual_bit_rate = fifo_max_rate * 8 * 2**-TB_SCALE / 5e-9
    */
    input wire  [NUM_FIFO*PKT_LEN_WIDTH-1:0]      fifo_max_rate,             
    input wire  [NUM_FIFO*PKT_LEN_WIDTH-1:0]      fifo_burst_size,
    input wire  [NUM_FIFO*PKT_LEN_WIDTH-1:0]      fifo_drr_quantum,

    // from wall clk
    input wire  [TIME_LOG-1:0]                    curr_time,

    // to post dequeue
    output wire  [NUM_FIFO*PKT_LEN_WIDTH-1:0]     drr_quantum_shaped,
    
    // to pieo
    output reg  [ID_LOG+RANK_LOG+TIME_LOG-1:0]    pieo_enq_element,
    output reg                                    pieo_enq_trigger
);

integer i;

// Determine the size of next batch of packets to schedule based on the current fifo_status_depth
reg [NUM_FIFO*PKT_LEN_WIDTH-1:0] next_batch_size;

always @(fifo_status_depth,fifo_drr_quantum)begin
    for (i = 0; i < NUM_FIFO; i = i + 1) begin
        next_batch_size[i*PKT_LEN_WIDTH +: PKT_LEN_WIDTH] = 
            fifo_enable_shaping[i] ? 
                (fifo_status_depth[i*FIFO_STATUS_WIDTH +: FIFO_STATUS_WIDTH] > fifo_drr_quantum[i*PKT_LEN_WIDTH +: PKT_LEN_WIDTH]) ? 
                    fifo_drr_quantum[i*PKT_LEN_WIDTH +: PKT_LEN_WIDTH] : 
                    fifo_status_depth[i*FIFO_STATUS_WIDTH +: FIFO_STATUS_WIDTH]
                : fifo_drr_quantum[i*PKT_LEN_WIDTH +: PKT_LEN_WIDTH];
    end
end


/*
    Token Bucket
*/

reg  [TB_WIDTH-1:0] token_bucket       [NUM_FIFO-1:0];
reg  [TB_WIDTH-1:0] token_bucket_inc   [NUM_FIFO-1:0];
reg  [TB_WIDTH-1:0] token_bucket_dec   [NUM_FIFO-1:0];

reg [PKT_LEN_WIDTH-1:0] token_bucket_scaled  [NUM_FIFO-1:0];

always @(posedge clk) begin
    if (rst) begin
        for (i = 0; i < NUM_FIFO; i = i + 1) begin
            token_bucket[i] <= {1'b0, {(TB_WIDTH-1){1'b1}}};
        end
    end else begin
        for (i = 0; i < NUM_FIFO; i = i + 1) begin
            if ( (token_bucket[i] + token_bucket_inc[i]) > (fifo_burst_size[i*PKT_LEN_WIDTH +: PKT_LEN_WIDTH] << TB_SCALE) ) begin
                token_bucket[i] <= (fifo_burst_size[i*PKT_LEN_WIDTH +: PKT_LEN_WIDTH] << TB_SCALE) - token_bucket_dec[i];
            end else begin
                token_bucket[i] <= token_bucket[i] + token_bucket_inc[i] - token_bucket_dec[i];
            end
        end
    end
end

always @(*)begin
    for (i = 0; i < NUM_FIFO; i = i + 1) begin
        // tb updates
        token_bucket_inc[i] = fifo_max_rate[i*PKT_LEN_WIDTH +: PKT_LEN_WIDTH];
        token_bucket_dec[i] = (pe_tlast[i]) ? fifo_packet_length[i*PKT_LEN_WIDTH +: PKT_LEN_WIDTH] << TB_SCALE : 0;
        // downscaled tb
        token_bucket_scaled[i] = token_bucket[i][TB_WIDTH-1 -: PKT_LEN_WIDTH];
    end
end


/*
    Updated DRR quanta to drive the post deq function  
*/

reg  [NUM_FIFO*PKT_LEN_WIDTH-1:0]      post_deq_drr_quantum, post_deq_drr_quantum_next;

always @(posedge clk) begin
    if (rst) begin
        for (i = 0; i < NUM_FIFO; i = i + 1) begin
            post_deq_drr_quantum[i*PKT_LEN_WIDTH +: PKT_LEN_WIDTH] <= {(PKT_LEN_WIDTH){1'b0}};
        end
    end else begin
        for (i = 0; i < NUM_FIFO; i = i + 1) begin
            post_deq_drr_quantum[i*PKT_LEN_WIDTH +: PKT_LEN_WIDTH] <= post_deq_drr_quantum_next[i*PKT_LEN_WIDTH +: PKT_LEN_WIDTH];
        end
    end
end

always @(post_deq_drr_quantum, pieo_enq_trigger) begin
    for (i = 0; i < NUM_FIFO; i = i + 1) begin
        post_deq_drr_quantum_next[i*PKT_LEN_WIDTH +: PKT_LEN_WIDTH] = post_deq_drr_quantum[i*PKT_LEN_WIDTH +: PKT_LEN_WIDTH];
    end

    // When scheduling a fifo, set its quantum to next_batch_size
    if (pieo_enq_trigger) begin
        post_deq_drr_quantum_next[fifo_id*PKT_LEN_WIDTH +: PKT_LEN_WIDTH] = next_batch_size[fifo_id*PKT_LEN_WIDTH +: PKT_LEN_WIDTH];
    end
end

assign drr_quantum_shaped = post_deq_drr_quantum_next;

/*
    Control Logic
*/

reg [RANK_LOG-1:0]   pieo_rank;
reg [TIME_LOG-1:0]   pieo_send_time;

always @(*)begin
    pieo_rank = fifo_priority[fifo_id*RANK_LOG +: RANK_LOG];
    pieo_send_time = 1;

    pieo_enq_element = 0;
    pieo_enq_trigger = 0;
    
    if (pieo_ready && fifos_not_enq_flag) begin
        // if shaping is enabled and there are not enough tokens, postpone send time
        if (fifo_enable_shaping[fifo_id] && (token_bucket_scaled[fifo_id] < next_batch_size[fifo_id*PKT_LEN_WIDTH +: PKT_LEN_WIDTH])) begin
            pieo_send_time = curr_time + 
                            ((next_batch_size[fifo_id*PKT_LEN_WIDTH +: PKT_LEN_WIDTH] - token_bucket_scaled[fifo_id]) << TB_SCALE) /
                            fifo_max_rate[fifo_id*PKT_LEN_WIDTH +: PKT_LEN_WIDTH];
        end

        pieo_enq_element = {pieo_send_time, pieo_rank, fifo_id};
        pieo_enq_trigger = 1;
    end
end

endmodule
