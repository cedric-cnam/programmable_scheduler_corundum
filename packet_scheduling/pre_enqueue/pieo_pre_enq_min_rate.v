module pieo_pre_enq_min_rate #(
    /* application-specific parameters */
    parameter NUM_FIFO = 3,
    parameter PKT_LEN_WIDTH = 16,
    
    /* generic parameters */
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
    input wire [NUM_FIFO*PKT_LEN_WIDTH-1:0]       fifo_packet_length,
    
    // from parameter store
    /* fifo_min_rate = ( desired_bit_rate * 5e-9)/8
       note: since we transmit 8 bytes per clk, this should be normalised to that */
    input wire  [NUM_FIFO*PKT_LEN_WIDTH-1:0]      fifo_min_rate,             
    input wire  [NUM_FIFO*PKT_LEN_WIDTH-1:0]      fifo_burst_size,
    
    // to pieo
    output reg [ID_LOG+RANK_LOG+TIME_LOG-1:0]     pieo_enq_element,
    output reg                                    pieo_enq_trigger
);


/*
    Token Bucket
*/

reg [PKT_LEN_WIDTH-1:0] token_bucket       [NUM_FIFO-1:0];
reg [PKT_LEN_WIDTH-1:0] token_bucket_inc   [NUM_FIFO-1:0];
reg [PKT_LEN_WIDTH-1:0] token_bucket_dec   [NUM_FIFO-1:0];

// Debug purpose
reg [NUM_FIFO*PKT_LEN_WIDTH-1:0] token_bucket_w;


integer i;
always @(posedge clk) begin
    if (rst) begin
        for (i = 0; i < NUM_FIFO; i = i + 1) begin
            token_bucket[i] <= {1'b0, {(PKT_LEN_WIDTH-1){1'b1}}};
        end
    end else begin
        for (i = 0; i < NUM_FIFO; i = i + 1) begin
            if ( (token_bucket[i] + token_bucket_inc[i]) > fifo_burst_size[i*PKT_LEN_WIDTH +: PKT_LEN_WIDTH] ) begin
                token_bucket[i] <= fifo_burst_size[i*PKT_LEN_WIDTH +: PKT_LEN_WIDTH] - token_bucket_dec[i];
            end else begin
                token_bucket[i] <= token_bucket[i] + token_bucket_inc[i] - token_bucket_dec[i];
            end
        end
    end
end


/*
    Control Logic
*/

reg [RANK_LOG-1:0]  pieo_rank;
reg [TIME_LOG-1:0]  pieo_send_time;


always @(*)begin
    pieo_rank = 0;
    pieo_send_time = 1;

    pieo_enq_element = 0;
    pieo_enq_trigger = 0;
    
    // tb default updates
    for (i = 0; i < NUM_FIFO; i = i + 1) begin
        token_bucket_inc[i] = fifo_min_rate[i*PKT_LEN_WIDTH +: PKT_LEN_WIDTH];
        token_bucket_dec[i] = 0;
        // Debug purpose
        token_bucket_w[i*PKT_LEN_WIDTH +: PKT_LEN_WIDTH] = token_bucket[i];
    end
    
    if (pieo_ready && fifos_not_enq_flag) begin
        // Check there are enough tokens
        if (token_bucket[fifo_id] >= fifo_packet_length[fifo_id*PKT_LEN_WIDTH +: PKT_LEN_WIDTH]) begin
            pieo_rank = 1;
            token_bucket_dec[fifo_id] = fifo_packet_length[fifo_id*PKT_LEN_WIDTH +: PKT_LEN_WIDTH];
        end else begin
            pieo_rank = 2;
            token_bucket_dec[fifo_id] = token_bucket[fifo_id];
        end
    
        pieo_enq_element = {pieo_send_time, pieo_rank, fifo_id};
        pieo_enq_trigger = 1;
    end
end

endmodule
