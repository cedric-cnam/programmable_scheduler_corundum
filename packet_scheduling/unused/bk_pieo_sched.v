module pieo_sched #(
    // scheduler parameters
    parameter PORT_COUNT = 3,
    parameter N_FIFO_PER_PORT = 3,
    parameter NUM_FIFO = PORT_COUNT*N_FIFO_PER_PORT,
    parameter FIFO_STATUS_WIDTH = $clog2(4096),
    parameter PKT_LEN_WIDTH = 16,
    parameter SEL_WIDTH = $clog2(NUM_FIFO),
    parameter TB_SCALE = 4,
    // pieo parameters
    parameter ID_LOG = SEL_WIDTH,
    parameter LIST_SIZE = (2**ID_LOG),
    parameter RANK_LOG = ID_LOG,
    parameter TIME_LOG = 32,
    parameter NUM_OF_ELEMENTS_PER_SUBLIST = 1+(2**(ID_LOG/2)),  //sqrt(LIST_SIZE)
    parameter NUM_OF_SUBLIST = (2*NUM_OF_ELEMENTS_PER_SUBLIST)
)
(
    input wire                                      clk, rst, en_in,
    
    input wire  [TIME_LOG-1:0]                      curr_time,
    
    // from fifos
    input wire  [NUM_FIFO-1:0]                      fifo_tvalid,
    input wire  [NUM_FIFO*PKT_LEN_WIDTH-1:0]        fifo_packet_length,
    input wire  [NUM_FIFO*FIFO_STATUS_WIDTH-1:0]    fifo_status_depth,
    input wire  [NUM_FIFO-1:0]                      pe_tlast,

    // from parameter store
    input wire  [NUM_FIFO*RANK_LOG-1:0]             fifo_priority,
    input wire  [NUM_FIFO-1:0]                      fifo_enable_shaping,
    input wire  [NUM_FIFO*PKT_LEN_WIDTH-1:0]        fifo_max_rate,             
    input wire  [NUM_FIFO*PKT_LEN_WIDTH-1:0]        fifo_starvation_timeout,
    input wire  [NUM_FIFO*PKT_LEN_WIDTH-1:0]        fifo_drr_quantum,

    // to mux
    output wire [SEL_WIDTH-1:0]                     sel_out,
    output wire                                     en_out
);

wire                                    pieo_ready_w;
wire                                    pieo_empty_w;
wire                                    pieo_enq_trigger_w;       
wire [ID_LOG+RANK_LOG+TIME_LOG-1:0]     pieo_enq_element_w;    
wire                                    pieo_deq_trigger_w;    
wire                                    pieo_deq_valid_w;
wire [ID_LOG+RANK_LOG+TIME_LOG-1:0]     pieo_deq_element_w;


/*
    TRACK ENQUEUED FIFOS AND DETERMINE FIFO TO ENQUEUE NEXT
*/

wire [NUM_FIFO-1:0]     post_deq_end_w;
wire [NUM_FIFO-1:0]     tb_fifo_eligible_w;

wire [NUM_FIFO-1:0]     fifos_not_enqueued_w;
wire [SEL_WIDTH-1:0]    fifo_to_enqueue_w;

fifo_enqueue_tracker #(
    .NUM_FIFO(NUM_FIFO)
) fifo_enqueue_tracker_inst (
    .clk(clk),
    .rst(rst),
    //// Control signals ////
    .fifos_valid(fifo_tvalid),
    .tb_fifo_eligible(tb_fifo_eligible_w),
    .pieo_enq_trigger(pieo_enq_trigger_w),
    .post_deq_end(post_deq_end_w),
    //// Outputs ////
    .fifos_not_enqueued(fifos_not_enqueued_w),
    .fifo_to_enqueue(fifo_to_enqueue_w)
);


