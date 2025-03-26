module top_traffic_manager #(
    // AXIS Interface config parameters
    parameter PORT_COUNT_RX= 3,
    parameter PORT_COUNT_TX = 1,

    parameter AXIS_DATA_WIDTH = 64,
    parameter AXIS_KEEP_WIDTH = AXIS_DATA_WIDTH/8,
    parameter AXIS_USER_WIDTH = 2*8,

    //////////packet_scheduling//////////
    parameter PIEO_ENABLE = 1,
    parameter SHARED_MEM_EN = 1,

    // metadata parameters
    parameter PKT_LEN_WIDTH = 2*8,

    // FIFO parameters
    parameter FIFO_DEPTH = 4096*256,
    parameter FIFO_STATUS_WIDTH = $clog2(FIFO_DEPTH)+1,
    parameter N_FIFO_PER_PORT = 3,
    parameter ARRAY_FIFO_UPSCALE = 2**2,
    parameter FIFO_SEL_WIDTH = $clog2(N_FIFO_PER_PORT),
    parameter NUM_FIFO = PORT_COUNT_RX*N_FIFO_PER_PORT,
    parameter SEL_WIDTH = $clog2(NUM_FIFO),

    // Parameter Store parameters
    parameter PARAM_SEL_WIDTH = 3,
    parameter PARAM_DATA_WIDTH = 16,

    // MRECN paramaters
    parameter MRECN_RES_ID_WIDTH = 2,
    parameter MRECN_CONG_SEV_WIDTH = 3

)
(
    input wire clk,
    input wire rst,

    // AXI Lite Control
    input wire                          axil_ps_write_enable,
    input wire [SEL_WIDTH-1:0]          axil_ps_fifo_select,
    input wire [PARAM_SEL_WIDTH-1:0]    axil_ps_param_select,
    input wire [PARAM_DATA_WIDTH-1:0]   axil_ps_wr_data,

    output wire [PORT_COUNT_RX*N_FIFO_PER_PORT-1:0]                          axil_mrecn_mrce,
    output wire [PORT_COUNT_RX*N_FIFO_PER_PORT*MRECN_RES_ID_WIDTH-1:0]       axil_mrecn_res_id,
    output wire [PORT_COUNT_RX*N_FIFO_PER_PORT*MRECN_CONG_SEV_WIDTH-1:0]     axil_mrecn_cong_sev,

    // MRECN Interface
    input wire [PORT_COUNT_RX-1:0]                        mrecn_mrce,
    input wire [PORT_COUNT_RX*MRECN_RES_ID_WIDTH-1:0]     mrecn_res_id,
    input wire [PORT_COUNT_RX*MRECN_CONG_SEV_WIDTH-1:0]   mrecn_cong_sev,
 
    // AXI Stream input
    input wire  [PORT_COUNT_RX*AXIS_DATA_WIDTH-1:0]     s_axis_traffic_manager_tdata,
    input wire  [PORT_COUNT_RX*AXIS_USER_WIDTH-1:0]     s_axis_traffic_manager_tuser,
    input wire  [PORT_COUNT_RX*AXIS_KEEP_WIDTH-1:0]     s_axis_traffic_manager_tkeep,
    input wire  [PORT_COUNT_RX-1:0]                     s_axis_traffic_manager_tvalid,
    output wire [PORT_COUNT_RX-1:0]                     s_axis_traffic_manager_tready,
    input wire  [PORT_COUNT_RX-1:0]                     s_axis_traffic_manager_tlast,
    input wire  [PORT_COUNT_RX*FIFO_SEL_WIDTH-1:0]      s_axis_traffic_manager_tdest,

    // AXI Stream output
    output wire [AXIS_DATA_WIDTH*PORT_COUNT_TX-1:0]     m_axis_traffic_manager_tdata,
    output wire [AXIS_KEEP_WIDTH*PORT_COUNT_TX-1:0]     m_axis_traffic_manager_tkeep,
    output wire [PORT_COUNT_TX-1:0]                     m_axis_traffic_manager_tvalid,
    input  wire [PORT_COUNT_TX-1:0]                     m_axis_traffic_manager_tready,
    output wire [PORT_COUNT_TX-1:0]                     m_axis_traffic_manager_tlast
);

