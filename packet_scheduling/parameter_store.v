module format_signal #(
    parameter COMPONENTS_COUNT= 3,
    parameter COMPONENTS_WIDTH= 3,
    parameter OUTPUT_WIDTH = $clog2(COMPONENTS_COUNT*COMPONENTS_WIDTH)
)(
    input  wire [COMPONENTS_COUNT*COMPONENTS_WIDTH-1:0]     signal_in,
    output reg  [COMPONENTS_COUNT*OUTPUT_WIDTH-1:0]         signal_out
);

localparam ELEM_PER_COMPONENT = 2**COMPONENTS_WIDTH;

reg [OUTPUT_WIDTH-1:0] signal_tmp [COMPONENTS_COUNT-1:0];

integer i;
always @(*) begin
    for (i = 0; i < COMPONENTS_COUNT; i = i + 1) begin
        signal_tmp[i] = signal_in[COMPONENTS_WIDTH*(1+i)-1 -: COMPONENTS_WIDTH] + i*ELEM_PER_COMPONENT;
        signal_out[OUTPUT_WIDTH*(1+i)-1 -: OUTPUT_WIDTH] = signal_tmp[i];
    end
end

endmodule

module parameter_store #(
    // Structural parameters
    parameter PORT_COUNT_RX= 3,
    parameter N_FIFO_PER_PORT = 2**2,
    parameter FIFO_SEL_WIDTH = $clog2(N_FIFO_PER_PORT),
    // Parameter Store params
    parameter NUM_FIFO = PORT_COUNT_RX*N_FIFO_PER_PORT,
    parameter SEL_WIDTH = $clog2(NUM_FIFO),
    parameter PKT_LEN_WIDTH = 16,

    // AXIL interface params
    parameter PARAM_SEL_WIDTH = 3,
    parameter PARAM_DATA_WIDTH = 16,

    // MRECN params
    parameter MRECN_RES_ID_WIDTH = 2,
    parameter MRECN_CONG_SEV_WIDTH = 3
)(
    input wire clk,
    input wire rst,

    // AXI Lite Control
    input wire                                          axil_ps_write_enable,
    input wire [SEL_WIDTH-1:0]                          axil_ps_fifo_select,
    input wire [PARAM_SEL_WIDTH-1:0]                    axil_ps_param_select,
    input wire [PARAM_DATA_WIDTH-1:0]                   axil_ps_wr_data,
    
    output wire [NUM_FIFO-1:0]                          axil_mrecn_mrce,
    output wire [NUM_FIFO*MRECN_RES_ID_WIDTH-1:0]       axil_mrecn_res_id,
    output wire [NUM_FIFO*MRECN_CONG_SEV_WIDTH-1:0]     axil_mrecn_cong_sev,

    // MRECN Interface
    input wire [PORT_COUNT_RX-1:0]                        mrecn_mrce,
    input wire [PORT_COUNT_RX*MRECN_RES_ID_WIDTH-1:0]     mrecn_res_id,
    input wire [PORT_COUNT_RX*MRECN_CONG_SEV_WIDTH-1:0]   mrecn_cong_sev,
    input wire [PORT_COUNT_RX*FIFO_SEL_WIDTH-1:0]         mrecn_fifo_select,

    // PS Output
    output wire [NUM_FIFO*SEL_WIDTH-1:0]        ps_fifo_priority_out,
    output wire [NUM_FIFO-1:0]                  ps_fifo_enable_shaping_out,
    output wire [NUM_FIFO*PKT_LEN_WIDTH-1:0]    ps_fifo_max_rate_out,
    output wire [NUM_FIFO*PKT_LEN_WIDTH-1:0]    ps_fifo_drr_quantum_out,
    output wire [NUM_FIFO*PKT_LEN_WIDTH-1:0]    ps_fifo_starvation_timeout_out
);

// Mux
assign ps_fifo_priority_out             = ps_fifo_priority_r;
assign ps_fifo_drr_quantum_out          = ps_fifo_drr_quantum_r;
assign ps_fifo_starvation_timeout_out   = ps_fifo_starvation_timeout_r;

// assign ps_fifo_enable_shaping_out       = ps_fifo_enable_shaping_r;
// assign ps_fifo_max_rate_out             = ps_fifo_max_rate_r;

