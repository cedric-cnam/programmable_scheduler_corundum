// synopsys translate_off
`timescale 1 ns / 1 ps
// synopsys translate_on

/*
typedef struct packed
{
    logic [ID_LOG-1:0] id;
    logic [RANK_LOG-1:0] rank; //init with infinity
    logic [TIME_LOG-1:0] send_time;
} SublistElement;

typedef struct packed
{
    logic [$clog2(NUM_OF_SUBLIST)-1:0] id;
    logic [RANK_LOG-1:0] smallest_rank; //init with infinity
    logic [TIME_LOG-1:0] smallest_send_time; //init with infinity
    logic full;
    logic [$clog2(NUM_OF_SUBLIST/2)-1:0] num;
} PointerElement;
*/

/* NULL element is all 1s, i.e., e.id = '1, e.rank = '1, and e.send_time = '1
 * It is assumed that '1 for rank and send_time values equals Infinity
*/

module pieo_node
#(

parameter LIST_SIZE = (2**6),
parameter ID_LOG = $clog2(LIST_SIZE),
parameter RANK_LOG = 16,
parameter TIME_LOG = 16,

parameter NUM_OF_ELEMENTS_PER_SUBLIST = (2**3), //sqrt(LIST_SIZE)
parameter NUM_OF_SUBLIST = (2**4) //2*NUM_OF_ELEMENTS_PER_SUBLIST

)
(
    input clk,
    input rst,

    /* signal that PIEO has reset all the internal datastructures */
    output reg pieo_reset_done_out,
    
    /* signal that PIEO is empty*/
    output wire pieo_empty_out,

    /* signal to start the PIEO scheduler
     * this signal should be set once PIEO has reset all it's datastructures
    */
    input start,

    /* signal that PIEO is ready for the next primitive operation
     * wait for this signal to be set before issuing the next primitive operation
    */
    output reg pieo_ready_for_nxt_op_out,

    /* interface for enqueue(f) operation */
    input enqueue_f_in,
    input [ID_LOG+RANK_LOG+TIME_LOG-1:0] f_in,
    input [ID_LOG-1:0] p_start_in, p_end_in, 
    output reg enq_valid_out,
    output reg [$clog2(NUM_OF_SUBLIST):0] f_enqueued_in_sublist_out,

    /* input interface for dequeue() operation */
    input dequeue_in,
    input [TIME_LOG-1:0] curr_time_in,

    /* input interface for dequeue(f) operation */
    input dequeue_f_in,
    input [ID_LOG-1:0] flow_id_in,
    input [$clog2(NUM_OF_SUBLIST)-1:0] sublist_id_in,

    /* output interface for dequeue() and dequeue(f) operations */
    output reg deq_valid_out,
    output [ID_LOG+RANK_LOG+TIME_LOG-1:0] deq_element_out,

    /* element moved during a primitive operation */
    output reg [ID_LOG:0] flow_id_moved_out,
    output reg [$clog2(NUM_OF_SUBLIST):0] flow_id_moved_to_sublist_out
);

    // Split elements of f_in
    wire [ID_LOG-1:0]    f_in_id;
    wire [RANK_LOG-1:0]  f_in_rank;
    wire [TIME_LOG-1:0]  f_in_send_time;
    
    assign f_in_id           = f_in[ID_LOG-1:0];
    assign f_in_rank         = f_in[RANK_LOG+ID_LOG-1:ID_LOG];
    assign f_in_send_time    = f_in[TIME_LOG+RANK_LOG+ID_LOG-1:RANK_LOG+ID_LOG];

    // Concatenate elements of deq_element_out
    reg [ID_LOG-1:0]    deq_element_out_id;
    reg [RANK_LOG-1:0]  deq_element_out_rank;
    reg [TIME_LOG-1:0]  deq_element_out_send_time;
    
    assign deq_element_out = {deq_element_out_send_time, deq_element_out_rank, deq_element_out_id};


    //latching the inputs    
    reg [ID_LOG-1:0]    f_in_reg_id;
    reg [RANK_LOG-1:0]  f_in_reg_rank;
    reg [TIME_LOG-1:0]  f_in_reg_send_time;
    reg [ID_LOG-1:0]    p_start_in_reg, p_end_in_reg;
    reg dequeue_in_reg;
    reg [TIME_LOG-1:0] curr_time_in_reg;
    reg dequeue_f_in_reg;
    reg [ID_LOG-1:0] flow_id_in_reg;

    // neigh_types
    localparam LEFT = 0;
    localparam RIGHT = 1;
    localparam FREE = 2;
    localparam NONE = 3;

    //ordered list in SRAM
    reg enable_A [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    reg write_A [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    reg [$clog2(NUM_OF_SUBLIST)-1:0] address_A [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];    
    reg [ID_LOG-1:0]     wr_data_A_id        [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    reg [RANK_LOG-1:0]   wr_data_A_rank      [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    reg [TIME_LOG-1:0]   wr_data_A_send_time [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    wire [ID_LOG-1:0]    rd_data_A_id        [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    wire [RANK_LOG-1:0]  rd_data_A_rank      [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    wire [TIME_LOG-1:0]  rd_data_A_send_time [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];

    reg enable_B [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    reg write_B [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    reg [$clog2(NUM_OF_SUBLIST)-1:0] address_B [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    reg [ID_LOG-1:0]     wr_data_B_id        [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    reg [RANK_LOG-1:0]   wr_data_B_rank      [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    reg [TIME_LOG-1:0]   wr_data_B_send_time [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    wire [ID_LOG-1:0]    rd_data_B_id        [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    wire [RANK_LOG-1:0]  rd_data_B_rank      [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    wire [TIME_LOG-1:0]  rd_data_B_send_time [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];

    generate
    genvar i;
    for (i=0; i<NUM_OF_ELEMENTS_PER_SUBLIST; i=i+1) begin : rank_sublist
        true_dp_bram_readfirst # (
            .RAM_WIDTH(ID_LOG+RANK_LOG+TIME_LOG),
            .RAM_ADDR_BITS($clog2(NUM_OF_SUBLIST))
        ) rank_sublist (
            .clk(clk),
            .addr1(address_A[i]),
            .addr2(address_B[i]),
            .din1({wr_data_A_send_time[i], wr_data_A_rank[i], wr_data_A_id[i]}),
            .din2({wr_data_B_send_time[i], wr_data_B_rank[i], wr_data_B_id[i]}),
            .en1(enable_A[i]),
            .en2(enable_B[i]),
            .we1(write_A[i]),
            .we2(write_B[i]),
            .dout1({rd_data_A_send_time[i], rd_data_A_rank[i], rd_data_A_id[i]}),
            .dout2({rd_data_B_send_time[i], rd_data_B_rank[i], rd_data_B_id[i]})
        );
    end
    endgenerate

    reg  enable_AA [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    reg  write_AA [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    reg  [$clog2(NUM_OF_SUBLIST)-1:0] address_AA [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    reg  [TIME_LOG-1:0] wr_data_AA [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    wire [TIME_LOG-1:0] rd_data_AA [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];

    reg  enable_BB [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    reg  write_BB [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    reg  [$clog2(NUM_OF_SUBLIST)-1:0] address_BB [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    reg  [TIME_LOG-1:0] wr_data_BB [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    wire [TIME_LOG-1:0] rd_data_BB [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];

/*
            .clk(clk),
            .addr1(address_A[i]),
            .addr2(address_B[i]),
            .din1(wr_data_A[i]),
            .din2(wr_data_B[i]),
            .en1(enable_A[i]),
            .en2(enable_B[i]),
            .we1(write_A[i]),
            .we2(write_B[i]),
            .dout1(rd_data_A[i]),
            .dout2(rd_data_B[i])
*/
    generate
    genvar j;
    for (j=0; j<NUM_OF_ELEMENTS_PER_SUBLIST; j=j+1) begin : pred_fifo
        true_dp_bram_readfirst # (
            .RAM_WIDTH(TIME_LOG),
            .RAM_ADDR_BITS($clog2(NUM_OF_SUBLIST))
        ) pred_sublist (
            .clk(clk),
            .addr1(address_AA[j]),
            .addr2(address_BB[j]),
            .din1(wr_data_AA[j]),
            .din2(wr_data_BB[j]),
            .en1(enable_AA[j]),
            .en2(enable_BB[j]),
            .we1(write_AA[j]),
            .we2(write_BB[j]),
            .dout1(rd_data_AA[j]),
            .dout2(rd_data_BB[j])
        );
    end
    endgenerate


    reg [ID_LOG-1:0]    rd_data_A_id_reg        [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    reg [RANK_LOG-1:0]  rd_data_A_rank_reg      [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    reg [TIME_LOG-1:0]  rd_data_A_send_time_reg [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    
    reg [ID_LOG-1:0]    rd_data_B_id_reg        [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    reg [RANK_LOG-1:0]  rd_data_B_rank_reg      [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    reg [TIME_LOG-1:0]  rd_data_B_send_time_reg [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    
    reg [TIME_LOG-1:0] rd_data_AA_reg [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];
    reg [TIME_LOG-1:0] rd_data_BB_reg [NUM_OF_ELEMENTS_PER_SUBLIST-1:0];

    integer ii;
    always @(posedge clk) begin
        if (~rst) begin
            for (ii=0; ii<NUM_OF_ELEMENTS_PER_SUBLIST; ii=ii+1) begin
                rd_data_A_id_reg[ii]         <= rd_data_A_id[ii];
                rd_data_A_rank_reg[ii]       <= rd_data_A_rank[ii];
                rd_data_A_send_time_reg[ii]  <= rd_data_A_send_time[ii];
                rd_data_B_id_reg[ii]         <= rd_data_B_id[ii];
                rd_data_B_rank_reg[ii]       <= rd_data_B_rank[ii];
                rd_data_B_send_time_reg[ii]  <= rd_data_B_send_time[ii];
                rd_data_AA_reg[ii]          <= rd_data_AA[ii];
                rd_data_BB_reg[ii]          <= rd_data_BB[ii];
            end
        end
    end

    //pointer array in flip-flops
    reg [$clog2(NUM_OF_SUBLIST)-1:0]    pointer_array_id                    [NUM_OF_SUBLIST-1:0];
    reg [RANK_LOG-1:0]                  pointer_array_smallest_rank         [NUM_OF_SUBLIST-1:0];
    reg [TIME_LOG-1:0]                  pointer_array_smallest_send_time    [NUM_OF_SUBLIST-1:0];
    reg                                 pointer_array_full                  [NUM_OF_SUBLIST-1:0];
    reg [$clog2(NUM_OF_SUBLIST/2)-1:0]  pointer_array_num                   [NUM_OF_SUBLIST-1:0];
    
    reg [$clog2(NUM_OF_SUBLIST)-1:0] free_list_head_reg;

    //pointer array multiplexer
    reg [$clog2(NUM_OF_SUBLIST)-1:0] s_idx_reg;
    
    wire [$clog2(NUM_OF_SUBLIST)-1:0]    s_id;
    wire [RANK_LOG-1:0]                  s_smallest_rank;
    wire [TIME_LOG-1:0]                  s_smallest_send_time;
    wire                                 s_full;
    wire [$clog2(NUM_OF_SUBLIST/2)-1:0]  s_num;
    
    wire [$clog2(NUM_OF_SUBLIST)-1:0]    s_neigh_enq_id;
    wire [RANK_LOG-1:0]                  s_neigh_enq_smallest_rank;
    wire [TIME_LOG-1:0]                  s_neigh_enq_smallest_send_time;
    wire                                 s_neigh_enq_full;
    wire [$clog2(NUM_OF_SUBLIST/2)-1:0]  s_neigh_enq_num;
    
    wire [1:0] s_neigh_enq_type;
    
    wire [$clog2(NUM_OF_SUBLIST)-1:0]    s_neigh_deq_id;
    wire [RANK_LOG-1:0]                  s_neigh_deq_smallest_rank;
    wire [TIME_LOG-1:0]                  s_neigh_deq_smallest_send_time;
    wire                                 s_neigh_deq_full;
    wire [$clog2(NUM_OF_SUBLIST/2)-1:0]  s_neigh_deq_num;
    
    wire [1:0] s_neigh_deq_type;
    
    wire [$clog2(NUM_OF_SUBLIST)-1:0]    s_free_id;
    wire [RANK_LOG-1:0]                  s_free_smallest_rank;
    wire [TIME_LOG-1:0]                  s_free_smallest_send_time;
    wire                                 s_free_full;
    wire [$clog2(NUM_OF_SUBLIST/2)-1:0]  s_free_num;
    
    
    wire [$clog2(NUM_OF_ELEMENTS_PER_SUBLIST)-1:0] element_moving_idx;
    
    reg [$clog2(NUM_OF_SUBLIST)-1:0]    s_reg_id;
    reg [RANK_LOG-1:0]                  s_reg_smallest_rank;
    reg [TIME_LOG-1:0]                  s_reg_smallest_send_time;
    reg                                 s_reg_full;
    reg [$clog2(NUM_OF_SUBLIST/2)-1:0]  s_reg_num;
    
    reg [$clog2(NUM_OF_SUBLIST)-1:0]    s_neigh_reg_id;
    reg [RANK_LOG-1:0]                  s_neigh_reg_smallest_rank;
    reg [TIME_LOG-1:0]                  s_neigh_reg_smallest_send_time;
    reg                                 s_neigh_reg_full;
    reg [$clog2(NUM_OF_SUBLIST/2)-1:0]  s_neigh_reg_num;
    
    reg [1:0] s_neigh_type_reg;
    
    reg [$clog2(NUM_OF_SUBLIST)-1:0]    s_free_reg_id;
    reg [RANK_LOG-1:0]                  s_free_reg_smallest_rank;
    reg [TIME_LOG-1:0]                  s_free_reg_smallest_send_time;
    reg                                 s_free_reg_full;
    reg [$clog2(NUM_OF_SUBLIST/2)-1:0]  s_free_reg_num;

    assign s_id = pointer_array_id[s_idx_reg];
    assign s_smallest_rank = pointer_array_smallest_rank[s_idx_reg];
    assign s_smallest_send_time = pointer_array_smallest_send_time[s_idx_reg];
    assign s_full = pointer_array_full[s_idx_reg];
    assign s_num = pointer_array_num[s_idx_reg];
    
    assign s_neigh_enq_id = (s_idx_reg+1 < NUM_OF_SUBLIST
                            & pointer_array_full[s_idx_reg+1])
                        ? s_free_id : pointer_array_id[s_idx_reg+1];
    assign s_neigh_enq_smallest_rank  = (s_idx_reg+1 < NUM_OF_SUBLIST
                            & pointer_array_full[s_idx_reg+1])
                        ? s_free_smallest_rank  : pointer_array_smallest_rank [s_idx_reg+1];
    assign s_neigh_enq_smallest_send_time  = (s_idx_reg+1 < NUM_OF_SUBLIST
                            & pointer_array_full[s_idx_reg+1])
                        ? s_free_smallest_send_time  : pointer_array_smallest_send_time [s_idx_reg+1];
    assign s_neigh_enq_full = (s_idx_reg+1 < NUM_OF_SUBLIST
                            & pointer_array_full[s_idx_reg+1])
                        ? s_free_full : pointer_array_full[s_idx_reg+1];
    assign s_neigh_enq_num = (s_idx_reg+1 < NUM_OF_SUBLIST
                            & pointer_array_full[s_idx_reg+1])
                        ? s_free_num : pointer_array_num[s_idx_reg+1];

                        
    assign s_neigh_enq_type = (s_idx_reg+1 < NUM_OF_SUBLIST
                            & pointer_array_full[s_idx_reg+1])
                        ? FREE : RIGHT;
                        
    assign s_neigh_deq_id = (pointer_array_full[s_idx_reg]
                            & s_idx_reg+1 < NUM_OF_SUBLIST
                            & ~pointer_array_full[s_idx_reg+1]
                            & s_idx_reg+1 != free_list_head_reg)
                        ? pointer_array_id[s_idx_reg+1]
                        : (pointer_array_full[s_idx_reg]
                            & s_idx_reg > 0
                            & ~pointer_array_full[s_idx_reg-1])
                        ? pointer_array_id[s_idx_reg-1] : 0;
    assign s_neigh_deq_smallest_rank = (pointer_array_full[s_idx_reg]
                            & s_idx_reg+1 < NUM_OF_SUBLIST
                            & ~pointer_array_full[s_idx_reg+1]
                            & s_idx_reg+1 != free_list_head_reg)
                        ? pointer_array_smallest_rank[s_idx_reg+1]
                        : (pointer_array_full[s_idx_reg]
                            & s_idx_reg > 0
                            & ~pointer_array_full[s_idx_reg-1])
                        ? pointer_array_smallest_rank[s_idx_reg-1] : 0;
    assign s_neigh_deq_smallest_send_time = (pointer_array_full[s_idx_reg]
                            & s_idx_reg+1 < NUM_OF_SUBLIST
                            & ~pointer_array_full[s_idx_reg+1]
                            & s_idx_reg+1 != free_list_head_reg)
                        ? pointer_array_smallest_send_time[s_idx_reg+1]
                        : (pointer_array_full[s_idx_reg]
                            & s_idx_reg > 0
                            & ~pointer_array_full[s_idx_reg-1])
                        ? pointer_array_smallest_send_time[s_idx_reg-1] : 0;
    assign s_neigh_deq_full = (pointer_array_full[s_idx_reg]
                            & s_idx_reg+1 < NUM_OF_SUBLIST
                            & ~pointer_array_full[s_idx_reg+1]
                            & s_idx_reg+1 != free_list_head_reg)
                        ? pointer_array_full[s_idx_reg+1]
                        : (pointer_array_full[s_idx_reg]
                            & s_idx_reg > 0
                            & ~pointer_array_full[s_idx_reg-1])
                        ? pointer_array_full[s_idx_reg-1] : 0;
    assign s_neigh_deq_num = (pointer_array_full[s_idx_reg]
                            & s_idx_reg+1 < NUM_OF_SUBLIST
                            & ~pointer_array_full[s_idx_reg+1]
                            & s_idx_reg+1 != free_list_head_reg)
                        ? pointer_array_num[s_idx_reg+1]
                        : (pointer_array_full[s_idx_reg]
                            & s_idx_reg > 0
                            & ~pointer_array_full[s_idx_reg-1])
                        ? pointer_array_num[s_idx_reg-1] : 0;
                        
                        
    assign s_neigh_deq_type = (pointer_array_full[s_idx_reg]
                            & s_idx_reg+1 < NUM_OF_SUBLIST
                            & ~pointer_array_full[s_idx_reg+1]
                            & s_idx_reg+1 != free_list_head_reg)
                        ? RIGHT
                        : (pointer_array_full[s_idx_reg]
                            & s_idx_reg > 0
                            & ~pointer_array_full[s_idx_reg-1])
                        ? LEFT : NONE;
                        
    assign s_free_id = pointer_array_id[free_list_head_reg];
    assign s_free_smallest_rank = pointer_array_smallest_rank[free_list_head_reg];
    assign s_free_smallest_send_time = pointer_array_smallest_send_time[free_list_head_reg];
    assign s_free_full = pointer_array_full[free_list_head_reg];
    assign s_free_num = pointer_array_num[free_list_head_reg];
    
    
    assign element_moving_idx = (pointer_array_full[s_idx_reg]
                            & s_idx_reg+1 < NUM_OF_SUBLIST
                            & ~pointer_array_full[s_idx_reg+1]
                            & s_idx_reg+1 != free_list_head_reg)
                        ? 0
                        : (pointer_array_full[s_idx_reg]
                            & s_idx_reg > 0
                            & ~pointer_array_full[s_idx_reg-1])
                        ? pointer_array_num[s_idx_reg-1]-1 : {$clog2(NUM_OF_ELEMENTS_PER_SUBLIST){1'b1}};

    //priority encoder for pointer array
    reg  [NUM_OF_SUBLIST-1:0] bit_vector;
    wire [$clog2(NUM_OF_SUBLIST)-1:0] encode;
    reg  [$clog2(NUM_OF_SUBLIST)-1:0] encode_reg;
    wire valid;
    reg  valid_reg;

    priority_encoder_tree #(
        .WIDTH(NUM_OF_SUBLIST),
        .EN_REVERSE(1)
    ) pri_encoder(
        .input_unencoded(bit_vector),
        .output_encoded(encode),
        .output_valid(valid)
    );

    //priority encoder for rank sublist
    reg  [NUM_OF_SUBLIST/2-1:0] bit_vector_A;
    wire [$clog2(NUM_OF_SUBLIST/2)-1:0] encode_A;
    reg  [$clog2(NUM_OF_SUBLIST/2)-1:0] encode_A_reg;
    wire valid_A;
    reg  valid_A_reg;


    priority_encoder_tree #(
        .WIDTH(NUM_OF_SUBLIST/2),
        .EN_REVERSE(1)
    ) pri_encoder_A(
        .input_unencoded(bit_vector_A),
        .output_encoded(encode_A),
        .output_valid(valid_A)
    );

    //priority encoder for pred sublist
    reg  [NUM_OF_SUBLIST/2-1:0] bit_vector_AA;
    wire [$clog2(NUM_OF_SUBLIST/2)-1:0] encode_AA;
    reg  [$clog2(NUM_OF_SUBLIST/2)-1:0] encode_AA_reg;
    wire valid_AA;
    reg  valid_AA_reg;


    priority_encoder_tree #(
        .WIDTH(NUM_OF_SUBLIST/2),
        .EN_REVERSE(1)
    ) pri_encoder_AA(
        .input_unencoded(bit_vector_AA),
        .output_encoded(encode_AA),
        .output_valid(valid_AA)
    );

    //priority encoder for pred sublist
    reg  [NUM_OF_SUBLIST/2-1:0] bit_vector_BB;
    wire [$clog2(NUM_OF_SUBLIST/2)-1:0] encode_BB;
    reg  [$clog2(NUM_OF_SUBLIST/2)-1:0] encode_BB_reg;
    wire valid_BB;
    reg  valid_BB_reg;


    priority_encoder_tree #(
        .WIDTH(NUM_OF_SUBLIST/2),
        .EN_REVERSE(1)
    ) pri_encoder_BB(
        .input_unencoded(bit_vector_BB),
        .output_encoded(encode_BB),
        .output_valid(valid_BB)
    );


    // Check if PIEO is empty
    wire [NUM_OF_SUBLIST-1:0] is_sublist_empty;

    generate
    genvar x;
    for (x=0; x<NUM_OF_SUBLIST; x=x+1) begin
        assign is_sublist_empty[x] = (pointer_array_num[x] == 0) ? 1 : 0;
    end
    endgenerate
    
    assign pieo_empty_out = & is_sublist_empty;


/*
    typedef enum {
`ifdef SIMULATION
        PRINT,
        CONT_PRINTING,