// Demux - FIFO signals
wire [NUM_FIFO*AXIS_DATA_WIDTH-1:0]    w_axis_demux_fifo_tdata;
wire [NUM_FIFO*AXIS_USER_WIDTH-1:0]    w_axis_demux_fifo_tuser;
wire [NUM_FIFO*AXIS_KEEP_WIDTH-1:0]    w_axis_demux_fifo_tkeep;
wire [NUM_FIFO-1:0]                    w_axis_demux_fifo_tvalid;
wire [NUM_FIFO-1:0]                    w_axis_demux_fifo_tready;
wire [NUM_FIFO-1:0]                    w_axis_demux_fifo_tlast;

// FIFO output signals
wire [NUM_FIFO*AXIS_DATA_WIDTH-1:0]    w_axis_fifo_tdata;
wire [NUM_FIFO*AXIS_USER_WIDTH-1:0]    w_axis_fifo_tuser;
wire [NUM_FIFO*AXIS_KEEP_WIDTH-1:0]    w_axis_fifo_tkeep;
wire [NUM_FIFO-1:0]                    w_axis_fifo_tvalid;
wire [NUM_FIFO-1:0]                    w_axis_fifo_tready;
wire [NUM_FIFO-1:0]                    w_axis_fifo_tlast;
wire [NUM_FIFO*FIFO_STATUS_WIDTH-1:0]  w_fifo_status_depth;


