module shared_mem_fifo#(
    // structural parameters
    parameter NUM_SLICES = 4,

    parameter AXIS_DATA_WIDTH = 128,
    parameter AXIS_USER_WIDTH = 2*8,
    parameter AXIS_KEEP_WIDTH = AXIS_DATA_WIDTH/8,
    parameter AXIS_DEST_WIDTH = $clog2(NUM_SLICES),

    /*
    The RAMB36E2 allows access to the block RAM memory in the 36 Kb configuration. 
    This element can be configured and used as a 1-bit wide by 32K deep to an 36-bit 
    wide by 1024-bit deep true dual port RAM. This element can also be configured as 
    a 72-bit wide by 512 deep simple dual port RAM.

    We need to store words of 163 bits = 128 tdata + 16 tuser + 128/8 tkeep + 2 tdest + 1 tlast
    --> we must use 3 RAMB36E2 in 72-bit mode
    --> we have 163*512 = 83456 bits of memory (10432 bytes), of which 128*512 = 65536 bits (8192 bytes) just for tdata
    --> FIFO_DEPTH should be 8192 (2**13) to use all the available memory
    */

    // FIFO parameters
    parameter ARRAY_FIFO_UPSCALE  = 2,
    parameter ARRAY_FIFO_SIZE = NUM_SLICES * ARRAY_FIFO_UPSCALE,
    parameter ARRAY_ADDRESS_WIDTH = $clog2(ARRAY_FIFO_SIZE),
    parameter FIFO_DEPTH = 2**13 - 1
)
(
    input                                                clk, rst,
    
    // input
    input  wire  [AXIS_DATA_WIDTH-1:0]        s_axis_tdata,
    input  wire  [AXIS_USER_WIDTH-1:0]        s_axis_tuser,
    input  wire  [AXIS_KEEP_WIDTH-1:0]        s_axis_tkeep,
    input  wire                               s_axis_tvalid,
    output wire                               s_axis_tready,
    input  wire                               s_axis_tlast,
    input  wire  [AXIS_DEST_WIDTH-1:0]        s_axis_tdest,

    // per-slice output
    output wire [NUM_SLICES*AXIS_DATA_WIDTH-1:0]           m_axis_tdata,
    output wire [NUM_SLICES*AXIS_USER_WIDTH-1:0]           m_axis_tuser,
    output wire [NUM_SLICES*AXIS_KEEP_WIDTH-1:0]           m_axis_tkeep,
    output wire [NUM_SLICES-1:0]                           m_axis_tvalid,
    input  wire [NUM_SLICES-1:0]                           m_axis_tready,
    output wire [NUM_SLICES-1:0]                           m_axis_tlast
    //output wire [NUM_SLICES*$clog2(FIFO_DEPTH)-1:0]         m_fifo_status_depth
);

//// DEMUX ////
reg                                 array_fifo_demux_en, array_fifo_demux_drop;
reg [ARRAY_ADDRESS_WIDTH-1:0]       array_fifo_demux_select;

