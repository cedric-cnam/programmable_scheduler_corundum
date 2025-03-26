module pieo_hier_sched #(
    parameter L1_PRE_ENQ_STYLE  = 0,
    parameter L1_POST_DEQ_STYLE = 0,
    parameter L2_PRE_ENQ_STYLE  = 0,
    parameter L2_POST_DEQ_STYLE = 0,
    parameter PORT_COUNT = 3,
    parameter N_FIFO_PER_PORT = 3,
    parameter NUM_FIFO = PORT_COUNT*N_FIFO_PER_PORT,
    parameter PKT_LEN_WIDTH = 16,
    parameter SEL_WIDTH = $clog2(NUM_FIFO)
)
(
    input wire                                  clk, rst,
    input wire [NUM_FIFO-1:0]                   fifo_tvalid,
    input wire [NUM_FIFO*PKT_LEN_WIDTH-1:0]     fifo_packet_length,
    input wire [NUM_FIFO-1:0]                   fifo_tlast,
    output wire [SEL_WIDTH-1:0]                 sel_out,
    output wire                                 en_out
);


// pre-enqueue styles
localparam PRE_ENQ_DEFAULT   = 0;
localparam PRE_ENQ_PRIORITY  = 1;
localparam PRE_ENQ_MIN_RATE  = 2;
localparam PRE_ENQ_SHAPER    = 3;

// post-dequeue styles
localparam POST_DEQ_DEFAULT  = 0;
localparam POST_DEQ_DRR      = 1;



/*
    TRACK ENQUEUED FIFOS AND DETERMINE FIFO TO ENQUEUE NEXT
*/

reg     [NUM_FIFO-1:0]              fifos_enqueued_r, fifos_enqueued_next_r;
wire    [NUM_FIFO-1:0]              fifos_not_enqueued;
reg     [SEL_WIDTH-1:0]             fifo_to_enqueue_r, fifo_to_enqueue_next_r;
wire    [SEL_WIDTH-1:0]             fifo_to_enqueue_next_w;
wire                                found_fifo_to_enq;