genvar i,j;
generate
    if (SHARED_MEM_EN) begin : SHARED_MEM_FIFO
        for (i = 0; i < PORT_COUNT_RX; i = i + 1) begin : gen_shared_memory_fifo
            shared_mem_fifo #(
                .NUM_SLICES(N_FIFO_PER_PORT),
                .ARRAY_FIFO_UPSCALE(ARRAY_FIFO_UPSCALE),
                .AXIS_DATA_WIDTH(AXIS_DATA_WIDTH),
                .AXIS_USER_WIDTH(AXIS_USER_WIDTH),
                .AXIS_DEST_WIDTH(FIFO_SEL_WIDTH)
            ) shared_memory_fifo_inst (
                .clk(clk),
                .rst(rst),
                // input
                .s_axis_tdata(      s_axis_traffic_manager_tdata    [AXIS_DATA_WIDTH*(1+i)-1    -:  AXIS_DATA_WIDTH]  ),
                .s_axis_tuser(      s_axis_traffic_manager_tuser    [AXIS_USER_WIDTH*(1+i)-1    -:  AXIS_USER_WIDTH]  ),
                .s_axis_tkeep(      s_axis_traffic_manager_tkeep    [AXIS_KEEP_WIDTH*(1+i)-1    -:  AXIS_KEEP_WIDTH]  ),
                .s_axis_tvalid(     s_axis_traffic_manager_tvalid   [i]  ),
                .s_axis_tready(     s_axis_traffic_manager_tready   [i]  ),
                .s_axis_tlast(      s_axis_traffic_manager_tlast    [i]  ),
                .s_axis_tdest(      s_axis_traffic_manager_tdest    [FIFO_SEL_WIDTH*(1+i)-1     -:  FIFO_SEL_WIDTH]  ),
                // output
                .m_axis_tdata(      w_axis_fifo_tdata               [N_FIFO_PER_PORT*AXIS_DATA_WIDTH*(1+i)-1 -: N_FIFO_PER_PORT*AXIS_DATA_WIDTH] ),
                .m_axis_tuser(      w_axis_fifo_tuser               [N_FIFO_PER_PORT*AXIS_USER_WIDTH*(1+i)-1 -: N_FIFO_PER_PORT*AXIS_USER_WIDTH] ),
                .m_axis_tkeep(      w_axis_fifo_tkeep               [N_FIFO_PER_PORT*AXIS_KEEP_WIDTH*(1+i)-1 -: N_FIFO_PER_PORT*AXIS_KEEP_WIDTH] ),
                .m_axis_tvalid(     w_axis_fifo_tvalid              [N_FIFO_PER_PORT*(1+i)-1 -: N_FIFO_PER_PORT]   ),
                .m_axis_tready(     w_axis_fifo_tready              [N_FIFO_PER_PORT*(1+i)-1 -: N_FIFO_PER_PORT]   ),
                .m_axis_tlast(      w_axis_fifo_tlast               [N_FIFO_PER_PORT*(1+i)-1 -: N_FIFO_PER_PORT]    )
            );
        end
    end else begin : STATIC_FIFO
        for (i = 0; i < PORT_COUNT_RX; i = i + 1) begin : gen_demux
            axis_demux #(
                .M_COUNT(N_FIFO_PER_PORT),
                .DATA_WIDTH(AXIS_DATA_WIDTH),
                .S_DEST_WIDTH(FIFO_SEL_WIDTH),
                .USER_WIDTH(AXIS_USER_WIDTH),
                .DEST_ENABLE(1),
                .TDEST_ROUTE(1)
            ) port_fifo_demux (
                .clk(clk),
                .rst(rst),
                // AXI input
                .s_axis_tdata(s_axis_traffic_manager_tdata[AXIS_DATA_WIDTH+AXIS_DATA_WIDTH*i-1-:AXIS_DATA_WIDTH]),
                .s_axis_tuser(s_axis_traffic_manager_tuser[AXIS_USER_WIDTH+AXIS_USER_WIDTH*i-1-:AXIS_USER_WIDTH]),
                .s_axis_tkeep(s_axis_traffic_manager_tkeep[AXIS_KEEP_WIDTH+AXIS_KEEP_WIDTH*i-1-:AXIS_KEEP_WIDTH]),
                .s_axis_tvalid(s_axis_traffic_manager_tvalid[i]),
                .s_axis_tready(s_axis_traffic_manager_tready[i]),
                .s_axis_tlast(s_axis_traffic_manager_tlast[i]),
                .s_axis_tdest(s_axis_traffic_manager_tdest[FIFO_SEL_WIDTH+FIFO_SEL_WIDTH*i-1-:FIFO_SEL_WIDTH]),
                // AXI output
                .m_axis_tdata(w_axis_demux_fifo_tdata[(N_FIFO_PER_PORT*AXIS_DATA_WIDTH)+(N_FIFO_PER_PORT*AXIS_DATA_WIDTH)*i-1-:(N_FIFO_PER_PORT*AXIS_DATA_WIDTH)]),
                .m_axis_tuser(w_axis_demux_fifo_tuser[(N_FIFO_PER_PORT*AXIS_USER_WIDTH)+(N_FIFO_PER_PORT*AXIS_USER_WIDTH)*i-1-:(N_FIFO_PER_PORT*AXIS_USER_WIDTH)]),
                .m_axis_tkeep(w_axis_demux_fifo_tkeep[(N_FIFO_PER_PORT*AXIS_KEEP_WIDTH)+(N_FIFO_PER_PORT*AXIS_KEEP_WIDTH)*i-1-:(N_FIFO_PER_PORT*AXIS_KEEP_WIDTH)]),
                .m_axis_tvalid(w_axis_demux_fifo_tvalid[N_FIFO_PER_PORT+N_FIFO_PER_PORT*i-1-:N_FIFO_PER_PORT]),
                .m_axis_tready(w_axis_demux_fifo_tready[N_FIFO_PER_PORT+N_FIFO_PER_PORT*i-1-:N_FIFO_PER_PORT]),
                .m_axis_tlast(w_axis_demux_fifo_tlast[N_FIFO_PER_PORT+N_FIFO_PER_PORT*i-1-:N_FIFO_PER_PORT]),
                // Control
                .enable(1'b1)
            );
            
            for (j = 0; j < N_FIFO_PER_PORT; j = j + 1) begin : gen_fifo
                
                axis_fifo #(
                    .DEPTH(FIFO_DEPTH),
                    .DATA_WIDTH(AXIS_DATA_WIDTH),
                    .USER_WIDTH(AXIS_USER_WIDTH),
                    .OUTPUT_FIFO_ENABLE(1),
                    .FRAME_FIFO(0),
                    .DROP_WHEN_FULL(0)
                ) fifo_inst (
                    .clk(clk),
                    .rst(rst),
                    .s_axis_tdata(w_axis_demux_fifo_tdata[(AXIS_DATA_WIDTH+(N_FIFO_PER_PORT*i+j)*AXIS_DATA_WIDTH)-1 -: AXIS_DATA_WIDTH]),
                    .s_axis_tuser(w_axis_demux_fifo_tuser[(AXIS_USER_WIDTH+(N_FIFO_PER_PORT*i+j)*AXIS_USER_WIDTH)-1 -: AXIS_USER_WIDTH]),
                    .s_axis_tkeep(w_axis_demux_fifo_tkeep[(AXIS_KEEP_WIDTH+(N_FIFO_PER_PORT*i+j)*AXIS_KEEP_WIDTH)-1 -: AXIS_KEEP_WIDTH]),
                    .s_axis_tvalid(w_axis_demux_fifo_tvalid[(N_FIFO_PER_PORT*i+j)]),
                    .s_axis_tready(w_axis_demux_fifo_tready[(N_FIFO_PER_PORT*i+j)]),
                    .s_axis_tlast(w_axis_demux_fifo_tlast[(N_FIFO_PER_PORT*i+j)]),
                    
                    .m_axis_tdata(w_axis_fifo_tdata[(AXIS_DATA_WIDTH+(N_FIFO_PER_PORT*i+j)*AXIS_DATA_WIDTH)-1 -: AXIS_DATA_WIDTH]),
                    .m_axis_tuser(w_axis_fifo_tuser[(AXIS_USER_WIDTH+(N_FIFO_PER_PORT*i+j)*AXIS_USER_WIDTH)-1 -: AXIS_USER_WIDTH]),
                    .m_axis_tkeep(w_axis_fifo_tkeep[(AXIS_KEEP_WIDTH+(N_FIFO_PER_PORT*i+j)*AXIS_KEEP_WIDTH)-1 -: AXIS_KEEP_WIDTH]),
                    .m_axis_tvalid(w_axis_fifo_tvalid[(N_FIFO_PER_PORT*i+j)]),
                    .m_axis_tready(w_axis_fifo_tready[(N_FIFO_PER_PORT*i+j)]),
                    .m_axis_tlast(w_axis_fifo_tlast[(N_FIFO_PER_PORT*i+j)]),
                    .status_depth(w_fifo_status_depth[(FIFO_STATUS_WIDTH+(N_FIFO_PER_PORT*i+j)*FIFO_STATUS_WIDTH)-1 -: FIFO_STATUS_WIDTH]),
                    .status_overflow()          // may be useful later
                );
            end
        end
    end
