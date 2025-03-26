module pieo_post_deq_default #(
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
    input wire [NUM_QUEUES-1:0]                   fifo_tvalid,
    input wire [NUM_QUEUES-1:0]                   pe_tlast,
    
    // from enq fifo tracker
    input wire                                    fifos_not_enq_flag,
  
    // to mux
    output reg [ID_LOG-1:0]                       sel_out,
    output reg                                    en_out                           
);


/*
    MAIN FSM
*/

reg [ID_LOG-1:0]    sel_r, sel_next_r;
reg                 en_r,  en_next_r;

// FSM States
localparam IDLE = 0, WAIT_PIEO = 1, SEND = 2;
reg [1:0] current_state, next_state;

always @(posedge clk) begin
    if (rst) begin
        current_state  <= IDLE;
        sel_r          <= 0;
        en_r           <= 1'b0;
    end else begin
        current_state  <= next_state;
        sel_r          <= sel_next_r;
        en_r           <= en_next_r;
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
                next_state = IDLE;
                en_next_r  = 1'b0;
            end
        end
    
    endcase
end

endmodule
