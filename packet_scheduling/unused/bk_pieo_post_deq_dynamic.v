module pieo_post_deq_dynamic_bk #(
    parameter PKT_LEN_WIDTH = 16,
    parameter TB_SCALE = 4,
    parameter TB_WIDTH = PKT_LEN_WIDTH + TB_SCALE,
    parameter NUM_QUEUES = 3,
    parameter ID_LOG = $clog2(NUM_QUEUES),
    parameter RANK_LOG = 1,
    parameter TIME_LOG = 1
)(
    input  wire                                   clk, rst, 
    input  wire                                   en_in,
    
    // sched fifo buffer interface
    output  reg                                   post_deq_ready,
    input  wire                                   deq_valid,
    input  wire  [ID_LOG+RANK_LOG+TIME_LOG-1:0]   deq_element,
    
    // from fifos
    input wire [NUM_QUEUES-1:0]                   fifo_tvalid,
    input wire [NUM_QUEUES-1:0]                   pe_tlast,
    input wire [NUM_QUEUES*PKT_LEN_WIDTH-1:0]     fifo_packet_length,
    
    // to enq fifo tracker
    output reg [NUM_QUEUES-1:0]                   tb_fifo_eligible,
    output reg [NUM_QUEUES-1:0]                   post_deq_end,

    // from parameter store
    input wire [NUM_QUEUES*PKT_LEN_WIDTH-1:0]     fifo_drr_quantum,
    input wire [NUM_QUEUES-1:0]                   fifo_enable_shaping,
    input wire [NUM_QUEUES*PKT_LEN_WIDTH-1:0]     fifo_max_rate,
  
    // to mux
    output reg [ID_LOG-1:0]                       sel_out,
    output reg                                    en_out                           
);

integer i;

wire  [ID_LOG-1:0]   pieo_deq_id;
assign pieo_deq_id = deq_element[ID_LOG-1 : 0];

/*
    Token Bucket
*/

reg signed  [TB_WIDTH:0]   token_bucket                [NUM_QUEUES-1:0];
reg         [TB_WIDTH-1:0] token_bucket_inc            [NUM_QUEUES-1:0];
reg         [TB_WIDTH-1:0] token_bucket_dec            [NUM_QUEUES-1:0];

reg         [TB_WIDTH-1:0] token_bucket_dec_cumul      [NUM_QUEUES-1:0];
reg         [TB_WIDTH-1:0] token_bucket_dec_cumul_next [NUM_QUEUES-1:0];


reg signed  [PKT_LEN_WIDTH:0] token_bucket_scaled  [NUM_QUEUES-1:0];


wire signed  [TB_WIDTH:0] w_token_bucket;
assign w_token_bucket = token_bucket[sel_r];                  // Debug purpose

wire signed  [PKT_LEN_WIDTH:0] w_token_bucket_scaled;
assign w_token_bucket_scaled = token_bucket_scaled[sel_r];    // Debug purpose