endgenerate

/*
genvar i,j;
generate
    for (i = 0; i < PORT_COUNT_RX; i = i + 1) begin : gen_demux
        
        axis_demux #(
            .M_COUNT(N_FIFO_PER_PORT),
            .DATA_WIDTH(AXIS_DATA_WIDTH),
            .S_DEST_WIDTH(FIFO_SEL_WIDTH),
            .USER_WIDTH(AXIS_USER_WIDTH),
            .DEST_ENABLE(1),
            .TDEST_ROUTE(1)
        ) port_fifo_demux (
            .clk(clk),
            .rst(rst),
            // AXI input
            .s_axis_tdata(s_axis_traffic_manager_tdata[AXIS_DATA_WIDTH+AXIS_DATA_WIDTH*i-1-:AXIS_DATA_WIDTH]),
            .s_axis_tuser(s_axis_traffic_manager_tuser[AXIS_USER_WIDTH+AXIS_USER_WIDTH*i-1-:AXIS_USER_WIDTH]),
            .s_axis_tkeep(s_axis_traffic_manager_tkeep[AXIS_KEEP_WIDTH+AXIS_KEEP_WIDTH*i-1-:AXIS_KEEP_WIDTH]),
            .s_axis_tvalid(s_axis_traffic_manager_tvalid[i]),
            .s_axis_tready(s_axis_traffic_manager_tready[i]),
            .s_axis_tlast(s_axis_traffic_manager_tlast[i]),
            .s_axis_tdest(s_axis_traffic_manager_tdest[FIFO_SEL_WIDTH+FIFO_SEL_WIDTH*i-1-:FIFO_SEL_WIDTH]),
            // AXI output
            .m_axis_tdata(w_axis_demux_fifo_tdata[(N_FIFO_PER_PORT*AXIS_DATA_WIDTH)+(N_FIFO_PER_PORT*AXIS_DATA_WIDTH)*i-1-:(N_FIFO_PER_PORT*AXIS_DATA_WIDTH)]),
            .m_axis_tuser(w_axis_demux_fifo_tuser[(N_FIFO_PER_PORT*AXIS_USER_WIDTH)+(N_FIFO_PER_PORT*AXIS_USER_WIDTH)*i-1-:(N_FIFO_PER_PORT*AXIS_USER_WIDTH)]),
            .m_axis_tkeep(w_axis_demux_fifo_tkeep[(N_FIFO_PER_PORT*AXIS_KEEP_WIDTH)+(N_FIFO_PER_PORT*AXIS_KEEP_WIDTH)*i-1-:(N_FIFO_PER_PORT*AXIS_KEEP_WIDTH)]),
            .m_axis_tvalid(w_axis_demux_fifo_tvalid[N_FIFO_PER_PORT+N_FIFO_PER_PORT*i-1-:N_FIFO_PER_PORT]),
            .m_axis_tready(w_axis_demux_fifo_tready[N_FIFO_PER_PORT+N_FIFO_PER_PORT*i-1-:N_FIFO_PER_PORT]),
            .m_axis_tlast(w_axis_demux_fifo_tlast[N_FIFO_PER_PORT+N_FIFO_PER_PORT*i-1-:N_FIFO_PER_PORT]),
            // Control
            .enable(1'b1)
        );
        
        for (j = 0; j < N_FIFO_PER_PORT; j = j + 1) begin : gen_fifo
            
            axis_fifo #(
                .DEPTH(FIFO_DEPTH),
                .DATA_WIDTH(AXIS_DATA_WIDTH),
                .USER_WIDTH(AXIS_USER_WIDTH),
                .OUTPUT_FIFO_ENABLE(1),
                .FRAME_FIFO(0),
                .DROP_WHEN_FULL(0)
            ) fifo_inst (
                .clk(clk),
                .rst(rst),
                .s_axis_tdata(w_axis_demux_fifo_tdata[(AXIS_DATA_WIDTH+(N_FIFO_PER_PORT*i+j)*AXIS_DATA_WIDTH)-1 -: AXIS_DATA_WIDTH]),
                .s_axis_tuser(w_axis_demux_fifo_tuser[(AXIS_USER_WIDTH+(N_FIFO_PER_PORT*i+j)*AXIS_USER_WIDTH)-1 -: AXIS_USER_WIDTH]),
                .s_axis_tkeep(w_axis_demux_fifo_tkeep[(AXIS_KEEP_WIDTH+(N_FIFO_PER_PORT*i+j)*AXIS_KEEP_WIDTH)-1 -: AXIS_KEEP_WIDTH]),
                .s_axis_tvalid(w_axis_demux_fifo_tvalid[(N_FIFO_PER_PORT*i+j)]),
                .s_axis_tready(w_axis_demux_fifo_tready[(N_FIFO_PER_PORT*i+j)]),
                .s_axis_tlast(w_axis_demux_fifo_tlast[(N_FIFO_PER_PORT*i+j)]),
                
                .m_axis_tdata(w_axis_fifo_tdata[(AXIS_DATA_WIDTH+(N_FIFO_PER_PORT*i+j)*AXIS_DATA_WIDTH)-1 -: AXIS_DATA_WIDTH]),
                .m_axis_tuser(w_axis_fifo_tuser[(AXIS_USER_WIDTH+(N_FIFO_PER_PORT*i+j)*AXIS_USER_WIDTH)-1 -: AXIS_USER_WIDTH]),
                .m_axis_tkeep(w_axis_fifo_tkeep[(AXIS_KEEP_WIDTH+(N_FIFO_PER_PORT*i+j)*AXIS_KEEP_WIDTH)-1 -: AXIS_KEEP_WIDTH]),
                .m_axis_tvalid(w_axis_fifo_tvalid[(N_FIFO_PER_PORT*i+j)]),
                .m_axis_tready(w_axis_fifo_tready[(N_FIFO_PER_PORT*i+j)]),
                .m_axis_tlast(w_axis_fifo_tlast[(N_FIFO_PER_PORT*i+j)]),
                .status_depth(w_fifo_status_depth[(FIFO_STATUS_WIDTH+(N_FIFO_PER_PORT*i+j)*FIFO_STATUS_WIDTH)-1 -: FIFO_STATUS_WIDTH]),
                .status_overflow()          // may be useful later
            );
        end
    end
endgenerate
*/

