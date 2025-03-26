module pieo_sched_tree #(
    // scheduler style
    parameter L1_PRE_ENQ_STYLE  = 0,
    parameter L1_POST_DEQ_STYLE = 0,
    parameter L2_PRE_ENQ_STYLE  = 0,
    parameter L2_POST_DEQ_STYLE = 0,
    // fifo parameters
    parameter PORT_COUNT = 3,
    parameter N_FIFO_PER_PORT = 4,
    parameter NUM_FIFO = PORT_COUNT*N_FIFO_PER_PORT,
    parameter PKT_LEN_WIDTH = 16,
    parameter SEL_WIDTH = $clog2(NUM_FIFO),
    parameter L1_SEL_WIDTH = $clog2(N_FIFO_PER_PORT),
    parameter L2_SEL_WIDTH = $clog2(PORT_COUNT),
    // pieo parameters
    parameter TIME_LOG = (L1_PRE_ENQ_STYLE == 3) ? 32       : 2   // PRE_ENQ_SHAPER
)
(
    input wire                                  clk, rst,
    input wire [TIME_LOG-1:0]                   curr_time,
    input wire [NUM_FIFO-1:0]                   fifo_tvalid,
    input wire [NUM_FIFO*PKT_LEN_WIDTH-1:0]     fifo_packet_length,
    input wire [NUM_FIFO-1:0]                   pe_tlast,
    output reg [SEL_WIDTH-1:0]                  sel_out,
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

wire [PORT_COUNT-1:0]       l1_en_in;
wire [L1_SEL_WIDTH-1:0]     l1_sel_out  [PORT_COUNT-1:0];
wire [PORT_COUNT-1:0]       l1_en_out;

wire [L2_SEL_WIDTH-1:0]     l2_sel_out;
wire                        l2_en_out;

assign en_out = |l1_en_out;

wire [N_FIFO_PER_PORT*PKT_LEN_WIDTH-1:0]    l1_fifo_packet_length     [PORT_COUNT-1:0];
wire [N_FIFO_PER_PORT-1:0]                  l1_fifos_enqueued_next_r  [PORT_COUNT-1:0];
wire [PORT_COUNT-1:0]                       l1_pieo_valid;

wire [PORT_COUNT*PKT_LEN_WIDTH-1:0]         l2_fifo_packet_length;
wire [PORT_COUNT-1:0]                       aggr_pe_tlast, l2_pe_tlast;

genvar i;
generate
    for (i = 0; i < PORT_COUNT; i = i + 1) begin : l1_pieo
        pieo_sched #(
            .PRE_ENQ_STYLE(L1_PRE_ENQ_STYLE),
            .POST_DEQ_STYLE(L1_POST_DEQ_STYLE),
            .PORT_COUNT(1),
            .N_FIFO_PER_PORT(N_FIFO_PER_PORT)
        ) l1_pieo (
            .clk(clk),
            .rst(rst),
            .en_in(l1_en_in[i]),
            .curr_time(curr_time),
            .fifo_tvalid(fifo_tvalid[N_FIFO_PER_PORT-1+i*N_FIFO_PER_PORT -: N_FIFO_PER_PORT]),
            .fifo_packet_length(l1_fifo_packet_length[i]), 
            .pe_tlast(pe_tlast[N_FIFO_PER_PORT-1+i*N_FIFO_PER_PORT -: N_FIFO_PER_PORT]),
            .fifos_enqueued_next_r(l1_fifos_enqueued_next_r[i]),
            .sel_out(l1_sel_out[i]),
            .en_out(l1_en_out[i])
        );
        
        assign l1_pieo_valid[i] = |l1_fifos_enqueued_next_r[i];
        
        assign l1_fifo_packet_length[i] = fifo_packet_length[N_FIFO_PER_PORT*PKT_LEN_WIDTH-1+i*N_FIFO_PER_PORT*PKT_LEN_WIDTH -: N_FIFO_PER_PORT*PKT_LEN_WIDTH];
        assign l2_fifo_packet_length[PKT_LEN_WIDTH-1+i*PKT_LEN_WIDTH -: PKT_LEN_WIDTH] = l1_fifo_packet_length[i][PKT_LEN_WIDTH-1+l1_sel_out[i]*PKT_LEN_WIDTH -: PKT_LEN_WIDTH];
        
        assign aggr_pe_tlast[i] = |pe_tlast[N_FIFO_PER_PORT-1+i*N_FIFO_PER_PORT -: N_FIFO_PER_PORT];
        
        assign l1_en_in[i] = (l2_sel_out == i) && l2_en_out;
    end
endgenerate

// If L2_POST_DEQ_STYLE is round robin, the root pieo doesn't care about tlast, but cares about the negative edge of l1_en_out
generate
    if (L2_POST_DEQ_STYLE == POST_DEQ_DEFAULT) begin
        positive_edge_filter #(
            .WIDTH(PORT_COUNT)
        ) detect_ne_l1_en_out (
            .clk(clk),
            .rst(rst),
            .data_in(~l1_en_out),
            .pe_out(l2_pe_tlast)
        );
    end else begin
        assign l2_pe_tlast = aggr_pe_tlast;
    end
endgenerate

pieo_sched #(
    .PRE_ENQ_STYLE(L2_PRE_ENQ_STYLE),
    .POST_DEQ_STYLE(L2_POST_DEQ_STYLE),
    .PORT_COUNT(1),
    .N_FIFO_PER_PORT(PORT_COUNT)
) l2_pieo (
    .clk(clk),
    .rst(rst),
    .en_in(1'b1),
    .curr_time({2{1'b1}}),
    .fifo_tvalid(l1_pieo_valid),
    .fifo_packet_length(l2_fifo_packet_length),
    .pe_tlast(l2_pe_tlast),
    .sel_out(l2_sel_out),
    .en_out(l2_en_out)
);


// Convert per port sel_out to the actual sel_out
integer j;
reg stop;
always @(*)begin
    sel_out = 0;
    stop = 0;
    for (j=0; j < PORT_COUNT; j = j + 1) begin
        if (~stop) begin
            if (l2_sel_out != j) begin
                sel_out = sel_out + N_FIFO_PER_PORT;
            end else begin
                sel_out = sel_out + l1_sel_out[j];
                stop = 1;
            end
        end
    end
end

endmodule