genvar j;
generate
    for (j = 0; j < NUM_FIFO; j = j + 1) begin : gen_mux
        assign ps_fifo_enable_shaping_out[j]                                  = mrecn_mrce_r[j] ? 1'b1 : ps_fifo_enable_shaping_r[j];
        assign ps_fifo_max_rate_out[PKT_LEN_WIDTH*(1+j)-1 -: PKT_LEN_WIDTH]   = mrecn_mrce_r[j] ? 
                                                                             (ps_fifo_max_rate_r[PKT_LEN_WIDTH*(1+j)-1-:PKT_LEN_WIDTH] >> mrecn_cong_sev_r[MRECN_CONG_SEV_WIDTH*(1+j)-1-:MRECN_CONG_SEV_WIDTH]) : 
                                                                              ps_fifo_max_rate_r[PKT_LEN_WIDTH*(1+j)-1-:PKT_LEN_WIDTH];
    end
endgenerate

// Parameter Store Registers
localparam [SEL_WIDTH-1:0]          default_priority = 1;                   // actual_bit_rate = fifo_max_rate * 8 * 2**-TB_SCALE / 4e-9
localparam [PKT_LEN_WIDTH-1:0]      default_max_rate = 1;                   //  --> actual_bit_rate = ~30 Mbps if TOKEN_BUCKET_SCALE = 6
localparam [PKT_LEN_WIDTH-1:0]      default_starvation_timeout = 1000;
localparam [PKT_LEN_WIDTH-1:0]      default_quantum = 500;

reg [NUM_FIFO*SEL_WIDTH-1:0]        ps_fifo_priority_r,                 ps_fifo_priority_next_r;
reg [NUM_FIFO-1:0]                  ps_fifo_enable_shaping_r,           ps_fifo_enable_shaping_next_r;
reg [NUM_FIFO*PKT_LEN_WIDTH-1:0]    ps_fifo_max_rate_r,                 ps_fifo_max_rate_next_r;
reg [NUM_FIFO*PKT_LEN_WIDTH-1:0]    ps_fifo_drr_quantum_r,              ps_fifo_drr_quantum_next_r;
reg [NUM_FIFO*PKT_LEN_WIDTH-1:0]    ps_fifo_starvation_timeout_r,       ps_fifo_starvation_timeout_next_r;