axis_demux #(
    .M_COUNT(ARRAY_FIFO_SIZE),
    .DATA_WIDTH(AXIS_DATA_WIDTH),
    //.S_DEST_WIDTH(FIFO_SEL_WIDTH),
    .USER_WIDTH(AXIS_USER_WIDTH)
) array_fifo_demux (
    .clk(clk),
    .rst(rst),
    // AXI input
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tuser(s_axis_tuser),
    .s_axis_tkeep(s_axis_tkeep),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .s_axis_tlast(s_axis_tlast),
    // AXI output
    .m_axis_tdata(fifo_in_axis_tdata),
    .m_axis_tuser(fifo_in_axis_tuser),
    .m_axis_tkeep(fifo_in_axis_tkeep),
    .m_axis_tvalid(fifo_in_axis_tvalid),
    .m_axis_tready(fifo_in_axis_tready),
    .m_axis_tlast(fifo_in_axis_tlast),
    // Control
    .enable(1'b1),  // array_fifo_demux_en
    .drop(array_fifo_demux_drop),
    .select(array_fifo_demux_select)
);

//// FIFO Array ////

wire [ARRAY_FIFO_SIZE*AXIS_DATA_WIDTH-1:0]    fifo_in_axis_tdata;
wire [ARRAY_FIFO_SIZE*AXIS_USER_WIDTH-1:0]    fifo_in_axis_tuser;
wire [ARRAY_FIFO_SIZE*AXIS_KEEP_WIDTH-1:0]    fifo_in_axis_tkeep;
wire [ARRAY_FIFO_SIZE-1:0]                    fifo_in_axis_tvalid;
wire [ARRAY_FIFO_SIZE-1:0]                    fifo_in_axis_tready;
wire [ARRAY_FIFO_SIZE-1:0]                    fifo_in_axis_tlast;

wire [ARRAY_FIFO_SIZE*AXIS_DATA_WIDTH-1:0]    fifo_out_axis_tdata;
wire [ARRAY_FIFO_SIZE*AXIS_USER_WIDTH-1:0]    fifo_out_axis_tuser;
wire [ARRAY_FIFO_SIZE*AXIS_KEEP_WIDTH-1:0]    fifo_out_axis_tkeep;
wire [ARRAY_FIFO_SIZE-1:0]                    fifo_out_axis_tvalid;
wire [ARRAY_FIFO_SIZE-1:0]                    fifo_out_axis_tready;
wire [ARRAY_FIFO_SIZE-1:0]                    fifo_out_axis_tlast;

wire [$clog2(FIFO_DEPTH):0]                   fifo_status_depth [ARRAY_FIFO_SIZE-1 : 0];

genvar i,ii;
generate
    for (i = 0; i < ARRAY_FIFO_SIZE; i = i + 1) begin : gen_fifo
        axis_fifo #(
            .DEPTH(FIFO_DEPTH),
            .DATA_WIDTH(AXIS_DATA_WIDTH),
            .USER_WIDTH(AXIS_USER_WIDTH),
            .OUTPUT_FIFO_ENABLE(1),
            .FRAME_FIFO(1),
            .DROP_WHEN_FULL(0)
        ) fifo_inst (
            .clk(clk),
            .rst(rst),

            .s_axis_tdata (  fifo_in_axis_tdata   [AXIS_DATA_WIDTH*(1+i)-1    -: AXIS_DATA_WIDTH]),
            .s_axis_tuser (  fifo_in_axis_tuser   [AXIS_USER_WIDTH*(1+i)-1    -: AXIS_USER_WIDTH]),
            .s_axis_tkeep (  fifo_in_axis_tkeep   [AXIS_KEEP_WIDTH*(1+i)-1    -: AXIS_KEEP_WIDTH]),
            .s_axis_tvalid(  fifo_in_axis_tvalid  [i]),
            .s_axis_tready(  fifo_in_axis_tready  [i]),
            .s_axis_tlast (  fifo_in_axis_tlast   [i]),

            .m_axis_tdata (  fifo_out_axis_tdata  [AXIS_DATA_WIDTH*(1+i)-1    -: AXIS_DATA_WIDTH]),
            .m_axis_tuser (  fifo_out_axis_tuser  [AXIS_USER_WIDTH*(1+i)-1    -: AXIS_USER_WIDTH]),
            .m_axis_tkeep (  fifo_out_axis_tkeep  [AXIS_KEEP_WIDTH*(1+i)-1    -: AXIS_KEEP_WIDTH]),
            .m_axis_tvalid(  fifo_out_axis_tvalid [i]),
            .m_axis_tready(  fifo_out_axis_tready [i]),
            .m_axis_tlast (  fifo_out_axis_tlast  [i]),

            .status_depth(   fifo_status_depth    [i]),
            .status_overflow()
        );
    end
endgenerate


//// per-slice MUX ////
reg  [ARRAY_ADDRESS_WIDTH-1:0]              per_slice_mux_select    [NUM_SLICES-1:0];
reg  [NUM_SLICES-1:0]                       per_slice_mux_en;

