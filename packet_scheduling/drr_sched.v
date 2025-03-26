module drr_sched #(
    parameter NUM_FIFO = 3,
    parameter QUANTUM = 2000,
    parameter PKT_LEN_WIDTH = 16,
    parameter SEL_WIDTH = $clog2(NUM_FIFO)
)(
    input wire                                  clk, rst,
    input wire [NUM_FIFO-1:0]                   fifo_tvalid,
    input wire [NUM_FIFO*PKT_LEN_WIDTH-1:0]     fifo_packet_length,
    input wire [NUM_FIFO-1:0]                   fifo_tlast,
    output reg [SEL_WIDTH-1:0]                  sel_out,
    output reg                                  en_out = 1'b1
);

    reg [SEL_WIDTH-1:0] next_sel, sel;
    reg [PKT_LEN_WIDTH-1:0] deficit_counter [NUM_FIFO-1:0];
    reg [PKT_LEN_WIDTH-1:0] next_deficit_counter [NUM_FIFO-1:0];
    reg [PKT_LEN_WIDTH-1:0] head_pkt_length [NUM_FIFO-1:0];
    
    wire [PKT_LEN_WIDTH-1:0]    w_deficit_counter;
    wire [PKT_LEN_WIDTH-1:0]    w_head_packet_length;
    
    reg  [NUM_FIFO-1:0] fifo_tlast_prev;
    wire [NUM_FIFO-1:0] pe_tlast;
    
    assign pe_tlast = fifo_tlast & ~fifo_tlast_prev;

    integer i;
    assign w_deficit_counter = deficit_counter[sel];
    assign w_head_packet_length = head_pkt_length [sel];
    
    wire [SEL_WIDTH-1:0] next_valid;
    wire                 found_next_valid;
    
    find_next_valid #(
        .INPUT_WIDTH(NUM_FIFO)
    ) find_next_valid_inst (
        .all_valid(fifo_tvalid),
        .curr_valid(sel),
        .next_valid(next_valid),
        .found(found_next_valid)
    );
    
    // FSM States
    localparam IDLE = 0, SEND = 1;
    reg current_state, next_state;

    always @(posedge clk) begin
        if (rst) begin
            fifo_tlast_prev <= 0;
            sel <= 0;
            current_state <= IDLE;
            for (i = 0; i < NUM_FIFO; i = i + 1) begin
                deficit_counter[i] <= 0;
            end
        end else begin
            fifo_tlast_prev <= fifo_tlast;
            sel <= next_sel;
            current_state <= next_state;
            for (i = 0; i < NUM_FIFO; i = i + 1) begin
                deficit_counter[i] <= next_deficit_counter[i];
            end
        end
    end

    always @(*) begin
        sel_out  = sel;
        next_sel = sel;
        next_state = current_state;

        for (i = 0; i < NUM_FIFO; i = i + 1) begin
            next_deficit_counter[i] = deficit_counter[i];
            head_pkt_length[i] = fifo_packet_length[i*PKT_LEN_WIDTH +: PKT_LEN_WIDTH];
        end

        

        case(current_state)
            IDLE: begin
            	if(!fifo_tvalid[sel]) begin // no more packets in current fifo
                    next_deficit_counter[sel] = 0;
                    if (found_next_valid) begin
                        next_sel = next_valid;
                        next_state = SEND;
                    end
                end else if (deficit_counter[sel] >= QUANTUM) begin // there's a packet but we already sent more than QUANTUM bytes
                    next_deficit_counter[sel] = deficit_counter[sel] - QUANTUM;
                    if (found_next_valid) begin
                        sel_out  = next_valid;
                        next_sel = next_valid;
                        next_state = SEND;
                    end
                end else begin // there's a packet and it fits in the current deficit
                    next_state = SEND;
                end
            end
           

            SEND: begin
            	if (pe_tlast[sel]) begin 
            	   next_deficit_counter[sel] = deficit_counter[sel] + head_pkt_length[sel];
                   next_state = IDLE;
               end
            end
         endcase
    end
    
endmodule