always @(posedge clk) begin
    if (rst) begin
        fifos_enqueued_r    <= {NUM_FIFO{1'b0}};
        fifo_to_enqueue_r   <= {SEL_WIDTH{1'b0}};
    end else begin
        fifos_enqueued_r    <= fifos_enqueued_next_r;
        fifo_to_enqueue_r   <= fifo_to_enqueue_next_r;
    end
end

assign fifos_not_enqueued = ~fifos_enqueued_r & fifo_tvalid;

find_next_valid #(
    .INPUT_WIDTH(NUM_FIFO)
) find_next_valid_fifo (
    .all_valid(fifos_not_enqueued),
    .curr_valid(fifo_to_enqueue_r),
    .next_valid(fifo_to_enqueue_next_w),
    .found(found_fifo_to_enq)
);

always @(*)begin
    // By default, refresh registers
    fifos_enqueued_next_r = fifos_enqueued_r;
    fifo_to_enqueue_next_r = fifo_to_enqueue_r;
    // If there is a new fifo to enqueue, update fifo_to_enqueue_next_r
    if (found_fifo_to_enq) begin
        fifo_to_enqueue_next_r = fifo_to_enqueue_next_w;
    end
    // Upon sending a packet, update list of fifos enqueued
    if (l1_post_deq_end) begin
        fifos_enqueued_next_r = fifos_enqueued_r & ~l1_post_deq_end;
    end
    // If enqueue is triggered, update list of fifos enqueued 
    if (l1_pieo_enq_trigger) begin
        fifos_enqueued_next_r[fifo_to_enqueue_next_r] = 1'b1;
    end
end


/*
    TRACK ENQUEUED L1 PIEOS AND DETERMINE PIEO TO ENQUEUE NEXT
*/

localparam PORT_WIDTH = $clog2(PORT_COUNT);

reg     [PORT_COUNT-1:0]            pieos_enqueued_r, pieos_enqueued_next_r;
wire    [PORT_COUNT-1:0]            pieos_not_enqueued; 
reg     [PORT_COUNT-1:0]            pieos_valid;
reg     [PORT_WIDTH-1:0]            pieo_to_enqueue_r, pieo_to_enqueue_next_r;
wire    [PORT_WIDTH-1:0]            pieo_to_enqueue_next_w;
wire                                found_pieo_to_enq;

always @(posedge clk) begin
    if (rst) begin
        pieos_enqueued_r    <= {PORT_COUNT{1'b0}};
        pieo_to_enqueue_r   <= {PORT_WIDTH{1'b0}};
    end else begin
        pieos_enqueued_r    <= pieos_enqueued_next_r;
        pieo_to_enqueue_r   <= fifo_to_enqueue_next_r;
    end
end

// When a fifo is enqueued in a L1 pieo, update pieo valid
integer i;
always @(*)begin
    for (i = 0; i < PORT_COUNT; i = i + 1) begin 
        pieos_valid[i] = |fifos_enqueued_next_r[N_FIFO_PER_PORT+(i*N_FIFO_PER_PORT)-1 -: N_FIFO_PER_PORT];
    end
end

assign pieos_not_enqueued = ~pieos_enqueued_r & pieos_valid;

find_next_valid #(
    .INPUT_WIDTH(PORT_COUNT)
) find_next_valid_pieo (
    .all_valid(pieos_not_enqueued),
    .curr_valid(pieo_to_enqueue_r),
    .next_valid(pieo_to_enqueue_next_w),
    .found(found_pieo_to_enq)
);

always @(*)begin
    // By default, refresh registers
    pieos_enqueued_next_r = pieos_enqueued_r;
    pieo_to_enqueue_next_r = pieo_to_enqueue_r;
    // If there is a new pieo to enqueue, update pieo_to_enqueue_next_r
    if (found_pieo_to_enq) begin
        pieo_to_enqueue_next_r = pieo_to_enqueue_next_w;
    end
    // At the end of the post-dequeue, update list of pieos enqueued
    if (l2_post_deq_end) begin
        pieos_enqueued_next_r = pieos_enqueued_r & ~l2_post_deq_end;
    end
    // If enqueue is triggered, update list of pieos enqueued 
    if (l2_pieo_enq_trigger) begin
        pieos_enqueued_next_r[pieo_to_enqueue_next_r] = 1'b1;
    end
end




/*
    DETECT END OF PACKET
*/

reg  [NUM_FIFO-1:0] fifo_tlast_prev;
wire [NUM_FIFO-1:0] pe_tlast;
    
assign pe_tlast = fifo_tlast & ~fifo_tlast_prev;

always @(posedge clk) begin
    if (rst) begin
        fifo_tlast_prev <= 0;
    end else begin
        fifo_tlast_prev <= fifo_tlast;
    end
end


/*
    WALL CLOCK IF SHAPING
*/

reg [L1_TIME_LOG-1:0]  curr_time = {L1_TIME_LOG{1'b1}};

generate
    if (L1_PRE_ENQ_STYLE == PRE_ENQ_SHAPER) begin : wall_clk
        
        always @(posedge clk) begin
            if (rst) begin
                curr_time <= 0;
            end else begin
                curr_time <= curr_time + 1;
            end
        end
    end
endgenerate



/******************************
            L1 PIEO
/******************************/

// L1 Pieo signals
localparam L1_ID_LOG = $clog2(NUM_FIFO);
localparam L1_LIST_SIZE = (2**L1_ID_LOG);
localparam L1_RANK_LOG = (L1_PRE_ENQ_STYLE == PRE_ENQ_PRIORITY) ? L1_ID_LOG+1 : 2;
localparam L1_TIME_LOG = (L1_PRE_ENQ_STYLE == PRE_ENQ_SHAPER)   ? 32       : 2;
localparam L1_NUM_OF_ELEMENTS_PER_SUBLIST = 1+(2**(L1_ID_LOG/2));  //sqrt(LIST_SIZE)
localparam L1_NUM_OF_SUBLIST = (2*L1_NUM_OF_ELEMENTS_PER_SUBLIST); //2*NUM_OF_ELEMENTS_PER_SUBLIST

wire                                                l1_en_in;
wire                                                l1_pieo_ready;
wire                                                l1_pieo_empty;
wire                                                l1_pieo_enq_trigger;       
wire [L1_ID_LOG+L1_RANK_LOG+L1_TIME_LOG-1:0]        l1_pieo_enq_element;    
wire [L1_ID_LOG-1:0]                                l1_p_start_in, l1_p_end_in;
wire                                                l1_pieo_deq_trigger;    
wire                                                l1_pieo_deq_valid;
wire [L1_ID_LOG+L1_RANK_LOG+L1_TIME_LOG-1:0]        l1_pieo_deq_element;


/*
    PRE ENQUEUE FUNCTION
*/

generate
    if (L1_PRE_ENQ_STYLE == PRE_ENQ_DEFAULT) begin : l1_pre_enq_default
    
        pieo_pre_enq_default #(
            // generic parameters
            .ID_LOG(L1_ID_LOG),
            .RANK_LOG(L1_RANK_LOG),
            .TIME_LOG(L1_TIME_LOG)
        ) l1_pieo_pre_enq (
            // generic ports
            .pieo_ready(~(~l1_pieo_ready)),
            .fifos_not_enq_flag(|fifos_not_enqueued),
            .fifo_id(~(~fifo_to_enqueue_next_r)),
            .pieo_enq_element(l1_pieo_enq_element),
            .pieo_enq_trigger(l1_pieo_enq_trigger)
        );
    
    end else if (L1_PRE_ENQ_STYLE == PRE_ENQ_PRIORITY) begin : l1_pre_enq_priority
    
        pieo_pre_enq_priority #(
            // generic parameters
            .ID_LOG(L1_ID_LOG),
            .RANK_LOG(L1_RANK_LOG),
            .TIME_LOG(L1_TIME_LOG)
        ) l1_pieo_pre_enq (
            // application-specific ports
            .fifo_priority({1'b0, ~(~fifo_to_enqueue_next_r)}),
            // generic ports
            .pieo_ready(~(~l1_pieo_ready)),
            .fifos_not_enq_flag(|fifos_not_enqueued),
            .fifo_id(~(~fifo_to_enqueue_next_r)),
            .pieo_enq_element(l1_pieo_enq_element),
            .pieo_enq_trigger(l1_pieo_enq_trigger)
        );
    
    end else if (L1_PRE_ENQ_STYLE == PRE_ENQ_MIN_RATE) begin : l1_pre_enq_min_rate

        pieo_pre_enq_min_rate #(
            // application-specific parameters
            .NUM_FIFO(NUM_FIFO),
            .PKT_LEN_WIDTH(PKT_LEN_WIDTH),
            // generic parameters
            .ID_LOG(L1_ID_LOG),
            .RANK_LOG(L1_RANK_LOG),
            .TIME_LOG(L1_TIME_LOG)
        ) l1_pieo_pre_enq (
            // application-specific ports 
            .clk(clk),
            .rst(rst),
            .fifo_packet_length(fifo_packet_length),
            .fifo_min_rate(  {NUM_FIFO{16'd3}}),
            .fifo_burst_size({NUM_FIFO{16'd800}}),
            // generic ports
            .pieo_ready(~(~l1_pieo_ready)),
            .fifos_not_enq_flag(|fifos_not_enqueued),
            .fifo_id(~(~fifo_to_enqueue_next_r)),
            .pieo_enq_element(l1_pieo_enq_element),
            .pieo_enq_trigger(l1_pieo_enq_trigger)
        );
        
    end else if (L1_PRE_ENQ_STYLE == PRE_ENQ_SHAPER) begin : l1_pre_enq_shaper
    
        pieo_pre_enq_shaper #(
            // application-specific parameters
            .NUM_FIFO(NUM_FIFO),
            .PKT_LEN_WIDTH(PKT_LEN_WIDTH),
            .TB_SCALE(4),
            // generic parameters
            .ID_LOG(L1_ID_LOG),
            .RANK_LOG(L1_RANK_LOG),
            .TIME_LOG(L1_TIME_LOG)
        ) l1_pieo_pre_enq (
            // application-specific ports 
            .clk(clk),
            .rst(rst),
            .fifo_packet_length(fifo_packet_length),
            .fifo_max_rate( {{5{16'd1}}, {4{16'd4}}} ),
            .fifo_burst_size({NUM_FIFO{16'd800}}),
            .curr_time(curr_time),
            // generic ports
            .pieo_ready(~(~l1_pieo_ready)),
            .fifos_not_enq_flag(|fifos_not_enqueued),
            .fifo_id(~(~fifo_to_enqueue_next_r)),
            .pieo_enq_element(l1_pieo_enq_element),
            .pieo_enq_trigger(l1_pieo_enq_trigger)
        );
        
    end
endgenerate


/*
    PIEO QUEUE
*/

pieo_node #(
    .LIST_SIZE(L1_LIST_SIZE),
    .RANK_LOG(L1_RANK_LOG),
    .TIME_LOG(L1_TIME_LOG),
    .NUM_OF_ELEMENTS_PER_SUBLIST(L1_NUM_OF_ELEMENTS_PER_SUBLIST),      //sqrt(LIST_SIZE)
    .NUM_OF_SUBLIST(L1_NUM_OF_SUBLIST)                                 //2*NUM_OF_ELEMENTS_PER_SUBLIST
) l1_pieo (
        .clk(clk),
        .rst(rst),
        .pieo_empty_out(l1_pieo_empty),
        .start(1'b1),
        .pieo_ready_for_nxt_op_out(l1_pieo_ready),
        .enqueue_f_in(l1_pieo_enq_trigger),
        .f_in(l1_pieo_enq_element),
        .p_start_in(l1_p_start_in),
        .p_end_in(l1_p_end_in),
        .dequeue_in(l1_pieo_deq_trigger),
        .curr_time_in(curr_time),
        //.dequeue_f_in(dequeue_f_in),
        //.flow_id_in(flow_id_in),
        //.sublist_id_in(sublist_id_in),
        .deq_valid_out(l1_pieo_deq_valid),
        .deq_element_out(l1_pieo_deq_element)
);   


/*
    POST DEQUEUE FUNCTION
*/

wire [NUM_FIFO-1:0] l1_post_deq_end;

generate
    if (L1_POST_DEQ_STYLE == POST_DEQ_DEFAULT) begin : l1_post_deq_default
    
        pieo_post_deq_default #(
            // generic parameters
            .NUM_QUEUES(NUM_FIFO),
            .ID_LOG(L1_ID_LOG),
            .RANK_LOG(L1_RANK_LOG),
            .TIME_LOG(L1_TIME_LOG)
        ) l1_pieo_post_deq (
            // generic ports
            .clk(clk),
            .rst(rst),
            .en_in(l1_en_in),
            .pieo_ready(~(~l1_pieo_ready)),
            .pieo_empty(l1_pieo_empty),
            .pieo_deq_valid(l1_pieo_deq_valid),
            .pieo_deq_element(l1_pieo_deq_element),
            .pieo_deq_trigger(l1_pieo_deq_trigger),
            .pe_tlast(pe_tlast),
            .fifos_not_enq_flag(|fifos_not_enqueued),
            .sel_out(sel_out),
            .en_out(en_out)
        );
        
    assign l1_post_deq_end = pe_tlast;

    end else if (L1_POST_DEQ_STYLE == POST_DEQ_DRR) begin: l1_post_deq_drr
    
        pieo_post_deq_drr #(
            // application-specific parameters
            .NUM_FIFOS(NUM_FIFO),
            // generic parameters
            .NUM_QUEUES(NUM_FIFO),
            .ID_LOG(L1_ID_LOG),
            .RANK_LOG(L1_RANK_LOG),
            .TIME_LOG(L1_TIME_LOG)
        ) l1_pieo_post_deq (
            // application-specific ports
            .fifo_tvalid(fifo_tvalid),
            .fifo_packet_length(fifo_packet_length),
            // generic ports
            .clk(clk),
            .rst(rst),
            .en_in(l1_en_in),
            .pieo_ready(~(~l1_pieo_ready)),
            .pieo_empty(l1_pieo_empty),
            .pieo_deq_valid(l1_pieo_deq_valid),
            .pieo_deq_element(l1_pieo_deq_element),
            .pieo_deq_trigger(l1_pieo_deq_trigger),
            .fifo_tlast(fifo_tlast),
            .fifos_not_enq_flag(|fifos_not_enqueued),
            .post_deq_end(l1_post_deq_end),
            .sel_out(sel_out),
            .en_out(en_out)
        );
    
    end
endgenerate


/******************************
            L2 PIEO
/******************************/

// L2 Pieo signals
localparam L2_ID_LOG = $clog2(PORT_COUNT);
localparam L2_LIST_SIZE = (2**L2_ID_LOG);
localparam L2_RANK_LOG = (L2_PRE_ENQ_STYLE == PRE_ENQ_PRIORITY) ? L2_ID_LOG+1 : 2;
localparam L2_TIME_LOG = (L2_PRE_ENQ_STYLE == PRE_ENQ_SHAPER)   ? 32       : 2;
localparam L2_NUM_OF_ELEMENTS_PER_SUBLIST = 1+(2**(L2_ID_LOG/2));  //sqrt(LIST_SIZE)
localparam L2_NUM_OF_SUBLIST = (2*L2_NUM_OF_ELEMENTS_PER_SUBLIST); //2*NUM_OF_ELEMENTS_PER_SUBLIST

wire                                                l2_pieo_ready;
wire                                                l2_pieo_empty;
wire                                                l2_pieo_enq_trigger;       
wire [L2_ID_LOG+L2_RANK_LOG+L2_TIME_LOG-1:0]        l2_pieo_enq_element;  
wire                                                l2_pieo_deq_trigger;    
wire                                                l2_pieo_deq_valid;
wire [L2_ID_LOG+L2_RANK_LOG+L2_TIME_LOG-1:0]        l2_pieo_deq_element;


/*
    PRE ENQUEUE FUNCTION
*/

generate
    if (L2_PRE_ENQ_STYLE == PRE_ENQ_DEFAULT) begin : l2_pre_enq_default
    
        pieo_pre_enq_default #(
            // generic parameters
            .ID_LOG(L2_ID_LOG),
            .RANK_LOG(L2_RANK_LOG),
            .TIME_LOG(L2_TIME_LOG)
        ) l2_pieo_pre_enq (
            // generic ports
            .pieo_ready(~(~l2_pieo_ready)),
            .fifos_not_enq_flag(|pieos_not_enqueued),
            .fifo_id(~(~pieo_to_enqueue_next_r)),
            .pieo_enq_element(l2_pieo_enq_element),
            .pieo_enq_trigger(l2_pieo_enq_trigger)
        );
    
    end else if (L2_PRE_ENQ_STYLE == PRE_ENQ_PRIORITY) begin : l2_pre_enq_priority
    
        pieo_pre_enq_priority #(
            // generic parameters
            .ID_LOG(L2_ID_LOG),
            .RANK_LOG(L2_RANK_LOG),
            .TIME_LOG(L2_TIME_LOG)
        ) l2_pieo_pre_enq (
            // application-specific ports
            .fifo_priority({1'b0, ~(~pieo_to_enqueue_next_r)}),
            // generic ports
            .pieo_ready(~(~l2_pieo_ready)),
            .fifos_not_enq_flag(|pieos_not_enqueued),
            .fifo_id(~(~pieo_to_enqueue_next_r)),
            .pieo_enq_element(l2_pieo_enq_element),
            .pieo_enq_trigger(l2_pieo_enq_trigger)
        );
    
    end
endgenerate


/*
    PIEO QUEUE
*/

pieo #(
    .LIST_SIZE(L2_LIST_SIZE),
    .RANK_LOG(L2_RANK_LOG),
    .TIME_LOG(L2_TIME_LOG),
    .NUM_OF_ELEMENTS_PER_SUBLIST(L2_NUM_OF_ELEMENTS_PER_SUBLIST),      //sqrt(LIST_SIZE)
    .NUM_OF_SUBLIST(L2_NUM_OF_SUBLIST)                                 //2*NUM_OF_ELEMENTS_PER_SUBLIST
) l2_pieo (
        .clk(clk),
        .rst(rst),
        .pieo_empty_out(l2_pieo_empty),
        .start(1'b1),
        .pieo_ready_for_nxt_op_out(l2_pieo_ready),
        .enqueue_f_in(l2_pieo_enq_trigger),
        .f_in(l2_pieo_enq_element),
        .dequeue_in(l2_pieo_deq_trigger),
        .curr_time_in(curr_time),
        //.dequeue_f_in(dequeue_f_in),
        //.flow_id_in(flow_id_in),
        //.sublist_id_in(sublist_id_in),
        .deq_valid_out(l2_pieo_deq_valid),
        .deq_element_out(l2_pieo_deq_element)
);   


/*
    POST DEQUEUE FUNCTION
*/

wire [PORT_COUNT-1:0]     l2_post_deq_end;
wire [L2_ID_LOG-1:0]      sel_l1_pieo;


// Convert sel_l1_pieo to p_start and p_end
localparam p_start_0 = 0;
localparam p_start_1 = N_FIFO_PER_PORT;
localparam p_start_2 = 2*N_FIFO_PER_PORT;

localparam p_end_0 = N_FIFO_PER_PORT-1;
localparam p_end_1 = 2*N_FIFO_PER_PORT-1;
localparam p_end_2 = 3*N_FIFO_PER_PORT-1;

assign l1_p_start_in = (sel_l1_pieo == 0) ? p_start_0 : (sel_l1_pieo == 1) ? p_start_1 : (sel_l1_pieo == 2) ? p_start_2 : 0;
assign l1_p_end_in   = (sel_l1_pieo == 0) ? p_end_0   : (sel_l1_pieo == 1) ? p_end_1   : (sel_l1_pieo == 2) ? p_end_2   : {L1_ID_LOG{1'b1}};


// aggregate pe_tlast into l1_pieo_tlast and l1_post_deq_end into l1_pieo_deq_end
reg [PORT_COUNT-1:0] l1_pieo_tlast, l1_pieo_deq_end;

integer j;
always @(*)begin
    for (j = 0; j < PORT_COUNT; j = j + 1) begin 
        l1_pieo_tlast[j]   = |pe_tlast[N_FIFO_PER_PORT+(j*N_FIFO_PER_PORT)-1 -: N_FIFO_PER_PORT];
        l1_pieo_deq_end[j] = |l1_post_deq_end[N_FIFO_PER_PORT+(j*N_FIFO_PER_PORT)-1 -: N_FIFO_PER_PORT];
    end
end


generate
    if (L2_POST_DEQ_STYLE == POST_DEQ_DEFAULT) begin : l2_post_deq_default
    
        pieo_post_deq_default #(
            // generic parameters
            .NUM_QUEUES(PORT_COUNT),
            .ID_LOG(L2_ID_LOG),
            .RANK_LOG(L2_RANK_LOG),
            .TIME_LOG(L2_TIME_LOG)
        ) l2_pieo_post_deq (
            // generic ports
            .clk(clk),
            .rst(rst),
            .en_in(1'b1),
            .pieo_ready(~(~l2_pieo_ready)),
            .pieo_empty(l2_pieo_empty),
            .pieo_deq_valid(l2_pieo_deq_valid),
            .pieo_deq_element(l2_pieo_deq_element),
            .pieo_deq_trigger(l2_pieo_deq_trigger),
            .pe_tlast(l1_pieo_deq_end),
            .fifos_not_enq_flag(|pieos_not_enqueued),
            .sel_out(sel_l1_pieo),
            .en_out(l1_en_in)
        );
        
        assign l2_post_deq_end = l1_pieo_deq_end;

    end else if (L2_POST_DEQ_STYLE == POST_DEQ_DRR) begin: l2_post_deq_drr
    
        pieo_post_deq_drr #(
            // application-specific parameters
            .NUM_FIFOS(NUM_FIFO),
            // generic parameters
            .NUM_QUEUES(PORT_COUNT),
            .ID_LOG(L2_ID_LOG),
            .RANK_LOG(L2_RANK_LOG),
            .TIME_LOG(L2_TIME_LOG)
        ) l2_pieo_post_deq (
            // application-specific ports
            .fifo_tvalid(fifo_tvalid),
            .head_pkt_length(fifo_packet_length[sel_out*PKT_LEN_WIDTH +: PKT_LEN_WIDTH]),
            // generic ports
            .clk(clk),
            .rst(rst),
            .en_in(1'b1),
            .pieo_ready(~(~l2_pieo_ready)),
            .pieo_empty(l2_pieo_empty),
            .pieo_deq_valid(l2_pieo_deq_valid),
            .pieo_deq_element(l2_pieo_deq_element),
            .pieo_deq_trigger(l2_pieo_deq_trigger),
            .pe_tlast(l1_pieo_tlast),
            .fifos_not_enq_flag(|pieos_not_enqueued),
            .post_deq_end(l2_post_deq_end),
            .sel_out(sel_l1_pieo),
            .en_out(l1_en_in)
        );
    
    end
endgenerate

endmodule