/*
    DETERMINE PIEO REQDY
*/
/*
wire is_pieo_ready_w; 

determine_if_ready determine_pieo_ready (
    .clk(clk),
    .rst(rst),
    .trigger1(pieo_enq_trigger_w),
    .trigger2(pieo_deq_trigger_w),
    .valid1(pieo_ready_w),
    .valid2(pieo_deq_valid_w),
    .ready(is_pieo_ready_w)    
);
*/

/*
    PRE ENQUEUE FUNCTION
*/

wire  [NUM_FIFO*PKT_LEN_WIDTH-1:0]     drr_quantum_shaped;

pieo_pre_enq_priority #(
    .NUM_FIFO(NUM_FIFO),
    .ID_LOG(ID_LOG),
    .RANK_LOG(RANK_LOG),
    .TIME_LOG(TIME_LOG)
) pieo_pre_enq_inst (
    //// from fifos ////
    .fifos_not_enq_flag(|fifos_not_enqueued_w),
    .fifo_id(~(~fifo_to_enqueue_w)),    //
    //// from parameter store ////
    .fifo_priority(fifo_priority),
    //// from/to pieo ////
    .pieo_ready(~(~pieo_ready_w)),
    //.pieo_ready(is_pieo_ready_w),
    .pieo_enq_element(pieo_enq_element_w),
    .pieo_enq_trigger(pieo_enq_trigger_w)
);


/*
    PIEO QUEUE
*/

pieo #(
    .LIST_SIZE(LIST_SIZE),
    .RANK_LOG(RANK_LOG),
    .TIME_LOG(TIME_LOG),
    .NUM_OF_ELEMENTS_PER_SUBLIST(NUM_OF_ELEMENTS_PER_SUBLIST),      //sqrt(LIST_SIZE)
    .NUM_OF_SUBLIST(NUM_OF_SUBLIST)                                 //2*NUM_OF_ELEMENTS_PER_SUBLIST
) pieo_inst (
        .clk(clk),
        .rst(rst),
        .pieo_empty_out(pieo_empty_w),
        .start(1'b1),
        .pieo_ready_for_nxt_op_out(pieo_ready_w),
        .enqueue_f_in(pieo_enq_trigger_w),
        .f_in(pieo_enq_element_w),
        .dequeue_in(pieo_deq_trigger_w),
        .curr_time_in(curr_time),
        //.dequeue_f_in(dequeue_f_in),
        //.flow_id_in(flow_id_in),
        //.sublist_id_in(sublist_id_in),
        .deq_valid_out(pieo_deq_valid_w),
        .deq_element_out(pieo_deq_element_w)
);   

/*
    SCHEDULED FIFO BUFFER
*/
/*
wire                                post_deq_ready_w;

wire                                buff_deq_valid_out;
wire [ID_LOG+RANK_LOG+TIME_LOG-1:0] buff_deq_element_out;

sched_fifo_buffer #(
    .NUM_FIFO(NUM_FIFO),
    .ID_LOG(ID_LOG),
    .RANK_LOG(RANK_LOG),
    .TIME_LOG(TIME_LOG)
) sched_fifo_buffer_inst(
    .clk(clk),
    .rst(rst),
    //// pieo interface ////
    //.pieo_ready( (pieo_ready_w) ),
    .pieo_ready( is_pieo_ready_w ),
    .fifos_not_enq_flag(|fifos_not_enqueued_w),
    .pieo_empty(pieo_empty_w),
    .deq_valid_in(pieo_deq_valid_w),
    .deq_element_in(pieo_deq_element_w),
    .pieo_deq_trigger_out(pieo_deq_trigger_w),
    //// post deq interface ////
    //.post_deq_ready(post_deq_ready_w), //
    .deq_valid_out(buff_deq_valid_out),
    .deq_element_out(buff_deq_element_out)
);*/

/*
    POST DEQUEUE FUNCTION
*/

pieo_post_deq_dynamic #(
    .NUM_QUEUES(NUM_FIFO),
    .TB_SCALE(TB_SCALE),
    .PKT_LEN_WIDTH(PKT_LEN_WIDTH),
    .ID_LOG(ID_LOG),
    .RANK_LOG(RANK_LOG),
    .TIME_LOG(TIME_LOG)
) pieo_post_deq_inst (
    .clk(clk),
    .rst(rst),
    .en_in(en_in),
    //// from fifos ////
    .fifo_tvalid(fifo_tvalid),
    .fifos_not_enq_flag(|fifos_not_enqueued_w),
    .pe_tlast(pe_tlast),
    .fifo_packet_length(fifo_packet_length),
    //// from parameter store ////
    .fifo_drr_quantum(fifo_drr_quantum),
    .fifo_enable_shaping(fifo_enable_shaping),
    .fifo_max_rate(fifo_max_rate),
    //// from/to pieo ////
    .pieo_ready(~(~pieo_ready_w)),
    //.pieo_ready(is_pieo_ready_w),
    .pieo_empty(pieo_empty_w),
    .pieo_deq_valid(pieo_deq_valid_w),
    .pieo_deq_element(pieo_deq_element_w),
    .pieo_deq_trigger(pieo_deq_trigger_w),
    //// queue select ////
    .post_deq_end(post_deq_end_w),
    .tb_fifo_eligible(tb_fifo_eligible_w),
    .sel_out(sel_out),
    .en_out(en_out)
);

