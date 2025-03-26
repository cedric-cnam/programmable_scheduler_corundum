module simple_fifo #(
    parameter DATA_WIDTH = 8,  // Width of the data
    parameter DEPTH = 16       // Depth of the FIFO (number of entries)
)(
    input  wire                     clk,      // Clock signal
    input  wire                     rst,      // Reset signal (synchronous, active high)
    input  wire                     wr_en,    // Write enable
    input  wire                     rd_en,    // Read enable
    input  wire [DATA_WIDTH-1:0]    data_in, // Data input
    output wire [DATA_WIDTH-1:0]    data_out, // Data output
    output wire                     full,     // FIFO full flag
    output wire                     empty     // FIFO empty flag
);

    // Internal signals
    reg [DATA_WIDTH-1:0] mem[0:DEPTH-1]; // FIFO memory
    reg [$clog2(DEPTH):0] wr_ptr;        // Write pointer
    reg [$clog2(DEPTH):0] rd_ptr;        // Read pointer
    reg [$clog2(DEPTH+1)-1:0] count;     // Entry count

    // Write operation
    always @(posedge clk) begin
        if (rst) begin
            wr_ptr <= 0;
        end else if (wr_en && !full) begin
            mem[wr_ptr] <= data_in;
            wr_ptr <= wr_ptr + 1;
        end
    end

    // Read operation
    always @(posedge clk) begin
        if (rst) begin
            rd_ptr <= 0;
        end else if (rd_en && !empty) begin
            rd_ptr <= rd_ptr + 1;
        end
    end

    // Count tracking
    always @(posedge clk) begin
        if (rst) begin
            count <= 0;
        end else begin
            case ({wr_en && !full, rd_en && !empty})
                2'b10: count <= count + 1; // Write only
                2'b01: count <= count - 1; // Read only
                default: count <= count;   // No change or simultaneous write and read
            endcase
        end
    end

    // Output logic
    assign data_out = mem[rd_ptr]; // Data output from read pointer
    assign full  = (count == DEPTH); // Full flag
    assign empty = (count == 0);     // Empty flag

endmodule