`endif
        RESET,
        RESET_DONE,
        IDLE,
        ENQ_FETCH_SUBLIST_FROM_MEM,
        POS_TO_ENQUEUE,
        ENQ_WRITE_BACK_TO_MEM,
        DEQ_FETCH_SUBLIST_FROM_MEM,
        POS_TO_DEQUEUE,
        DEQ_WRITE_BACK_TO_MEM
    } pieo_ops;
*/

    localparam RESET = 0;
    localparam RESET_DONE = 1;
    localparam IDLE = 2;
    localparam ENQ_FETCH_SUBLIST_FROM_MEM = 3;
    localparam POS_TO_ENQUEUE = 4;
    localparam ENQ_WRITE_BACK_TO_MEM = 5;
    localparam DEQ_FETCH_SUBLIST_FROM_MEM = 6;
    localparam POS_TO_DEQUEUE = 7;
    localparam DEQ_WRITE_BACK_TO_MEM = 8;

    reg [3:0] curr_state, nxt_state;

    reg [31:0] curr_address;

    reg [ID_LOG-1:0]    element_moving_reg_id;
    reg [RANK_LOG-1:0]  element_moving_reg_rank;
    reg [TIME_LOG-1:0]  element_moving_reg_send_time;
    
    reg [$clog2(NUM_OF_ELEMENTS_PER_SUBLIST)-1:0] element_moving_idx_reg;
    reg [TIME_LOG-1:0] pred_moving_reg;

    reg [1:0] enqueue_case_reg;

    reg [$clog2(NUM_OF_SUBLIST)-1:0] idx_enq_reg;
    reg [$clog2(NUM_OF_SUBLIST)-1:0] idx_enq;

    reg [ID_LOG-1:0]    element_dequeued_reg_id;
    reg [RANK_LOG-1:0]  element_dequeued_reg_rank;
    reg [TIME_LOG-1:0]  element_dequeued_reg_send_time;
    always @(posedge clk) begin
        if (~rst) element_dequeued_reg_id <= rd_data_A_id[encode_A];
        if (~rst) element_dequeued_reg_rank <= rd_data_A_rank[encode_A];
        if (~rst) element_dequeued_reg_send_time <= rd_data_A_send_time[encode_A];        
    end

    wire [ID_LOG-1:0]    element_moving_id;
    wire [RANK_LOG-1:0]  element_moving_rank;
    wire [TIME_LOG-1:0]  element_moving_send_time;
    assign element_moving_id = rd_data_B_id[element_moving_idx_reg];
    assign element_moving_rank = rd_data_B_rank[element_moving_idx_reg];
    assign element_moving_send_time = rd_data_B_send_time[element_moving_idx_reg];
    

    reg [TIME_LOG-1:0] pred_val_deq;

    // deq debug
    reg [NUM_OF_ELEMENTS_PER_SUBLIST-1:0]   pred_eval, logic_pieo_select;

    always @(*) begin
        for (ii=0; ii<NUM_OF_ELEMENTS_PER_SUBLIST; ii=ii+1) begin
            enable_A[ii] = 0;
            write_A[ii] = 0;
            address_A[ii] = {$clog2(NUM_OF_SUBLIST){1'b0}};
            wr_data_A_id[ii] = {ID_LOG{1'b0}};
            wr_data_A_rank[ii] = {RANK_LOG{1'b0}};
            wr_data_A_send_time[ii] = {TIME_LOG{1'b0}};            
            enable_B[ii] = 0;
            write_B[ii] = 0;
            address_B[ii] = {$clog2(NUM_OF_SUBLIST){1'b0}};
            wr_data_B_id[ii] = {ID_LOG{1'b0}};
            wr_data_B_rank[ii] = {RANK_LOG{1'b0}};
            wr_data_B_send_time[ii] = {TIME_LOG{1'b0}}; 
            enable_AA[ii] = 0;
            write_AA[ii] = 0;
            address_AA[ii] = {$clog2(NUM_OF_SUBLIST){1'b0}};
            wr_data_AA[ii] = {TIME_LOG{1'b0}}; 
            enable_BB[ii] = 0;
            write_BB[ii] = 0;
            address_BB[ii] = {$clog2(NUM_OF_SUBLIST){1'b0}};
            wr_data_BB[ii] = {TIME_LOG{1'b0}}; 
        end
        nxt_state = curr_state;
        pieo_reset_done_out = 0;
        pieo_ready_for_nxt_op_out = 0;
        enq_valid_out = 0;
        f_enqueued_in_sublist_out = {$clog2(NUM_OF_SUBLIST){1'b1}};
        deq_valid_out = 0;
        deq_element_out_id = {ID_LOG{1'b1}};
        deq_element_out_rank = {RANK_LOG{1'b1}};
        deq_element_out_send_time = {TIME_LOG{1'b1}};
        flow_id_moved_out = {ID_LOG{1'b1}};
        flow_id_moved_to_sublist_out = {$clog2(NUM_OF_SUBLIST){1'b1}};
        bit_vector = {NUM_OF_SUBLIST{1'b0}};
        bit_vector_A = {(NUM_OF_SUBLIST/2){1'b0}};
        bit_vector_AA = {(NUM_OF_SUBLIST/2){1'b0}};
        bit_vector_BB = {(NUM_OF_SUBLIST/2){1'b0}};
        idx_enq = 0; //temp vals
        pred_val_deq = {(TIME_LOG){1'b0}}; //temp vals

        case(curr_state)
            RESET: begin
                for (ii=0; ii<NUM_OF_ELEMENTS_PER_SUBLIST; ii=ii+1) begin
                    enable_A[ii] = 1;
                    write_A[ii] = 1;
                    address_A[ii] = curr_address;
                    wr_data_A_id[ii] = 0;
                    wr_data_A_rank[ii] = {RANK_LOG{1'b1}};
                    wr_data_A_send_time[ii] = {TIME_LOG{1'b1}}; 
                    enable_AA[ii] = 1;
                    write_AA[ii] = 1;
                    address_AA[ii] = curr_address;
                    wr_data_AA[ii] = {TIME_LOG{1'b1}}; 
                    if (curr_address == NUM_OF_SUBLIST - 1) begin
                        nxt_state = RESET_DONE;
                    end
                end
            end

            RESET_DONE: begin
                pieo_reset_done_out = 1;
                nxt_state = IDLE;
            end

            IDLE: begin
                if (start) begin
                    pieo_ready_for_nxt_op_out = 1;
                    if (enqueue_f_in) begin
                        //figure out the right sublist to enq
                        for (ii=0; ii<NUM_OF_SUBLIST; ii=ii+1) begin
                            bit_vector[ii] = (pointer_array_smallest_rank[ii] > f_in_rank);
                        end
                        nxt_state = ENQ_FETCH_SUBLIST_FROM_MEM;
                    end
                    else if (dequeue_in) begin
                        //figure out the right sublist to deq
                        for (ii=0; ii<NUM_OF_SUBLIST; ii=ii+1) begin
                            bit_vector[ii] = (curr_time_in >= pointer_array_smallest_send_time[ii]);
                        end
                        nxt_state = DEQ_FETCH_SUBLIST_FROM_MEM;
                    end else if (dequeue_f_in) begin
                        //figure out the right sublist to deq
                        for (ii=0; ii<NUM_OF_SUBLIST; ii=ii+1) begin
                            bit_vector[ii] = (sublist_id_in == pointer_array_id[ii]);
                        end
                        nxt_state = DEQ_FETCH_SUBLIST_FROM_MEM;
                    end
                end
            end

            ENQ_FETCH_SUBLIST_FROM_MEM: begin
                if (valid_reg) begin
                    for (ii=0; ii<NUM_OF_ELEMENTS_PER_SUBLIST; ii=ii+1) begin
                        enable_A[ii] = 1;
                        write_A[ii] = 0;
                        address_A[ii] = s_id;
                        enable_AA[ii] = 1;
                        write_AA[ii] = 0;
                        address_AA[ii] = s_id;

                        if (s_full && s_neigh_enq_type != NONE) begin
                            enable_B[ii] = 1;
                            write_B[ii] = 0;
                            address_B[ii] = s_neigh_enq_id;
                            enable_BB[ii] = 1;
                            write_BB[ii] = 0;
                            address_BB[ii] = s_neigh_enq_id;
                        end
                    end
                    nxt_state = POS_TO_ENQUEUE;
                end
            end

            POS_TO_ENQUEUE: begin
                if (~s_reg_full) begin
                    for (ii=0; ii<NUM_OF_ELEMENTS_PER_SUBLIST; ii=ii+1) begin
                        bit_vector_A[ii] = (rd_data_A_rank[ii] > f_in_reg_rank);
                    end
                    for (ii=0; ii<NUM_OF_ELEMENTS_PER_SUBLIST; ii=ii+1) begin
                        bit_vector_AA[ii] = (rd_data_AA[ii] > f_in_reg_send_time);
                    end
                end else begin
                    //new element is getting inserted in B
                    if (f_in_reg_rank >= rd_data_A_rank[NUM_OF_ELEMENTS_PER_SUBLIST-1]) begin
                        for (ii=0; ii<NUM_OF_ELEMENTS_PER_SUBLIST; ii=ii+1)begin
                            bit_vector_BB[ii] = (rd_data_BB[ii] > f_in_reg_send_time);
                        end
                    end
                    else begin //new element in A, last element of A in B
                        for (ii=0; ii<NUM_OF_ELEMENTS_PER_SUBLIST; ii=ii+1)begin
                            bit_vector_A[ii] = (rd_data_A_rank[ii] > f_in_reg_rank);
                        end
                        for (ii=0; ii<NUM_OF_ELEMENTS_PER_SUBLIST; ii=ii+1)begin
                            bit_vector_AA[ii] = (rd_data_AA[ii] > f_in_reg_send_time);
                        end
                        for (ii=0; ii<NUM_OF_ELEMENTS_PER_SUBLIST; ii=ii+1)begin
                            bit_vector_BB[ii] = (rd_data_BB[ii] > rd_data_A_send_time[NUM_OF_ELEMENTS_PER_SUBLIST-1]);
                        end
                    end
                end
                nxt_state = ENQ_WRITE_BACK_TO_MEM;
            end

            ENQ_WRITE_BACK_TO_MEM: begin
                case (enqueue_case_reg)
                    0: begin
                        if (valid_A_reg & valid_AA_reg) begin
                            enq_valid_out = 1;
                            f_enqueued_in_sublist_out = s_reg_id;
                            flow_id_moved_out = {ID_LOG{1'b1}};
                            flow_id_moved_to_sublist_out = {$clog2(NUM_OF_SUBLIST){1'b1}};
                            for (ii=0; ii<NUM_OF_ELEMENTS_PER_SUBLIST; ii=ii+1) begin
                                enable_A[ii] = 1;
                                write_A[ii] = 1;
                                address_A[ii] = s_reg_id;
                                if (ii < encode_A_reg) begin
                                    wr_data_A_id[ii] = rd_data_A_id_reg[ii];
                                    wr_data_A_rank[ii] = rd_data_A_rank_reg[ii];
                                    wr_data_A_send_time[ii] = rd_data_A_send_time_reg[ii];
                                end else if (ii == encode_A_reg) begin
                                    wr_data_A_id[ii] = f_in_reg_id;
                                    wr_data_A_rank[ii] = f_in_reg_rank;
                                    wr_data_A_send_time[ii] = f_in_reg_send_time;
                                end else if (ii != 0) begin
                                    wr_data_A_id[ii] = rd_data_A_id_reg[ii-1];
                                    wr_data_A_rank[ii] = rd_data_A_rank_reg[ii-1];
                                    wr_data_A_send_time[ii] = rd_data_A_send_time_reg[ii-1];
                                end
                                enable_AA[ii] = 1;
                                write_AA[ii] = 1;
                                address_AA[ii] = s_reg_id;
                                if (ii < encode_AA_reg) begin
                                    wr_data_AA[ii] = rd_data_AA_reg[ii];
                                end else if (ii == encode_AA_reg) begin
                                    wr_data_AA[ii] = f_in_reg_send_time;
                                end else if (ii != 0) begin
                                    wr_data_AA[ii] = rd_data_AA_reg[ii-1];
                                end
                            end
                            nxt_state = IDLE;
                        end
                    end

                    1: begin
                        if (valid_BB_reg) begin
                            enq_valid_out = 1;
                            f_enqueued_in_sublist_out = s_neigh_reg_id;
                            flow_id_moved_out = {ID_LOG{1'b1}};
                            flow_id_moved_to_sublist_out = {$clog2(NUM_OF_SUBLIST){1'b1}};
                            for (ii=0; ii<NUM_OF_ELEMENTS_PER_SUBLIST; ii=ii+1) begin
                                enable_B[ii] = 1;
                                write_B[ii] = 1;
                                address_B[ii] = s_neigh_reg_id;
                                if (ii == 0) begin
                                    wr_data_B_id[ii] = f_in_reg_id;
                                    wr_data_B_rank[ii] = f_in_reg_rank;
                                    wr_data_B_send_time[ii] = f_in_reg_send_time;
                                end else if (ii != 0) begin
                                    wr_data_B_id[ii] = rd_data_B_id_reg[ii-1];
                                    wr_data_B_rank[ii] = rd_data_B_rank_reg[ii-1];
                                    wr_data_B_send_time[ii] = rd_data_B_send_time_reg[ii-1];
                                end
                                enable_BB[ii] = 1;
                                write_BB[ii] = 1;
                                address_BB[ii] = s_neigh_reg_id;
                                if (ii < encode_BB_reg) begin
                                    wr_data_BB[ii] = rd_data_BB_reg[ii];
                                end else if (ii == encode_BB_reg) begin
                                    wr_data_BB[ii] = f_in_reg_send_time;
                                end else if (ii != 0) begin
                                    wr_data_BB[ii] = rd_data_BB_reg[ii-1];
                                end
                            end
                            nxt_state = IDLE;
                        end
                    end

                    2: begin
                        if (valid_A_reg & (valid_AA_reg||idx_enq_reg) & valid_BB_reg) begin
                            enq_valid_out = 1;
                            f_enqueued_in_sublist_out = s_reg_id;
                            flow_id_moved_out = element_moving_reg_id;
                            flow_id_moved_to_sublist_out = s_neigh_reg_id;
                            idx_enq = (valid_AA_reg) ? encode_AA_reg : idx_enq_reg;
                            for (ii=0; ii<NUM_OF_ELEMENTS_PER_SUBLIST; ii=ii+1) begin
                                enable_A[ii] = 1;
                                write_A[ii] = 1;
                                address_A[ii] = s_reg_id;
                                if (ii < encode_A_reg) begin
                                    wr_data_A_id[ii] = rd_data_A_id_reg[ii];
                                    wr_data_A_rank[ii] = rd_data_A_rank_reg[ii];
                                    wr_data_A_send_time[ii] = rd_data_A_send_time_reg[ii];
                                end else if (ii == encode_A_reg) begin
                                    wr_data_A_id[ii] = f_in_reg_id;
                                    wr_data_A_rank[ii] = f_in_reg_rank;
                                    wr_data_A_send_time[ii] = f_in_reg_send_time;
                                end else if (ii !=0) begin
                                    wr_data_A_id[ii] = rd_data_A_id_reg[ii-1];
                                    wr_data_A_rank[ii] = rd_data_A_rank_reg[ii-1];
                                    wr_data_A_send_time[ii] = rd_data_A_send_time_reg[ii-1];
                                end
                                enable_AA[ii] = 1;
                                write_AA[ii] = 1;
                                address_AA[ii] = s_reg_id;
                                if (pred_moving_reg == f_in_reg_send_time) begin
                                    wr_data_AA[ii] = rd_data_AA_reg[ii];
                                end else if (pred_moving_reg < f_in_reg_send_time) begin
                                    if (rd_data_AA_reg[ii] < pred_moving_reg) begin
                                        wr_data_AA[ii] = rd_data_AA_reg[ii];
                                    end else if (rd_data_AA_reg[ii] == pred_moving_reg
                                                || ii < idx_enq) begin
                                        if (ii == idx_enq-1)
                                            wr_data_AA[ii] = f_in_reg_send_time;
                                        else if (ii < NUM_OF_ELEMENTS_PER_SUBLIST-1)
                                            wr_data_AA[ii] = rd_data_AA_reg[ii+1];
                                    end else  begin
                                        wr_data_AA[ii] = rd_data_AA_reg[ii];
                                    end
                                end else begin
                                    if (ii < idx_enq) begin
                                        wr_data_AA[ii] = rd_data_AA_reg[ii];
                                    end else if (ii == idx_enq) begin
                                        wr_data_AA[ii] = f_in_reg_send_time;
                                    end else if (ii > idx_enq && ii != 0
                                                && rd_data_AA_reg[ii] <= pred_moving_reg) begin
                                        wr_data_AA[ii] = rd_data_AA_reg[ii-1];
                                    end else begin
                                        wr_data_AA[ii] = rd_data_AA_reg[ii];
                                    end
                                end
                                enable_B[ii] = 1;
                                write_B[ii] = 1;
                                address_B[ii] = s_neigh_reg_id;
                                if (ii == 0) begin
                                    wr_data_B_id[ii] = element_moving_reg_id;
                                    wr_data_B_rank[ii] = element_moving_reg_rank;
                                    wr_data_B_send_time[ii] = element_moving_reg_send_time;
                                end else if (ii != 0) begin
                                    wr_data_B_id[ii] = rd_data_B_id_reg[ii-1];
                                    wr_data_B_rank[ii] = rd_data_B_rank_reg[ii-1];
                                    wr_data_B_send_time[ii] = rd_data_B_send_time_reg[ii-1];
                                end
                                enable_BB[ii] = 1;
                                write_BB[ii] = 1;
                                address_BB[ii] = s_neigh_reg_id;
                                if (ii < encode_BB_reg) begin
                                    wr_data_BB[ii] = rd_data_BB_reg[ii];
                                end else if (ii == encode_BB_reg) begin
                                    wr_data_BB[ii] = pred_moving_reg;
                                end else if (ii != 0) begin
                                    wr_data_BB[ii] = rd_data_BB_reg[ii-1];
                                end
                            end
                            nxt_state = IDLE;
                        end
                    end

                    default: begin
                        enq_valid_out = 0;
                        f_enqueued_in_sublist_out = {$clog2(NUM_OF_SUBLIST){1'b1}};
                        flow_id_moved_out = {ID_LOG{1'b1}};
                        flow_id_moved_to_sublist_out = {$clog2(NUM_OF_SUBLIST){1'b1}};
                        for (ii=0; ii<NUM_OF_ELEMENTS_PER_SUBLIST; ii=ii+1) begin
                            enable_A[ii] = 1;
                            write_A[ii] = 1;
                            address_A[ii] = s_reg_id;
                            wr_data_A_id[ii] = rd_data_A_id_reg[ii];
                            wr_data_A_rank[ii] = rd_data_A_rank_reg[ii];
                            wr_data_A_send_time[ii] = rd_data_A_send_time_reg[ii];
                            enable_AA[ii] = 1;
                            write_AA[ii] = 1;
                            address_AA[ii] = s_reg_id;
                            wr_data_AA[ii] = rd_data_AA_reg[ii];
                            enable_B[ii] = 1;
                            write_B[ii] = 1;
                            address_B[ii] = s_neigh_reg_id;
                            wr_data_B_id[ii] = rd_data_B_id_reg[ii];
                            wr_data_B_rank[ii] = rd_data_B_rank_reg[ii];
                            wr_data_B_send_time[ii] = rd_data_B_send_time_reg[ii];
                            enable_BB[ii] = 1;
                            write_BB[ii] = 1;
                            address_BB[ii] = s_neigh_reg_id;
                            wr_data_BB[ii] = rd_data_BB_reg[ii];
                        end
                        nxt_state = IDLE;
                    end
                endcase
            end

            DEQ_FETCH_SUBLIST_FROM_MEM: begin
                if (~valid_reg) begin
                    deq_valid_out = 1;
                    deq_element_out_id = {ID_LOG{1'b1}};
                    deq_element_out_rank = {RANK_LOG{1'b1}};
                    deq_element_out_send_time = {TIME_LOG{1'b1}};
                    flow_id_moved_out = {ID_LOG{1'b1}};
                    flow_id_moved_to_sublist_out = {$clog2(NUM_OF_SUBLIST){1'b1}};
                    nxt_state = IDLE;
                end else if (valid_reg) begin
                    for (ii=0; ii<NUM_OF_ELEMENTS_PER_SUBLIST; ii=ii+1) begin
                        enable_A[ii] = 1;
                        write_A[ii] = 0;
                        address_A[ii] = s_id;
                        enable_AA[ii] = 1;
                        write_AA[ii] = 0;
                        address_AA[ii] = s_id;

                        if (s_full && s_neigh_deq_type != NONE) begin
                            enable_B[ii] = 1;
                            write_B[ii] = 0;
                            address_B[ii] = s_neigh_deq_id;
                            enable_BB[ii] = 1;
                            write_BB[ii] = 0;
                            address_BB[ii] = s_neigh_deq_id;
                        end
                    end
                    nxt_state = POS_TO_DEQUEUE;
                end
            end

            POS_TO_DEQUEUE: begin
                if (dequeue_in_reg) begin
                    for (ii=0; ii<NUM_OF_ELEMENTS_PER_SUBLIST; ii=ii+1) begin
                        pred_eval[ii] = (curr_time_in_reg >= rd_data_A_send_time[ii]);
                        logic_pieo_select[ii] = (rd_data_A_id[ii] >= p_start_in_reg) && (rd_data_A_id[ii] <= p_end_in_reg);
                        bit_vector_A[ii] = pred_eval[ii] && logic_pieo_select[ii];
                        //bit_vector_A[ii] = (curr_time_in_reg >= rd_data_A_send_time[ii]) && (rd_data_A_id[ii] >= p_start_in_reg) && (rd_data_A_id[ii] <= p_end_in_reg);
                    end
                end else if (dequeue_f_in_reg) begin
                    for (ii=0; ii<NUM_OF_ELEMENTS_PER_SUBLIST; ii=ii+1) begin
                        bit_vector_A[ii] = (flow_id_in_reg == rd_data_A_id[ii]);
                    end
                end

                if (s_neigh_type_reg != NONE) begin
                    //insertion
                    for (ii=0; ii<NUM_OF_ELEMENTS_PER_SUBLIST; ii=ii+1) begin
                        bit_vector_AA[ii] = (rd_data_AA[ii] > element_moving_send_time);
                    end
                    //deletion
                    for (ii=0; ii<NUM_OF_ELEMENTS_PER_SUBLIST; ii=ii+1) begin
                        bit_vector_BB[ii] = (rd_data_BB[ii] == element_moving_send_time);
                    end
                end
                nxt_state = DEQ_WRITE_BACK_TO_MEM;
            end

            DEQ_WRITE_BACK_TO_MEM: begin
                if (~valid_A_reg) begin
                    deq_valid_out = 1;
                    deq_element_out_id = {ID_LOG{1'b1}};
                    deq_element_out_rank = {RANK_LOG{1'b1}};
                    deq_element_out_send_time = {TIME_LOG{1'b1}};
                    flow_id_moved_out = {ID_LOG{1'b1}};
                    flow_id_moved_to_sublist_out = {$clog2(NUM_OF_SUBLIST){1'b1}};
                    nxt_state = IDLE;
                end else begin
                    if (s_neigh_type_reg == NONE) begin
                        if (valid_A_reg) begin
                            deq_valid_out = 1;
                            deq_element_out_id = element_dequeued_reg_id;
                            deq_element_out_rank = element_dequeued_reg_rank;
                            deq_element_out_send_time = element_dequeued_reg_send_time;
                            flow_id_moved_out = {ID_LOG{1'b1}};
                            flow_id_moved_to_sublist_out = {$clog2(NUM_OF_SUBLIST){1'b1}};
                            for (ii=0; ii<NUM_OF_ELEMENTS_PER_SUBLIST; ii=ii+1) begin
                                enable_A[ii] = 1;
                                write_A[ii] = 1;
                                address_A[ii] = s_reg_id;
                                if (ii < encode_A_reg) begin
                                    wr_data_A_id[ii] = rd_data_A_id_reg[ii];
                                    wr_data_A_rank[ii] = rd_data_A_rank_reg[ii];
                                    wr_data_A_send_time[ii] = rd_data_A_send_time_reg[ii];
                                end else begin
                                    if (ii == NUM_OF_ELEMENTS_PER_SUBLIST-1) begin
                                        wr_data_A_id[ii] = 0;
                                        wr_data_A_rank[ii] = {RANK_LOG{1'b1}};
                                        wr_data_A_send_time[ii] = {TIME_LOG{1'b1}};
                                    end else begin
                                        wr_data_A_id[ii] = rd_data_A_id_reg[ii+1];
                                        wr_data_A_rank[ii] = rd_data_A_rank_reg[ii+1];
                                        wr_data_A_send_time[ii] = rd_data_A_send_time_reg[ii+1];
                                    end
                                end
                                enable_AA[ii] = 1;
                                write_AA[ii] = 1;
                                address_AA[ii] = s_reg_id;
                                if (rd_data_AA_reg[ii] < element_dequeued_reg_send_time) begin
                                    wr_data_AA[ii] = rd_data_AA_reg[ii];
                                end else begin
                                    if (ii == NUM_OF_ELEMENTS_PER_SUBLIST-1) begin
                                        wr_data_AA[ii] = {TIME_LOG{1'b1}};
                                    end else begin
                                        wr_data_AA[ii] = rd_data_AA_reg[ii+1];
                                    end
                                end
                            end
                            nxt_state = IDLE;
                        end
                    end else begin
                        if (valid_A_reg & (valid_AA_reg||idx_enq_reg) & valid_BB_reg) begin
                            deq_valid_out = 1;
                            deq_element_out_id = element_dequeued_reg_id;
                            deq_element_out_rank = element_dequeued_reg_rank;
                            deq_element_out_send_time = element_dequeued_reg_send_time;
                            flow_id_moved_out = element_moving_reg_id;
                            flow_id_moved_to_sublist_out = s_reg_id;

                            pred_val_deq = element_dequeued_reg_send_time;
                            idx_enq = (valid_AA_reg) ? encode_AA_reg : idx_enq_reg;
                            for (ii=0; ii<NUM_OF_ELEMENTS_PER_SUBLIST; ii=ii+1) begin
                                enable_A[ii] = 1;
                                write_A[ii] = 1;
                                address_A[ii] = s_reg_id;
                                if (s_neigh_type_reg == LEFT) begin
                                    if (ii == 0) begin
                                        wr_data_A_id[ii] = element_moving_reg_id;
                                        wr_data_A_rank[ii] = element_moving_reg_rank;
                                        wr_data_A_send_time[ii] = element_moving_reg_send_time;
                                    end else if (ii <= encode_A_reg) begin
                                        wr_data_A_id[ii] = rd_data_A_id_reg[ii-1];
                                        wr_data_A_rank[ii] = rd_data_A_rank_reg[ii-1];
                                        wr_data_A_send_time[ii] = rd_data_A_send_time_reg[ii-1];
                                    end else begin
                                        wr_data_A_id[ii] = rd_data_A_id_reg[ii];
                                        wr_data_A_rank[ii] = rd_data_A_rank_reg[ii];
                                        wr_data_A_send_time[ii] = rd_data_A_send_time_reg[ii];
                                    end
                                end else begin
                                    if (ii < encode_A_reg) begin
                                        wr_data_A_id[ii] = rd_data_A_id_reg[ii];
                                        wr_data_A_rank[ii] = rd_data_A_rank_reg[ii];
                                        wr_data_A_send_time[ii] = rd_data_A_send_time_reg[ii];
                                    end else begin
                                        if (ii == NUM_OF_ELEMENTS_PER_SUBLIST-1) begin
                                            wr_data_A_id[ii] = element_moving_reg_id;
                                            wr_data_A_rank[ii] = element_moving_reg_rank;
                                            wr_data_A_send_time[ii] = element_moving_reg_send_time;
                                        end else begin
                                            wr_data_A_id[ii] = rd_data_A_id_reg[ii+1];
                                            wr_data_A_rank[ii] = rd_data_A_rank_reg[ii+1];
                                            wr_data_A_send_time[ii] = rd_data_A_send_time_reg[ii+1];
                                        end
                                    end
                                end
                                enable_AA[ii] = 1;
                                write_AA[ii] = 1;
                                address_AA[ii] = s_reg_id;
                                if (pred_val_deq == pred_moving_reg) begin
                                    wr_data_AA[ii] = rd_data_AA_reg[ii];
                                end else if (pred_val_deq < pred_moving_reg) begin
                                    if (rd_data_AA_reg[ii] < pred_val_deq) begin
                                        wr_data_AA[ii] = rd_data_AA_reg[ii];
                                    end else if (rd_data_AA_reg[ii] == pred_val_deq || ii < idx_enq) begin
                                        if (ii == idx_enq-1)
                                            wr_data_AA[ii] = pred_moving_reg;
                                        else if (ii < NUM_OF_ELEMENTS_PER_SUBLIST-1)
                                            wr_data_AA[ii] = rd_data_AA_reg[ii+1];
                                    end else  begin
                                        wr_data_AA[ii] = rd_data_AA_reg[ii];
                                    end
                                end else begin
                                    if (ii < idx_enq) begin
                                        wr_data_AA[ii] = rd_data_AA_reg[ii];
                                    end else if (ii == idx_enq) begin
                                        wr_data_AA[ii] = pred_moving_reg;
                                    end else if (ii > idx_enq && ii != 0 && rd_data_AA_reg[ii] <= pred_val_deq) begin
                                        wr_data_AA[ii] = rd_data_AA_reg[ii-1];
                                    end else begin
                                        wr_data_AA[ii] = rd_data_AA_reg[ii];
                                    end
                                end
                                enable_B[ii] = 1;
                                write_B[ii] = 1;
                                address_B[ii] = s_neigh_reg_id;
                                if (s_neigh_type_reg == LEFT) begin
                                    if (ii == s_neigh_reg_num-1) begin
                                        wr_data_B_id[ii] = 0;
                                        wr_data_B_rank[ii] = {RANK_LOG{1'b1}};
                                        wr_data_B_send_time[ii] = {TIME_LOG{1'b1}};
                                    end else begin
                                        wr_data_B_id[ii] = rd_data_B_id_reg[ii];
                                        wr_data_B_rank[ii] = rd_data_B_rank_reg[ii];
                                        wr_data_B_send_time[ii] = rd_data_B_send_time_reg[ii];
                                    end
                                end else begin
                                    if (ii < NUM_OF_ELEMENTS_PER_SUBLIST-1) begin
                                        wr_data_B_id[ii] = rd_data_B_id_reg[ii+1];
                                        wr_data_B_rank[ii] = rd_data_B_rank_reg[ii+1];
                                        wr_data_B_send_time[ii] = rd_data_B_send_time_reg[ii+1];
                                    end else begin
                                        wr_data_B_id[ii] = rd_data_B_id_reg[ii];
                                        wr_data_B_rank[ii] = rd_data_B_rank_reg[ii];
                                        wr_data_B_send_time[ii] = rd_data_B_send_time_reg[ii];
                                    end
                                end
                                enable_BB[ii] = 1;
                                write_BB[ii] = 1;
                                address_BB[ii] = s_neigh_reg_id;
                                if (ii < encode_BB_reg) begin
                                    wr_data_BB[ii] = rd_data_BB_reg[ii];
                                end else begin
                                    if (ii == NUM_OF_ELEMENTS_PER_SUBLIST-1) begin
                                        wr_data_BB[ii] = {TIME_LOG{1'b1}};
                                    end else begin
                                        wr_data_BB[ii] = rd_data_BB_reg[ii+1];
                                    end
                                end
                            end
                            nxt_state = IDLE;
                        end
                    end
                end
            end
        endcase
    end

    always @(posedge clk) begin
        if (rst) begin
            curr_state <= RESET;
            free_list_head_reg <= 0;
            //initialize pointer array
            for (ii=0; ii<NUM_OF_SUBLIST; ii=ii+1) begin
                pointer_array_id[ii] = ii;
                pointer_array_smallest_rank[ii] = {RANK_LOG{1'b1}};
                pointer_array_smallest_send_time[ii] = {TIME_LOG{1'b1}};
                pointer_array_full[ii] = 0;
                pointer_array_num[ii] = 0;
            end
            curr_address <= 0;
            enqueue_case_reg <= 3;
            idx_enq_reg <= 0;
            f_in_reg_id <= 0;
            f_in_reg_rank <= 0;
            f_in_reg_send_time <= 0;
            p_start_in_reg <= 0;
            p_end_in_reg <= 0;
            dequeue_in_reg <= 0;
            curr_time_in_reg <= 0;
            dequeue_f_in_reg <= 0;
            flow_id_in_reg <= 0;
        end else begin
            curr_state <= nxt_state;

            if (curr_state == RESET) begin
                curr_address <= curr_address + 1;
            end else if (curr_state == IDLE) begin
                if (start) begin
                    f_in_reg_id <= f_in_id;
                    f_in_reg_rank <= f_in_rank;
                    f_in_reg_send_time <= f_in_send_time;
                    p_start_in_reg <= p_start_in;
                    p_end_in_reg <= p_end_in;
                    dequeue_in_reg <= dequeue_in;
                    curr_time_in_reg <= curr_time_in;
                    dequeue_f_in_reg <= dequeue_f_in;
                    flow_id_in_reg <= flow_id_in;
                    valid_reg <= valid;
                    encode_reg <= encode;
                    if (enqueue_f_in) begin
                        s_idx_reg <= (encode==0) ? encode : encode-1;
                    end else if (dequeue_in || dequeue_f_in) begin
                        s_idx_reg <= encode;
                    end
                end                
            end else if (curr_state == ENQ_FETCH_SUBLIST_FROM_MEM) begin
                if (valid_reg) begin
                    s_reg_id <= s_id;
                    s_reg_smallest_rank <= s_smallest_rank;
                    s_reg_smallest_send_time <= s_smallest_send_time;
                    s_reg_full <= s_full;
                    s_reg_num <= s_num;
                    
                    s_neigh_reg_id <= s_neigh_enq_id;
                    s_neigh_reg_smallest_rank <= s_neigh_enq_smallest_rank;
                    s_neigh_reg_smallest_send_time <= s_neigh_enq_smallest_send_time;
                    s_neigh_reg_full <= s_neigh_enq_full;
                    s_neigh_reg_num <= s_neigh_enq_num;
                    
                    s_neigh_type_reg <= s_neigh_enq_type;
                    
                    s_free_reg_id <= s_free_id;
                    s_free_reg_smallest_rank <= s_free_smallest_rank;
                    s_free_reg_smallest_send_time <= s_free_smallest_send_time;
                    s_free_reg_full <= s_free_full;
                    s_free_reg_num <= s_free_num;
                end
            end else if (curr_state == POS_TO_ENQUEUE) begin
                element_moving_reg_id <= rd_data_A_id[NUM_OF_ELEMENTS_PER_SUBLIST-1];
                element_moving_reg_rank <= rd_data_A_rank[NUM_OF_ELEMENTS_PER_SUBLIST-1];
                element_moving_reg_send_time <= rd_data_A_send_time[NUM_OF_ELEMENTS_PER_SUBLIST-1];
                pred_moving_reg <= rd_data_A_send_time[NUM_OF_ELEMENTS_PER_SUBLIST-1];
                if (~s_reg_full) begin
                    valid_A_reg <= valid_A;
                    encode_A_reg <= encode_A;
                    valid_AA_reg <= valid_AA;
                    encode_AA_reg <= encode_AA;
                    enqueue_case_reg <= 0;
                    //update pointer array
                    if (s_idx_reg == free_list_head_reg) begin
                        free_list_head_reg <= free_list_head_reg + 1;
                    end
                end else begin
                    //new element is getting inserted in B
                    if (f_in_reg_rank >= rd_data_A_rank[NUM_OF_ELEMENTS_PER_SUBLIST-1]) begin
                        valid_BB_reg <= valid_BB;
                        encode_BB_reg <= encode_BB;
                        enqueue_case_reg <= 1;
                    end else begin
                        //new element in A, last element of A in B
                        valid_A_reg <= valid_A;
                        encode_A_reg <= encode_A;
                        valid_AA_reg <= valid_AA;
                        encode_AA_reg <= encode_AA;
                        valid_BB_reg <= valid_BB;
                        encode_BB_reg <= encode_BB;
                        enqueue_case_reg <= 2;
                        if (f_in_reg_send_time >= rd_data_AA[NUM_OF_ELEMENTS_PER_SUBLIST-1])
                            idx_enq_reg <= NUM_OF_ELEMENTS_PER_SUBLIST;
                        else
                            idx_enq_reg <= 0;
                    end
                    //update pointer array
                    if (s_neigh_type_reg == FREE) begin
                        for (ii = 0; ii < NUM_OF_SUBLIST-1; ii=ii+1) begin
                            if (ii > s_idx_reg && ii < free_list_head_reg) begin
                                pointer_array_id[ii+1] <= pointer_array_id[ii];
                                pointer_array_smallest_rank[ii+1] <= pointer_array_smallest_rank[ii];
                                pointer_array_smallest_send_time[ii+1] <= pointer_array_smallest_send_time[ii];
                                pointer_array_full[ii+1] <= pointer_array_full[ii];
                                pointer_array_num[ii+1] <= pointer_array_num[ii];
                                if (ii == s_idx_reg+1) begin
                                    pointer_array_id[ii] <= s_free_reg_id;
                                    pointer_array_smallest_rank[ii] <= s_free_reg_smallest_rank;
                                    pointer_array_smallest_send_time[ii] <= s_free_reg_smallest_send_time;
                                    pointer_array_full[ii] <= s_free_reg_full;
                                    pointer_array_num[ii] <= s_free_reg_num;
                                end
                            end
                        end
                        free_list_head_reg <= free_list_head_reg + 1;
                    end else if (s_idx_reg+1 == free_list_head_reg) begin
                        free_list_head_reg <= free_list_head_reg + 1;
                    end
                end
            end else if (curr_state == ENQ_WRITE_BACK_TO_MEM) begin
                if (enqueue_case_reg == 0) begin
                    if (valid_A_reg & valid_AA_reg) begin
                        for (ii=0; ii<NUM_OF_SUBLIST; ii=ii+1) begin
                            if (ii == s_idx_reg) begin
                                pointer_array_id[ii] <= s_reg_id;
                                pointer_array_smallest_rank[ii] <= (encode_A_reg == 0) 
                                                                    ? f_in_reg_rank : rd_data_A_rank_reg[0];
                                pointer_array_smallest_send_time[ii] <= (encode_AA_reg == 0) 
                                                                    ? f_in_reg_send_time : rd_data_AA_reg[0];
                                pointer_array_full[ii] <= (s_reg_full || s_reg_num==NUM_OF_ELEMENTS_PER_SUBLIST-1);
                                pointer_array_num[ii] <= s_reg_num + 1;
                            end
                        end
                    end
                end else if (enqueue_case_reg == 1) begin
                    if (valid_BB_reg) begin
                        for (ii=0; ii<NUM_OF_SUBLIST; ii=ii+1) begin
                            if (ii == s_idx_reg+1) begin
                                pointer_array_id[ii] <= s_neigh_reg_id;
                                pointer_array_smallest_rank[ii] <= f_in_reg_rank;
                                pointer_array_smallest_send_time[ii] <= (encode_BB_reg == 0) 
                                                                        ? f_in_reg_send_time : rd_data_BB_reg[0];
                                pointer_array_full[ii] <= (s_neigh_reg_num==NUM_OF_ELEMENTS_PER_SUBLIST-1);
                                pointer_array_num[ii] <= s_neigh_reg_num + 1;
                            end
                        end
                    end
                end else if (enqueue_case_reg == 2) begin
                    if (valid_A_reg & (valid_AA_reg||idx_enq_reg) & valid_BB_reg) begin
                        for (ii=0; ii<NUM_OF_SUBLIST; ii=ii+1) begin
                            if (ii == s_idx_reg) begin
                                pointer_array_id[ii] <= s_reg_id;
                                pointer_array_smallest_rank[ii] <= (encode_A_reg == 0) ? f_in_reg_rank : rd_data_A_rank_reg[0];
                                if (rd_data_A_send_time_reg[NUM_OF_ELEMENTS_PER_SUBLIST-1] == rd_data_AA_reg[0]) begin
                                    pointer_array_smallest_send_time[ii] <= (f_in_reg_send_time < rd_data_AA_reg[1])
                                                                            ? f_in_reg_send_time : rd_data_AA_reg[1];
                                end else begin
                                    pointer_array_smallest_send_time[ii] <= (f_in_reg_send_time < rd_data_AA_reg[0])
                                                                            ? f_in_reg_send_time : rd_data_AA_reg[0];
                                end
                                pointer_array_full[ii] <= (s_reg_full || s_reg_num==NUM_OF_ELEMENTS_PER_SUBLIST-1);
                                pointer_array_num[ii] <= s_num;
                            end else if (ii == s_idx_reg+1) begin
                                pointer_array_id[ii] <= s_neigh_reg_id;
                                pointer_array_smallest_rank[ii] <= rd_data_A_rank_reg[NUM_OF_ELEMENTS_PER_SUBLIST-1];
                                pointer_array_smallest_send_time[ii] <= (encode_BB_reg == 0)
                                                                        ? rd_data_A_send_time_reg[NUM_OF_ELEMENTS_PER_SUBLIST-1]: rd_data_BB_reg[0];
                                pointer_array_full[ii] <= (s_neigh_reg_num==NUM_OF_ELEMENTS_PER_SUBLIST-1);
                                pointer_array_num[ii] <= s_neigh_reg_num + 1;
                            end
                        end
                    end
                end
            end else if (curr_state == DEQ_FETCH_SUBLIST_FROM_MEM) begin
                if (~valid_reg) begin
                end
                else if (valid_reg) begin                    
                    s_reg_id <= s_id;
                    s_reg_smallest_rank <= s_smallest_rank;
                    s_reg_smallest_send_time <= s_smallest_send_time;
                    s_reg_full <= s_full;
                    s_reg_num <= s_num;
                    
                    s_neigh_reg_id <= s_neigh_deq_id;
                    s_neigh_reg_smallest_rank <= s_neigh_deq_smallest_rank;
                    s_neigh_reg_smallest_send_time <= s_neigh_deq_smallest_send_time;
                    s_neigh_reg_full <= s_neigh_deq_full;
                    s_neigh_reg_num <= s_neigh_deq_num;
                    
                    s_neigh_type_reg <= s_neigh_deq_type;
                    
                    s_free_reg_id <= s_free_id;
                    s_free_reg_smallest_rank <= s_free_smallest_rank;
                    s_free_reg_smallest_send_time <= s_free_smallest_send_time;
                    s_free_reg_full <= s_free_full;
                    s_free_reg_num <= s_free_num;
                    
                    element_moving_idx_reg <= element_moving_idx;
                end
            end else if (curr_state == POS_TO_DEQUEUE) begin
                valid_A_reg <= valid_A;
                encode_A_reg <= encode_A;
                valid_AA_reg <= valid_AA;
                encode_AA_reg <= encode_AA;
                valid_BB_reg <= valid_BB;
                encode_BB_reg <= encode_BB;
                if (s_reg_num == 1) begin
                    //re-arrange pointer array
                    for (ii=0; ii<NUM_OF_SUBLIST; ii=ii+1)
                    begin
                        if (ii == free_list_head_reg-1) begin
                            pointer_array_id[ii] <= s_reg_id;
                            pointer_array_smallest_rank[ii] <= {RANK_LOG{1'b1}};
                            pointer_array_smallest_send_time[ii] <= {TIME_LOG{1'b1}};
                            pointer_array_full[ii] <= 0;
                            pointer_array_num[ii] <= 0;
                        end else if (ii >= s_idx_reg && ii < free_list_head_reg && ii < NUM_OF_SUBLIST-1)begin
                            pointer_array_id[ii] <= pointer_array_id[ii+1];
                            pointer_array_smallest_rank[ii] <= pointer_array_smallest_rank[ii+1];
                            pointer_array_smallest_send_time[ii] <= pointer_array_smallest_send_time[ii+1];
                            pointer_array_full[ii] <= pointer_array_full[ii+1];
                            pointer_array_num[ii] <= pointer_array_num[ii+1];
                        end
                    end
                    free_list_head_reg <= free_list_head_reg - 1;
                end else begin
                    if (s_neigh_type_reg != NONE) begin
                        element_moving_reg_id <= element_moving_id;
                        element_moving_reg_rank <= element_moving_rank;
                        element_moving_reg_send_time <= element_moving_send_time;
                        pred_moving_reg <= element_moving_send_time;
                        if (rd_data_B_send_time[element_moving_idx_reg] >= rd_data_AA[NUM_OF_ELEMENTS_PER_SUBLIST-1]) begin
                                idx_enq_reg <= NUM_OF_ELEMENTS_PER_SUBLIST;
                        end else begin
                                idx_enq_reg <= 0;
                        end
                        if (s_neigh_reg_num == 1) begin
                            //re-arrange pointer array
                            for (ii=0; ii<NUM_OF_SUBLIST; ii=ii+1)
                            begin
                                if (ii == free_list_head_reg-1) begin
                                    pointer_array_id[ii] <= s_neigh_reg_id;
                                    pointer_array_smallest_rank[ii] <= {RANK_LOG{1'b1}};
                                    pointer_array_smallest_send_time[ii] <= {TIME_LOG{1'b1}};
                                    pointer_array_full[ii] <= 0;
                                    pointer_array_num[ii] <= 0;
                                end else if (ii >= ((s_neigh_type_reg==LEFT) ? s_idx_reg-1 : s_idx_reg+1)
                                                    && ii < free_list_head_reg-1
                                                    && ii < NUM_OF_SUBLIST-1) begin
                                    pointer_array_id[ii] <= pointer_array_id[ii+1];
                                    pointer_array_smallest_rank[ii] <= pointer_array_smallest_rank[ii+1];
                                    pointer_array_smallest_send_time[ii] <= pointer_array_smallest_send_time[ii+1];
                                    pointer_array_full[ii] <= pointer_array_full[ii+1];
                                    pointer_array_num[ii] <= pointer_array_num[ii+1];
                                end
                            end
                            free_list_head_reg <= free_list_head_reg - 1;
                            if (s_neigh_type_reg == LEFT) s_idx_reg <= s_idx_reg-1;
                        end
                    end
                end
            end else if (curr_state == DEQ_WRITE_BACK_TO_MEM) begin
                if (~valid_A_reg) begin
                end else begin
                    if (s_neigh_type_reg == NONE) begin
                        if (valid_A_reg) begin
                            if (s_reg_num != 1) begin
                                for (ii=0; ii<NUM_OF_SUBLIST; ii=ii+1) begin
                                    if (ii == s_idx_reg) begin
                                        pointer_array_id[ii] <= s_reg_id;
                                        pointer_array_smallest_rank[ii] <= (encode_A_reg == 0) 
                                                                            ? rd_data_A_rank_reg[1] : rd_data_A_rank_reg[0];
                                        pointer_array_smallest_send_time[ii] <= (rd_data_AA_reg[0] == element_dequeued_reg_send_time)
                                                                                ? rd_data_AA_reg[1] : rd_data_AA_reg[0];
                                        pointer_array_full[ii] <= 0;
                                        pointer_array_num[ii] <= pointer_array_num[ii] - 1;
                                    end
                                end
                            end
                        end
                    end else begin
                        if (valid_A_reg & (valid_AA_reg||idx_enq_reg) & valid_BB_reg) begin
                            for (ii=0; ii<NUM_OF_SUBLIST; ii=ii+1) begin
                                if (ii == s_idx_reg) begin
                                    pointer_array_id[ii] <= s_reg_id;
                                    pointer_array_smallest_rank[ii] <= (s_neigh_type_reg==LEFT)
                                                                        ? element_moving_reg_rank
                                                                        : ((encode_A_reg == 0) ? rd_data_A_rank_reg[1]
                                                                        : rd_data_A_rank_reg[0]);
                                    if (element_dequeued_reg_send_time == rd_data_AA_reg[0]) begin
                                        pointer_array_smallest_send_time[ii] <= (element_moving_reg_send_time < rd_data_AA_reg[1])
                                                                                ? element_moving_reg_send_time : rd_data_AA_reg[1];
                                    end else begin
                                        pointer_array_smallest_send_time[ii] <= (element_moving_reg_send_time < rd_data_AA_reg[0])
                                                                                ? element_moving_reg_send_time : rd_data_AA_reg[0];
                                    end
                                    pointer_array_full[ii] = s_reg_full;
                                    pointer_array_num[ii] = s_reg_num;
                                end
                            end
                            if (s_neigh_reg_num != 1) begin
                                if (s_neigh_type_reg == LEFT) begin
                                    for (ii=0; ii<NUM_OF_SUBLIST; ii=ii+1) begin
                                        if (ii == s_idx_reg-1) begin
                                            pointer_array_id[ii] <= s_neigh_reg_id;
                                            pointer_array_smallest_rank[ii] <= s_neigh_reg_smallest_rank;
                                            pointer_array_smallest_send_time[ii] <= (element_moving_reg_send_time == rd_data_BB_reg[0])
                                                                                    ? rd_data_BB_reg[1] : rd_data_BB_reg[0];
                                            pointer_array_full[ii] <= s_neigh_reg_full;
                                            pointer_array_num[ii] <= s_neigh_reg_num - 1;
                                        end
                                    end
                                end else begin
                                    for (ii=0; ii<NUM_OF_SUBLIST; ii=ii+1) begin
                                        if (ii == s_idx_reg+1) begin
                                            pointer_array_id[ii] <= s_neigh_reg_id;
                                            pointer_array_smallest_rank[ii] <= rd_data_B_rank_reg[1];
                                            pointer_array_smallest_send_time[ii] <= (rd_data_B_send_time_reg[0] == rd_data_BB_reg[0])
                                                                                    ? rd_data_BB_reg[1] : rd_data_BB_reg[0];
                                            pointer_array_full[ii] <= s_neigh_reg_full;
                                            pointer_array_num[ii] <= s_neigh_reg_num - 1;
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
endmodule