/*
pieo_post_deq_dynamic #(
    .NUM_QUEUES(NUM_FIFO),
    .TB_SCALE(TB_SCALE),
    .PKT_LEN_WIDTH(PKT_LEN_WIDTH),
    .ID_LOG(ID_LOG),
    .RANK_LOG(RANK_LOG),
    .TIME_LOG(TIME_LOG)
) pieo_post_deq_inst (
    .clk(clk),
    .rst(rst),
    .en_in(en_in),
    // // sched fifo buffer interface
    .post_deq_ready(post_deq_ready_w),
    .deq_valid(buff_deq_valid_out),
    .deq_element(buff_deq_element_out),
    // from fifos
    .fifo_tvalid(fifo_tvalid),
    .pe_tlast(pe_tlast),
    .fifo_packet_length(fifo_packet_length),
    // from parameter store
    .fifo_drr_quantum(fifo_drr_quantum),
    .fifo_enable_shaping(fifo_enable_shaping),
    .fifo_max_rate(fifo_max_rate),
    // queue select
    .post_deq_end(post_deq_end_w),
    .tb_fifo_eligible(tb_fifo_eligible_w),
    .sel_out(sel_out),
    .en_out(en_out)
);*/


endmodule





module determine_if_ready (
    input  wire clk,
    input  wire rst,

    // Inputs
    input  wire trigger1,
    input  wire trigger2,
    input  wire valid1,
    input  wire valid2, 

    // Output
    output wire ready
);

// Internal registers to track waiting state for valid signals
reg waiting_for_valid1, waiting_for_valid1_next, waiting_for_valid2, waiting_for_valid2_next;

always @(posedge clk) begin
    if (rst) begin
        waiting_for_valid1      <= 1'b0;
        waiting_for_valid2      <= 1'b0;
    end else begin
        waiting_for_valid1      <= waiting_for_valid1_next;
        waiting_for_valid2      <= waiting_for_valid2_next;
    end
end

always @(*)begin
    // Default reg update
    waiting_for_valid1_next = waiting_for_valid1;
    waiting_for_valid2_next = waiting_for_valid2;

    // Handle triggers
    if (trigger1) begin
        waiting_for_valid1_next = 1'b1;
    end
    if (trigger2) begin
        waiting_for_valid2_next = 1'b1;
    end

    // Handle valids
    if (valid1 && waiting_for_valid1) begin
        waiting_for_valid1_next = 1'b0;
    end
    if (valid2 && waiting_for_valid2) begin
        waiting_for_valid2_next = 1'b0;
    end

end

assign ready = ~(waiting_for_valid1 | waiting_for_valid2);

endmodule