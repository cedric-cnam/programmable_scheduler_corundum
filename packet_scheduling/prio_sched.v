module prio_sched#(
    parameter NUM_FIFO = 3,
    parameter SEL_WIDTH = $clog2(NUM_FIFO)
)
(
    input                                       clk, rst,
    
    input wire [NUM_FIFO-1:0]                   fifo_tvalid,
    input wire [NUM_FIFO-1:0]                   fifo_tlast,
    output reg [SEL_WIDTH-1:0]                  sel_out,
    output reg                                  en_out = 1'b1
);

wire [SEL_WIDTH-1:0] enc_out;
wire                 enc_valid;

// priority encoder to determine fifo to schedule next
priority_encoder_tree #(
    .WIDTH(NUM_FIFO),
    .EN_REVERSE(1)
) fifo_prio_encoder (
    .input_unencoded(fifo_tvalid),
    .output_valid(enc_valid),
    .output_encoded(enc_out)
);


reg idle;
reg next_idle;
reg [SEL_WIDTH-1:0] next_sel;

always @(posedge clk) begin
    if (rst) begin
        sel_out  <= 0;
        idle <= 1;
    end else begin
        sel_out  <= next_sel;
        idle <= next_idle;
    end
end

always @(*)begin
    next_sel = sel_out;
    next_idle = idle;

    if (|fifo_tlast) begin  
        next_idle=1'b1;
    end
    if (idle) begin
            if (enc_valid) begin
                next_idle = 1'b0;
                next_sel  <= enc_out;
            end
    end
end

endmodule
