module sched_fifo_buffer #(
    parameter NUM_FIFO = 3,
    parameter ID_LOG = $clog2(NUM_FIFO),
    parameter RANK_LOG = 1,
    parameter TIME_LOG = 1,
    parameter ELEMENT_WIDTH = ID_LOG + RANK_LOG + TIME_LOG

)(
    input  wire                          clk, rst,

    // pieo interface
    input  wire                          pieo_ready_for_deq, pieo_empty,

    input  wire                          deq_valid_in,
    input  wire  [ELEMENT_WIDTH-1:0]     deq_element_in,

    output reg                           pieo_deq_trigger_out,

    // post deq interface
    input wire                           post_deq_ready,

    output  reg                          deq_valid_out,
    output  reg  [ELEMENT_WIDTH-1:0]     deq_element_out
);

// define register signals
reg [ELEMENT_WIDTH-1:0]  buff_element_r,         buff_element_next_r;
reg                      buff_has_element_r,     buff_has_element_next_r;
reg                      waiting_for_pieo_deq_r, waiting_for_pieo_deq_next_r;

always @(posedge clk) begin
    if (rst) begin
        buff_element_r          <= {ELEMENT_WIDTH{1'b0}};;
        buff_has_element_r      <= 1'b0;
        waiting_for_pieo_deq_r  <= 1'b0;
    end else begin
        buff_element_r          <= buff_element_next_r;
        buff_has_element_r      <= buff_has_element_next_r;
        waiting_for_pieo_deq_r  <= waiting_for_pieo_deq_next_r;
    end
end

always @(*)begin
    // Default reg update
    buff_element_next_r         = buff_element_r;
    buff_has_element_next_r     = buff_has_element_r;
    waiting_for_pieo_deq_next_r = waiting_for_pieo_deq_r;
    // Default outputs
    pieo_deq_trigger_out        = 1'b0;
    deq_valid_out               = 1'b0;
    deq_element_out             = {ELEMENT_WIDTH{1'b0}};;

    // pieo dequeue trigger
    if (pieo_ready_for_deq && ~pieo_empty && ~buff_has_element_r && ~waiting_for_pieo_deq_r) begin
        waiting_for_pieo_deq_next_r = 1'b1;

        pieo_deq_trigger_out = 1'b1;
    end

    // receive pieo dequeue
    if (deq_valid_in && waiting_for_pieo_deq_r) begin
        waiting_for_pieo_deq_next_r = 1'b0;
        // check if deq element is valid
        if (~&deq_element_in) begin
            buff_element_next_r = deq_element_in;
            buff_has_element_next_r = 1'b1;
        end
    end

    // transmit element to post deq
    if (post_deq_ready && buff_has_element_r) begin
        buff_has_element_next_r = 1'b0;
        
        deq_valid_out = 1'b1;
        deq_element_out = buff_element_r;
    end

end
   
endmodule
