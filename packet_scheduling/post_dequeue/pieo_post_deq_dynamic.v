module pieo_post_deq_dynamic #(
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

wire  [ID_LOG-1:0]   pieo_deq_id;
assign pieo_deq_id = deq_element[ID_LOG-1 : 0];

/*
    Token Bucket
*/

wire        [TB_WIDTH-1:0]      fifo_quantum_scaled      [NUM_QUEUES-1:0];
wire        [TB_WIDTH-1:0]      fifo_pkt_len_scaled      [NUM_QUEUES-1:0];

reg  signed [TB_WIDTH:0]        token_bucket             [NUM_QUEUES-1:0];
wire signed [TB_WIDTH:0]        tb_update                [NUM_QUEUES-1:0];
wire signed [TB_WIDTH:0]        tb_cap                   [NUM_QUEUES-1:0];

wire        [TB_WIDTH-1:0]      token_bucket_inc         [NUM_QUEUES-1:0];
wire        [TB_WIDTH-1:0]      token_bucket_dec         [NUM_QUEUES-1:0];

reg         [TB_WIDTH-1:0]      token_bucket_inc_r       [NUM_QUEUES-1:0];
reg         [TB_WIDTH-1:0]      token_bucket_dec_r       [NUM_QUEUES-1:0];

reg         [NUM_QUEUES-1:0]    tb_fill_trigger, tb_dec_trigger;

genvar j;
generate
    for (j = 0; j < NUM_QUEUES; j = j + 1) begin : TOKEN_BUCKET_UPDATE
        // scaling
        assign fifo_quantum_scaled[j] = {fifo_drr_quantum  [j*PKT_LEN_WIDTH +: PKT_LEN_WIDTH], {TB_SCALE{1'b0}}};
        assign fifo_pkt_len_scaled[j] = {fifo_packet_length[j*PKT_LEN_WIDTH +: PKT_LEN_WIDTH], {TB_SCALE{1'b0}}};
        // tb_update calculation
        assign token_bucket_inc[j] = (fifo_enable_shaping[j]) ? fifo_max_rate[j*PKT_LEN_WIDTH +: PKT_LEN_WIDTH] :
                                     (tb_fill_trigger[j]) ? fifo_quantum_scaled[j] : 0;
        assign token_bucket_dec[j] = (tb_dec_trigger[j])  ? fifo_pkt_len_scaled[j] : 0;
        assign tb_update[j] = $signed(token_bucket[j] + token_bucket_inc_r[j] - token_bucket_dec_r[j]);
        assign tb_cap[j]    = $signed({1'b0, fifo_quantum_scaled[j]});
        // register update
        always @(posedge clk) begin
            if (rst) begin
                token_bucket[j] <= 0;
                token_bucket_inc_r[j] <= 0;
                token_bucket_dec_r[j] <= 0;
            end else begin
                token_bucket[j] <= (tb_update[j] > tb_cap[j]) ? tb_cap[j] : tb_update[j];
                token_bucket_inc_r[j] <= token_bucket_inc[j];
                token_bucket_dec_r[j] <= token_bucket_dec[j];
            end
        end
    end
endgenerate


/*
    MAIN FSM
*/

reg                     post_deq_ready_next;
reg [NUM_QUEUES-1:0]    tb_fifo_eligible_next;
reg [NUM_QUEUES-1:0]    post_deq_end_next;
reg [ID_LOG-1:0]        sel_r, sel_next_r;
reg                     en_r,  en_next_r;

// FSM States
localparam IDLE = 0, SEND = 1, CHECK_QUEUE_EMPTY = 2;
reg [1:0] current_state, next_state;

always @(posedge clk) begin
    if (rst) begin
        current_state       <= IDLE;
        post_deq_ready      <= 1'b1;
        tb_fifo_eligible    <= 0;
        post_deq_end        <= 0;
        sel_r               <= 0;
        en_r                <= 1'b0;
    end else begin
        current_state       <= next_state;
        post_deq_ready      <= post_deq_ready_next;
        tb_fifo_eligible    <= tb_fifo_eligible_next;
        post_deq_end        <= post_deq_end_next;
        sel_r               <= sel_next_r;
        en_r                <= en_next_r;
    end
end

integer i;
always @(*)begin
    // Defaults
    next_state = current_state;
    post_deq_ready_next = post_deq_ready;
    
    tb_fill_trigger = 0;
    tb_dec_trigger = 0;
    
    post_deq_end_next = 0;
    
    sel_next_r = sel_r;
    sel_out    = sel_r;
    en_next_r  = en_r;
    en_out     = en_r;

    for (i = 0; i < NUM_QUEUES; i = i + 1) begin
        tb_fifo_eligible_next[i] = ~fifo_enable_shaping[i] | ( token_bucket[i] > $signed({1'b0, fifo_pkt_len_scaled[i]}) );
    end
    
    case(current_state)
    
        IDLE: begin
            // wait for new fifo to be scheduled
            if (deq_valid) begin
                // If the fifo is not shaped, fill the token bucket
                tb_fill_trigger[pieo_deq_id] = 1'b1;
                // schedule fifo and go to SEND state
                sel_next_r = pieo_deq_id;
                sel_out    = pieo_deq_id;
                en_next_r  = 1'b1;
                en_out     = 1'b1;
                next_state = SEND;
                post_deq_ready_next = 1'b0;
            end
        end
        
        SEND : begin
            if (pe_tlast[sel_r]) begin
                // After each pkt, decrement the related bucket
                tb_dec_trigger[sel_r] = 1'b1;
                en_next_r  = 1'b0;
                // If the bucket will become negative (check MSB of tb_update), go to IDLE
                if (tb_update[sel_r][TB_WIDTH]) begin
                    next_state = IDLE;
                    post_deq_ready_next = 1'b1;
                    post_deq_end_next[sel_r] = 1'b1;
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
            // Otherwise go back to IDLE and, if the queue is not shaped, fill its bucket
            end else begin
                next_state = IDLE;
                post_deq_ready_next = 1'b1;
                post_deq_end_next[sel_r] = 1'b1;
                tb_fill_trigger[pieo_deq_id] = 1'b1;
            end
        end
    
    endcase
end

endmodule