// Mux
wire                   w_mux_en;
wire [SEL_WIDTH - 1:0] w_mux_select;

axis_mux  #(
    // Number of AXI stream inputs
    .S_COUNT(NUM_FIFO),
    // Width of AXI stream interfaces in bits
    .DATA_WIDTH(AXIS_DATA_WIDTH),
    .USER_ENABLE(0)
) axis_mux_inst(
    .clk(clk),
    .rst(rst),
    .s_axis_tdata(w_axis_fifo_tdata),
    .s_axis_tkeep(w_axis_fifo_tkeep),
    .s_axis_tvalid(w_axis_fifo_tvalid),
    .s_axis_tready(w_axis_fifo_tready),
    .s_axis_tlast(w_axis_fifo_tlast),
    
    .m_axis_tdata(m_axis_traffic_manager_tdata),
    .m_axis_tkeep(m_axis_traffic_manager_tkeep),
    .m_axis_tvalid(m_axis_traffic_manager_tvalid),
    .m_axis_tready(m_axis_traffic_manager_tready),
    .m_axis_tlast(m_axis_traffic_manager_tlast),
    .enable(w_mux_en), 
    .select(w_mux_select)
);

// Scheduling Parameter Store
localparam TOKEN_BUCKET_SCALE = 6;

wire [NUM_FIFO*SEL_WIDTH-1:0]        ps_fifo_priority_out;
wire [NUM_FIFO-1:0]                  ps_fifo_enable_shaping_out;
wire [NUM_FIFO*PKT_LEN_WIDTH-1:0]    ps_fifo_max_rate_out;
wire [NUM_FIFO*PKT_LEN_WIDTH-1:0]    ps_fifo_drr_quantum_out;
wire [NUM_FIFO*PKT_LEN_WIDTH-1:0]    ps_fifo_starvation_timeout_out;