wire [NUM_SLICES*ARRAY_FIFO_SIZE-1:0]       s_axis_mux_tready;

generate
    for (i = 0; i < NUM_SLICES; i = i + 1) begin : gen_mux
        axis_mux  #(
            // Number of AXI stream inputs
            .S_COUNT(ARRAY_FIFO_SIZE),
            // Width of AXI stream interfaces in bits
            .DATA_WIDTH(AXIS_DATA_WIDTH),
            .USER_WIDTH(AXIS_USER_WIDTH),
            .USER_ENABLE(1)
        ) per_slice_mux (
            .clk(clk),
            .rst(rst),
            .s_axis_tdata(fifo_out_axis_tdata),
            .s_axis_tuser(fifo_out_axis_tuser),
            .s_axis_tkeep(fifo_out_axis_tkeep),
            .s_axis_tvalid(fifo_out_axis_tvalid),
            .s_axis_tready( s_axis_mux_tready   [ARRAY_FIFO_SIZE*(1+i)-1   -:  ARRAY_FIFO_SIZE]),
            .s_axis_tlast(fifo_out_axis_tlast),

            .m_axis_tdata (  m_axis_tdata  [AXIS_DATA_WIDTH*(1+i)-1    -: AXIS_DATA_WIDTH]),
            .m_axis_tuser (  m_axis_tuser  [AXIS_USER_WIDTH*(1+i)-1    -: AXIS_USER_WIDTH]),
            .m_axis_tkeep (  m_axis_tkeep  [AXIS_KEEP_WIDTH*(1+i)-1    -: AXIS_KEEP_WIDTH]),
            .m_axis_tvalid(  m_axis_tvalid [i]),
            .m_axis_tready(  m_axis_tready [i]),
            .m_axis_tlast(   m_axis_tlast  [i]),

            .enable(per_slice_mux_en[i]), 
            .select(per_slice_mux_select[i])
        );
    end
endgenerate

// Assign or of s_axis_mux_tready bits with the same index to fifo_out_axis_tready
generate
    for (i = 0; i < ARRAY_FIFO_SIZE; i = i + 1) begin : gen_or_reduction
        wire [NUM_SLICES-1:0] tready_bits;

        // Extract corresponding bits from s_axis_mux_tready
        for (ii = 0; ii < NUM_SLICES; ii = ii + 1) begin : GEN_EXTRACT_BITS
            assign tready_bits[ii] = s_axis_mux_tready[ii * ARRAY_FIFO_SIZE + i];
        end

        // OR-reduction across NUM_SLICES
        assign fifo_out_axis_tready[i] = |tready_bits;
    end
endgenerate

//// per-slice FIFO list (FIFO of FIFOs) ////
reg  [NUM_SLICES-1:0]               fifo_list_wr_en;
reg  [NUM_SLICES-1:0]               fifo_list_rd_en;
reg  [ARRAY_ADDRESS_WIDTH-1:0]      fifo_list_in_element      [NUM_SLICES-1:0];
wire [ARRAY_ADDRESS_WIDTH-1:0]      fifo_list_out_element     [NUM_SLICES-1:0];
wire [NUM_SLICES-1:0]               fifo_list_full;
wire [NUM_SLICES-1:0]               fifo_list_empty;

generate 
    for (i = 0; i < NUM_SLICES; i = i + 1) begin : gen_fifo_list
        simple_fifo #(
            .DATA_WIDTH(ARRAY_ADDRESS_WIDTH),
            .DEPTH(ARRAY_FIFO_SIZE)
        ) per_slice_fifo_list (
            .clk(clk),
            .rst(rst),
            .wr_en(fifo_list_wr_en[i]),
            .rd_en(fifo_list_rd_en[i]),
            .data_in(fifo_list_in_element[i]),
            .data_out(fifo_list_out_element[i]),
            .full(fifo_list_full[i]),
            .empty(fifo_list_empty[i])
        );
    end
