module pieo_post_deq_drr #(
    /* application-specific parameters */
    // drr parameters
    parameter QUANTUM = 2000,
    parameter PKT_LEN_WIDTH = 16,
    //parameter NUM_FIFOS = 3,
    
    /* generic parameters */
    // fifo parameters
    parameter NUM_QUEUES = 3,
    // pieo parameters
    parameter ID_LOG = $clog2(NUM_QUEUES),
    parameter RANK_LOG = 1,
    parameter TIME_LOG = 1
)(
    input  wire                                   clk, rst, 
    input  wire                                   en_in,
    
    // from pieo
    input  wire                                   pieo_ready, pieo_empty,
    input  wire                                   pieo_deq_valid,
    input  wire  [ID_LOG+RANK_LOG+TIME_LOG-1:0]   pieo_deq_element,
    // to pieo
    output reg                                    pieo_deq_trigger,
    
    // from fifos
    input wire [NUM_QUEUES-1:0]                   fifo_tvalid,         //NUM_FIFOS
    input wire [NUM_QUEUES-1:0]                   pe_tlast,
    input wire [PKT_LEN_WIDTH-1:0]                head_pkt_length,
    
    // from enq fifo tracker
    input wire                                    fifos_not_enq_flag,
    // to enq fifo tracker
    output reg [NUM_QUEUES-1:0]                   post_deq_end,
  
    // to mux
    output reg [ID_LOG-1:0]                       sel_out,
    output reg                                    en_out                           
);


/*
    MAIN FSM
*/

reg [ID_LOG-1:0]    sel_r, sel_next_r;
reg                 en_r,  en_next_r;


reg [PKT_LEN_WIDTH-1:0] deficit_counter [NUM_QUEUES-1:0];
reg [PKT_LEN_WIDTH-1:0] next_deficit_counter [NUM_QUEUES-1:0];
    
wire [PKT_LEN_WIDTH-1:0]    w_deficit_counter;

assign w_deficit_counter = deficit_counter[sel_r];


// FSM States
localparam IDLE = 0, WAIT_PIEO = 1, SEND = 2, CHECK_QUEUE_EMPTY = 3;
reg [1:0] current_state, next_state;
integer i;

always @(posedge clk) begin
    if (rst) begin
        current_state  <= IDLE;
        sel_r          <= 0;
        en_r           <= 1'b0;
        for (i = 0; i < NUM_QUEUES; i = i + 1) begin
            deficit_counter[i] <= 0;
        end
    end else begin
        current_state  <= next_state;
        sel_r          <= sel_next_r;
        en_r           <= en_next_r;
        for (i = 0; i < NUM_QUEUES; i = i + 1) begin
            deficit_counter[i] <= next_deficit_counter[i];
        end
    end
end

always @(*)begin
    // Default
    next_state = current_state;
    
    sel_next_r = sel_r;
    sel_out    = sel_r;
    en_next_r  = en_r;
    en_out     = en_r;
    
    pieo_deq_trigger = 1'b0;
    
    post_deq_end = 0;
    
    for (i = 0; i < NUM_QUEUES; i = i + 1) begin
        next_deficit_counter[i] = deficit_counter[i];
    end
    
    case(current_state)
    
        IDLE: begin
            if (pieo_ready && ~pieo_empty && ~fifos_not_enq_flag && en_in) begin
                pieo_deq_trigger = 1'b1;
                next_state = WAIT_PIEO;
            end
        end
        
        WAIT_PIEO: begin
            if (pieo_deq_valid) begin
                if (~&pieo_deq_element && fifo_tvalid[pieo_deq_element[ID_LOG-1 : 0]]) begin
                    sel_next_r = pieo_deq_element[ID_LOG-1 : 0];
                    sel_out    = pieo_deq_element[ID_LOG-1 : 0];
                    en_next_r  = 1'b1;
                    en_out     = 1'b1;
                    next_state = SEND;
                end else begin
                    next_state = IDLE;
                end
            end
        end
        
        SEND : begin
            if (pe_tlast[sel_r]) begin
                // After each pkt, update the deficit counter
                next_deficit_counter[sel_r] = deficit_counter[sel_r] + head_pkt_length;
                en_next_r  = 1'b0;
                // If we passed the QUANTUM, go to IDLE and reduce the counter
                if (next_deficit_counter[sel_r] >= QUANTUM) begin
                    next_state = IDLE;
                    next_deficit_counter[sel_r] = next_deficit_counter[sel_r] - QUANTUM;
                    post_deq_end[sel_r] = 1'b1;
                // If the enable is not active anymore, go to IDLE, disable mux and reset the counter 
                end else if (~en_in) begin
                    next_state = IDLE;
                    next_deficit_counter[sel_r] = 0;
                    post_deq_end[sel_r] = 1'b1;
                // Otherwise, check if there is another packet
                end else begin
                    next_state = CHECK_QUEUE_EMPTY;
                end 
            end
        end
        
        CHECK_QUEUE_EMPTY : begin
            // If there is another pkt in the current fifo, go back to SEND
            if (fifo_tvalid[sel_r]) begin
                next_state = SEND;
                en_next_r  = 1'b1;
                en_out     = 1'b1;
            // Otherwise disable mux, reset deficit counter and go back to idle
            end else begin
                next_state = IDLE;
                next_deficit_counter[sel_r] = 0;
                post_deq_end[sel_r] = 1'b1;
            end
        end
    
    endcase
end

endmodule