parameter_store #(
    .PORT_COUNT_RX(PORT_COUNT_RX),
    .N_FIFO_PER_PORT(N_FIFO_PER_PORT),
    // AXIL interface params
    .PARAM_SEL_WIDTH(PARAM_SEL_WIDTH),
    .PARAM_DATA_WIDTH(PARAM_DATA_WIDTH),
    // MRECN params
    .MRECN_RES_ID_WIDTH(MRECN_RES_ID_WIDTH),
    .MRECN_CONG_SEV_WIDTH(MRECN_CONG_SEV_WIDTH)
) parameter_store_inst(
    .clk(clk),
    .rst(rst),
    // AXI Lite Control
    .axil_ps_write_enable(axil_ps_write_enable),
    .axil_ps_fifo_select(axil_ps_fifo_select),
    .axil_ps_param_select(axil_ps_param_select),
    .axil_ps_wr_data(axil_ps_wr_data),
    .axil_mrecn_mrce(axil_mrecn_mrce),
    .axil_mrecn_res_id(axil_mrecn_res_id),
    .axil_mrecn_cong_sev(axil_mrecn_cong_sev),
    // MRECN Interface
    .mrecn_mrce(mrecn_mrce),
    .mrecn_res_id(mrecn_res_id),
    .mrecn_cong_sev(mrecn_cong_sev),
    .mrecn_fifo_select(s_axis_traffic_manager_tdest),
    // PS Output
    .ps_fifo_priority_out(ps_fifo_priority_out),
    .ps_fifo_enable_shaping_out(ps_fifo_enable_shaping_out),
    .ps_fifo_max_rate_out(ps_fifo_max_rate_out),
    .ps_fifo_drr_quantum_out(ps_fifo_drr_quantum_out),
    .ps_fifo_starvation_timeout_out(ps_fifo_starvation_timeout_out)
);