endgenerate

// priority encoder to find upcoming empty list
wire [AXIS_DEST_WIDTH-1:0]   upcoming_empty_list;
wire upcoming_empty_list_valid;

priority_encoder_tree #(
    .WIDTH(NUM_SLICES),
    .EN_REVERSE(1)
) upcoming_empty_list_encoder (
    .input_unencoded(fifo_list_empty),
    .output_valid(upcoming_empty_list_valid),
    .output_encoded(upcoming_empty_list)
);


// priority encoder to find upcoming available fifo
wire [ARRAY_ADDRESS_WIDTH-1:0]   upcoming_available_fifo;
wire upcoming_available_fifo_valid;

priority_encoder_tree #(
    .WIDTH(ARRAY_FIFO_SIZE),
    .EN_REVERSE(1)
) upcoming_available_fifo_encoder (
    .input_unencoded(fifo_available_reg),
    .output_valid(upcoming_available_fifo_valid),
    .output_encoded(upcoming_available_fifo)
);

integer j;

//// Track available FIFOs ////
reg  [ARRAY_FIFO_SIZE-1:0]      fifo_available_reg, fifo_mark_available, fifo_mark_unavailable;
reg  [NUM_SLICES-1:0]           fifo_mark_available_trigger;

always @(posedge clk) begin
    if (rst) begin
        fifo_available_reg  <= {ARRAY_FIFO_SIZE{1'b1}};
    end else begin
        fifo_available_reg  <= (~fifo_available_reg     &   fifo_mark_available)      | 
                               (fifo_mark_available     &   ~fifo_mark_unavailable)   |
                               (fifo_available_reg      &   ~fifo_mark_unavailable);
    end
end

// handle fifo_mark_available triggers
always @(*) begin
    fifo_mark_available = 0;
    for (j = 0; j < NUM_SLICES; j = j + 1) begin
        if (fifo_mark_available_trigger[j]) begin
            fifo_mark_available[per_slice_mux_select[j]]  = 1'b1;
        end
    end
end

//// input-side FSM ////

// States
localparam IN_IDLE      = 0;
localparam IN_TRANSMIT  = 1;
localparam IN_DROP      = 2;

// Signals
reg  [1:0]                      in_state, in_state_next;

reg  [ARRAY_ADDRESS_WIDTH-1:0]  fifo_ptr_reg                    [NUM_SLICES-1:0];
reg  [ARRAY_ADDRESS_WIDTH-1:0]  fifo_ptr_reg_next               [NUM_SLICES-1:0];

// register update
always @(posedge clk) begin
    if (rst) begin
        in_state <= IN_IDLE;
    end else begin
        in_state <= in_state_next;
    end
end

generate
    for (i = 0; i < NUM_SLICES; i = i + 1) begin : per_slice_fifo_ptr
        always @(posedge clk) begin
            if (rst) begin
                fifo_ptr_reg[i]   <= i;
            end else begin
                fifo_ptr_reg[i]   <= fifo_ptr_reg_next[i];
            end
        end
    end
endgenerate

// FSM
always @(*) begin
    // default
    in_state_next = in_state;
    fifo_mark_unavailable  = 0;

    for (j = 0; j < NUM_SLICES; j = j + 1) begin
        fifo_ptr_reg_next[j]        = fifo_ptr_reg[j];

        fifo_list_wr_en[j]       = 1'b0;
        fifo_list_in_element[j]     = 0;
    end

    array_fifo_demux_select = fifo_ptr_reg[s_axis_tdest];
    //array_fifo_demux_en = 1'b0;
    array_fifo_demux_drop = 1'b0;

    // if a fifo list is empty, assign it the upcoming available fifo (if valid)
    if (upcoming_empty_list_valid && upcoming_available_fifo_valid) begin
        // insert the upcoming available fifo in the upcoming empty fifo list
        fifo_list_wr_en[upcoming_empty_list] = 1'b1;
        fifo_list_in_element[upcoming_empty_list] = upcoming_available_fifo;
        // update the corresponding fifo pointer to allow new pkts to be stored in that fifo
        fifo_ptr_reg_next[upcoming_empty_list] = upcoming_available_fifo;
        // unmark the fifo as available
        fifo_mark_unavailable[upcoming_available_fifo]  = 1'b1;
    end

    // FSM cases
    case (in_state)
        IN_IDLE: begin
            if (s_axis_tvalid) begin    //  && s_axis_tready
                // if the currently assigned fifo has room, select it to store the current pkt
                if ( FIFO_DEPTH - fifo_status_depth[fifo_ptr_reg[s_axis_tdest]] > s_axis_tuser) begin
                    array_fifo_demux_select = fifo_ptr_reg[s_axis_tdest];
                    //array_fifo_demux_en = 1'b1;

                    in_state_next = IN_TRANSMIT;
                // else select the upcoming_available_fifo (if valid), and update the related per_slice_fifo_list and fifo_ptr_reg
                end else if (upcoming_available_fifo_valid && ~upcoming_empty_list_valid && ~fifo_list_full[s_axis_tdest]) begin
                    array_fifo_demux_select = upcoming_available_fifo;
                    //array_fifo_demux_en = 1'b1;

                    fifo_ptr_reg_next[s_axis_tdest] = upcoming_available_fifo;
                    fifo_mark_unavailable[upcoming_available_fifo] = 1'b1;
                    fifo_list_wr_en[s_axis_tdest] = 1'b1;
                    fifo_list_in_element[s_axis_tdest] = upcoming_available_fifo;

                    in_state_next = IN_TRANSMIT;
                end else begin
                    array_fifo_demux_drop = 1'b1;

                    in_state_next = IN_DROP;
                end
            end
        end

        IN_TRANSMIT : begin
            array_fifo_demux_select = fifo_ptr_reg[s_axis_tdest];
            //array_fifo_demux_en = 1'b1;

            if (s_axis_tlast) begin
                in_state_next = IN_IDLE;
            end
        end

        IN_DROP : begin
            array_fifo_demux_drop = 1'b1;
            if (s_axis_tlast) begin
                in_state_next = IN_IDLE;
            end
        end
    endcase
end

//// output-side FSM ////

// States
localparam OUT_IDLE      = 0;
localparam OUT_TRANSMIT  = 1;

// Signals
reg [NUM_SLICES-1:0]    out_state, out_state_next;

generate
    for (i = 0; i < NUM_SLICES; i = i + 1) begin : gen_out_fsm

        // register update
        always @(posedge clk) begin
            if (rst) begin
                out_state[i] <= OUT_IDLE;
            end else begin
                out_state[i] <= out_state_next[i];
            end
        end

        // FSM
        always @(*) begin
            // default
            out_state_next[i] = out_state[i];
            fifo_mark_available_trigger[i] = 1'b0;

            fifo_list_rd_en[i]          = 1'b0;

            per_slice_mux_en[i]         = ~fifo_list_empty[i];
            per_slice_mux_select[i]     = fifo_list_out_element[i];

            // FSM cases
            case(out_state[i])
                OUT_IDLE: begin
                    if (m_axis_tvalid[i] && m_axis_tready[i]) begin
                        out_state_next[i] = OUT_TRANSMIT;
                    end
                end

                OUT_TRANSMIT : begin
                    // after each pkt is transmitted, 
                    // if the current output fifo is empty and is not the input fifo,
                    // remove it from the per_slice_fifo_list and mark it as available
                    if (m_axis_tlast[i]) begin
                        if ( (fifo_status_depth[per_slice_mux_select[i]] == 0) && (per_slice_mux_select[i] != fifo_ptr_reg[i]) ) begin
                            fifo_list_rd_en[i] = 1'b1;
                            fifo_mark_available_trigger[i]  = 1'b1;
                        end

                        out_state_next[i] = OUT_IDLE;
                    end
                end
            endcase
        end
    end
endgenerate

endmodule
