module pieo_pre_enq_default #(
    parameter ID_LOG = 2,
    parameter RANK_LOG = 1,
    parameter TIME_LOG = 1
)(
    // from pieo
    input  wire                                   pieo_ready,
    
    // from enq fifo tracker
    input  wire                                   fifos_not_enq_flag,
    input  wire [ID_LOG-1:0]                      fifo_id,
    
    // to pieo
    output reg [ID_LOG+RANK_LOG+TIME_LOG-1:0]     pieo_enq_element,
    output reg                                    pieo_enq_trigger
);

reg [RANK_LOG-1:0]  pieo_rank = 1;
reg [TIME_LOG-1:0]  pieo_send_time = 1;


always @(*)begin
    pieo_enq_element = 0;
    pieo_enq_trigger = 0;
    
    if (pieo_ready && fifos_not_enq_flag) begin
        pieo_enq_element = {pieo_send_time, pieo_rank, fifo_id};
        pieo_enq_trigger = 1;
    end
end

endmodule