// Traffic Manager
generate
    if (PIEO_ENABLE == 0) begin : DUMB_SCHEDULER
        
        prio_sched #(
            .NUM_FIFO(NUM_FIFO)
        )
        fifo_sched_inst
        (
            .clk(clk),
            .rst(rst),
            .fifo_tvalid(w_axis_fifo_tvalid),
            .fifo_tlast(w_axis_fifo_tlast),
            .sel_out(w_mux_select),
            .en_out(w_mux_en)
        );
        
    end else if (PIEO_ENABLE == 1) begin : PIEO_SCHEDULER
        // DETECT END OF PACKET
        wire [NUM_FIFO-1:0] pe_tlast;
        
        positive_edge_filter #(
            .WIDTH(NUM_FIFO)
        ) detect_pe_tlast (
            .clk(clk),
            .rst(rst),
            .data_in(w_axis_fifo_tlast),
            .pe_out(pe_tlast)
        );
        
        /*
        // WALL CLOCK
        localparam TIME_LOG = 32;
        wire [TIME_LOG-1:0]  curr_time;
        wall_clock #(
            .TIME_LOG(TIME_LOG)
        ) wall_clock_inst (
            .clk(clk),
            .rst(rst),
            .curr_time(curr_time)
        );*/

        pieo_sched #(
            .PORT_COUNT(PORT_COUNT_RX),
            .N_FIFO_PER_PORT(N_FIFO_PER_PORT),
            .FIFO_STATUS_WIDTH(FIFO_STATUS_WIDTH),
            .TB_SCALE(TOKEN_BUCKET_SCALE),
            .TIME_LOG(2)
        )
        fifo_sched_inst
        (
            .clk(clk),
            .rst(rst),
            .curr_time({2{1'b1}}),
            // from fifos
            .fifo_tvalid(w_axis_fifo_tvalid),
            .fifo_packet_length(w_axis_fifo_tuser),
            .fifo_status_depth(w_fifo_status_depth),
            .pe_tlast(pe_tlast),
            // from parameter store
            .fifo_priority(ps_fifo_priority_out),
            .fifo_enable_shaping(ps_fifo_enable_shaping_out),
            .fifo_max_rate(ps_fifo_max_rate_out),
            .fifo_drr_quantum(ps_fifo_drr_quantum_out),
            .fifo_starvation_timeout(ps_fifo_starvation_timeout_out),
            // to mux
            .sel_out(w_mux_select),
            .en_out(w_mux_en)
        );
    end
endgenerate

endmodule