always @(posedge clk) begin
    if (rst) begin
        for (i = 0; i < NUM_QUEUES; i = i + 1) begin
            //token_bucket[i] <= {1'b0, {(TB_WIDTH){1'b1}}};
            token_bucket[i] <= 0;
        end
    end else begin
        for (i = 0; i < NUM_QUEUES; i = i + 1) begin
            if ( $signed(token_bucket[i] + token_bucket_inc[i] - token_bucket_dec[i]) > $signed({1'b0,fifo_drr_quantum[i*PKT_LEN_WIDTH +: PKT_LEN_WIDTH], {TB_SCALE{1'b0}}}) ) begin
                token_bucket[i] <= ({fifo_drr_quantum[i*PKT_LEN_WIDTH +: PKT_LEN_WIDTH],{TB_SCALE{1'b0}}});
            end else begin
                token_bucket[i] <= token_bucket[i] + token_bucket_inc[i] - token_bucket_dec[i];
            end
        end
    end
end


/*
    MAIN FSM
*/

reg                 post_deq_ready_r,  post_deq_ready_next_r;
reg [ID_LOG-1:0]    sel_r, sel_next_r;
reg                 en_r,  en_next_r;


// FSM States
localparam IDLE = 0, SEND = 1, CHECK_QUEUE_EMPTY = 2;
reg [1:0] current_state, next_state;

always @(posedge clk) begin
    if (rst) begin
        current_state       <= IDLE;
        post_deq_ready_r    <= 1'b1;
        sel_r               <= 0;
        en_r                <= 1'b0;
    end else begin
        current_state       <= next_state;
        post_deq_ready_r    <= post_deq_ready_next_r;       // DA VALUTARE EFFETTO
        sel_r               <= sel_next_r;
        en_r                <= en_next_r;
    end
end

always @(*)begin
    // Default
    next_state = current_state;
    post_deq_ready_next_r = post_deq_ready_r;
    post_deq_ready = post_deq_ready_r;
    post_deq_end = 0;
    
    sel_next_r = sel_r;
    sel_out    = sel_r;
    en_next_r  = en_r;
    en_out     = en_r;

    for (i = 0; i < NUM_QUEUES; i = i + 1) begin
        // tb updates
        token_bucket_inc[i] = (fifo_enable_shaping[i]) ? fifo_max_rate[i*PKT_LEN_WIDTH +: PKT_LEN_WIDTH] : 0;
        token_bucket_dec[i] = 0;
        // downscaled tb
        token_bucket_scaled[i] = token_bucket[i] >>> TB_SCALE;
        // determine eligible fifos
        tb_fifo_eligible[i] = ~fifo_enable_shaping[i] | 
                              $signed(token_bucket_scaled[i]) > $signed(fifo_packet_length[i*PKT_LEN_WIDTH +: PKT_LEN_WIDTH]);
    end
    
    case(current_state)
    
        IDLE: begin
            if (en_in) begin
                // wait for new fifo to be scheduled
                if (deq_valid) begin
                    // If the fifo is not shaped, add the quantum to the token bucket
                    if (~fifo_enable_shaping[pieo_deq_id]) begin
                        token_bucket_inc[pieo_deq_id] = {fifo_drr_quantum[pieo_deq_id*PKT_LEN_WIDTH +: PKT_LEN_WIDTH],{TB_SCALE{1'b0}}};
                    end
                    sel_next_r = pieo_deq_id;
                    sel_out    = pieo_deq_id;
                    en_next_r  = 1'b1;
                    en_out     = 1'b1;
                    next_state = SEND;
                    post_deq_ready_next_r = 1'b0;
                end
            end
        end
        
        SEND : begin
            if (pe_tlast[sel_r]) begin
                // After each pkt, remove tokens equal to its length from the related bucket
                token_bucket_dec[sel_r] = {fifo_packet_length[sel_r*PKT_LEN_WIDTH +: PKT_LEN_WIDTH],{TB_SCALE{1'b0}}};
                en_next_r  = 1'b0;
                // If the bucket will become negative, go to IDLE
                if (token_bucket[sel_r] + token_bucket_inc[sel_r] <= token_bucket_dec[sel_r]) begin
                    next_state = IDLE;
                    post_deq_ready_next_r = 1'b1;
                    post_deq_end[sel_r] = 1'b1;
                // If the enable is not active anymore, go to IDLE and, if the queue is not shaped, add the quantum to the token bucket to reset it
                end else if (~en_in) begin
                    next_state = IDLE;
                    post_deq_ready_next_r = 1'b1;
                    post_deq_end[sel_r] = 1'b1;
                    if (~fifo_enable_shaping[sel_r]) begin
                        token_bucket_inc[sel_r] = {fifo_drr_quantum[sel_r*PKT_LEN_WIDTH +: PKT_LEN_WIDTH],{TB_SCALE{1'b0}}};
                    end
                // Otherwise, check if there is another packet
                end else begin
                    next_state = CHECK_QUEUE_EMPTY;
                end 
            end
        end
        
        CHECK_QUEUE_EMPTY : begin
            // If there is another pkt in the current fifo, go back to SEND
            if (fifo_tvalid[sel_r]) begin
                next_state = SEND;
                en_next_r  = 1'b1;
                en_out     = 1'b1;
            // Otherwise go back to IDLE and, if the queue is not shaped, add the quantum to the token bucket to reset it
            end else begin
                next_state = IDLE;
                post_deq_ready_next_r = 1'b1;
                post_deq_end[sel_r] = 1'b1;
                if (~fifo_enable_shaping[sel_r]) begin
                    token_bucket_inc[sel_r] = {fifo_drr_quantum[sel_r*PKT_LEN_WIDTH +: PKT_LEN_WIDTH],{TB_SCALE{1'b0}}};
                end
            end
        end
    
    endcase
end

endmodule