always @(posedge clk) begin
    if (rst) begin
        ps_fifo_priority_r              <= {NUM_FIFO{default_priority}};
        ps_fifo_enable_shaping_r        <= {NUM_FIFO{1'b0}};
        ps_fifo_max_rate_r              <= {NUM_FIFO{default_max_rate}};
        ps_fifo_drr_quantum_r           <= {NUM_FIFO{default_quantum}};
        ps_fifo_starvation_timeout_r    <= {NUM_FIFO{default_starvation_timeout}};
    end else begin
        ps_fifo_priority_r              <= ps_fifo_priority_next_r;
        ps_fifo_enable_shaping_r        <= ps_fifo_enable_shaping_next_r;
        ps_fifo_max_rate_r              <= ps_fifo_max_rate_next_r;
        ps_fifo_drr_quantum_r           <= ps_fifo_drr_quantum_next_r;
        ps_fifo_starvation_timeout_r    <= ps_fifo_starvation_timeout_next_r;
    end
end


// AXIL Control Logic
always @(*)begin
    ps_fifo_priority_next_r             = ps_fifo_priority_r;
    ps_fifo_enable_shaping_next_r       = ps_fifo_enable_shaping_r;
    ps_fifo_max_rate_next_r             = ps_fifo_max_rate_r;
    ps_fifo_drr_quantum_next_r          = ps_fifo_drr_quantum_r;
    ps_fifo_starvation_timeout_next_r   = ps_fifo_starvation_timeout_r;

    if (axil_ps_write_enable) begin
        case(axil_ps_param_select)
            0 : ps_fifo_priority_next_r             [axil_ps_fifo_select*SEL_WIDTH     +: SEL_WIDTH]        = axil_ps_wr_data;
            1 : ps_fifo_enable_shaping_next_r       [axil_ps_fifo_select]                                   = axil_ps_wr_data;
            2 : ps_fifo_max_rate_next_r             [axil_ps_fifo_select*PKT_LEN_WIDTH +: PKT_LEN_WIDTH]    = axil_ps_wr_data;
            3 : ps_fifo_drr_quantum_next_r          [axil_ps_fifo_select*PKT_LEN_WIDTH +: PKT_LEN_WIDTH]    = axil_ps_wr_data;
            4 : ps_fifo_starvation_timeout_next_r   [axil_ps_fifo_select*PKT_LEN_WIDTH +: PKT_LEN_WIDTH]    = axil_ps_wr_data;
        endcase
    end
end

// Format mrecn_fifo_select
wire [PORT_COUNT_RX*SEL_WIDTH-1:0]    mrecn_fifo_select_form;

format_signal #(
    .COMPONENTS_COUNT(PORT_COUNT_RX),
    .COMPONENTS_WIDTH(FIFO_SEL_WIDTH),
    .OUTPUT_WIDTH(SEL_WIDTH)
) format_signal_inst (
    .signal_in(mrecn_fifo_select),
    .signal_out(mrecn_fifo_select_form)
);

// MRECN Registers
reg [NUM_FIFO-1:0]                          mrecn_mrce_r,       mrecn_mrce_next_r;
reg [NUM_FIFO*MRECN_RES_ID_WIDTH-1:0]       mrecn_res_id_r,     mrecn_res_id_next_r;
reg [NUM_FIFO*MRECN_CONG_SEV_WIDTH-1:0]     mrecn_cong_sev_r,   mrecn_cong_sev_next_r;

always @(posedge clk) begin
    if (rst) begin
        mrecn_mrce_r            <= 0;
        mrecn_res_id_r          <= 0;
        mrecn_cong_sev_r        <= 0;
    end else begin
        mrecn_mrce_r            <= mrecn_mrce_next_r;
        mrecn_res_id_r          <= mrecn_res_id_next_r;
        mrecn_cong_sev_r        <= mrecn_cong_sev_next_r;
    end
end

// MRECN Control Logic
reg [SEL_WIDTH-1:0] mrecn_fifo_select_tmp;
integer i;
always @(*) begin
    // default
    mrecn_mrce_next_r = mrecn_mrce_r;
    mrecn_res_id_next_r = mrecn_res_id_r;
    mrecn_cong_sev_next_r = mrecn_cong_sev_r;

    // If MRECN interface is activated, update MRECN registers accordingly
    for (i = 0; i < PORT_COUNT_RX; i = i + 1) begin
        mrecn_fifo_select_tmp = mrecn_fifo_select_form[SEL_WIDTH*(1+i)-1 -: SEL_WIDTH];
        if (mrecn_mrce[i]) begin
            mrecn_mrce_next_r[mrecn_fifo_select_tmp] = 1'b1;
            mrecn_res_id_next_r[MRECN_RES_ID_WIDTH*(1+mrecn_fifo_select_tmp)-1 -: MRECN_RES_ID_WIDTH] = mrecn_res_id[MRECN_RES_ID_WIDTH*(1+i)-1 -: MRECN_RES_ID_WIDTH];
            mrecn_cong_sev_next_r[MRECN_CONG_SEV_WIDTH*(1+mrecn_fifo_select_tmp)-1 -: MRECN_CONG_SEV_WIDTH] = mrecn_cong_sev[MRECN_CONG_SEV_WIDTH*(1+i)-1 -: MRECN_CONG_SEV_WIDTH];
        end
    end

    // If a FIFO is configured through the AXI-Lite interface, reset the corresponding MRECN registers
    if (axil_ps_write_enable) begin
        mrecn_mrce_next_r[axil_ps_fifo_select] = 1'b0;
        mrecn_res_id_next_r[MRECN_RES_ID_WIDTH*(1+axil_ps_fifo_select)-1 -: MRECN_RES_ID_WIDTH] = 0;
        mrecn_cong_sev_next_r[MRECN_CONG_SEV_WIDTH*(1+axil_ps_fifo_select)-1 -: MRECN_CONG_SEV_WIDTH] = 0;
    end
end

assign axil_mrecn_mrce = mrecn_mrce_r;
assign axil_mrecn_res_id = mrecn_res_id_r;
assign axil_mrecn_cong_sev = mrecn_cong_sev_r;

endmodule