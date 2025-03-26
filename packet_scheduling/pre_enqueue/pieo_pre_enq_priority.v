module pieo_pre_enq_priority #(
    parameter NUM_FIFO = 3,
    parameter ID_LOG = 2,
    parameter RANK_LOG = 1,
    parameter TIME_LOG = 1
)(
    // from pieo
    input  wire                                   pieo_ready_for_enq,
    
    // from enq fifo tracker
    input  wire [ID_LOG-1:0]                      fifo_id,
    
    // from parameter store
    input wire  [NUM_FIFO*RANK_LOG-1:0]           fifo_priority,
    
    // to pieo
    output reg [ID_LOG+RANK_LOG+TIME_LOG-1:0]     pieo_enq_element,
    output reg                                    pieo_enq_trigger
);

wire [RANK_LOG-1:0]  pieo_rank;
reg  [TIME_LOG-1:0]  pieo_send_time = 1;

assign pieo_rank = fifo_priority[fifo_id*RANK_LOG +: RANK_LOG];

always @(*)begin
    pieo_enq_element = 0;
    pieo_enq_trigger = 0;
    
    if (pieo_ready_for_enq) begin
        pieo_enq_element = {pieo_send_time, pieo_rank, fifo_id};
        pieo_enq_trigger = 1;
    end
end

endmodule
