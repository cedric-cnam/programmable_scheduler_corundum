//  Xilinx True Dual Port RAM Read First Dual Clock
//  This code implements a parameterizable true dual port memory (both ports can read and write).
//  This implements read-first mode.
//  If a reset or enable is not necessary, it may be tied off or removed from the code.

`timescale 1 ps / 1 ps

module true_dp_bram_readfirst
#(
    parameter RAM_ADDR_BITS = 8, //RAM_ADDR_BITS
    parameter RAM_WIDTH = 32
)
(
    input                              clk,

    input                              we1,
    input                              en1,
    input       [RAM_ADDR_BITS-1:0]    addr1,
    input       [RAM_WIDTH-1:0]        din1,
    output      [RAM_WIDTH-1:0]        dout1,

    input                              we2,
    input                              en2,
    input       [RAM_ADDR_BITS-1:0]    addr2,
    input       [RAM_WIDTH-1:0]        din2,
    output      [RAM_WIDTH-1:0]        dout2
);

  (* ram_style = "block" *)

  localparam INIT_FILE = "";                       // Specify name/location of RAM initialization file if using one (leave blank if not)

//  <wire_or_reg> [clogb2(RAM_DEPTH-1)-1:0] addra;  // Port A address bus, width determined from RAM_DEPTH
//  <wire_or_reg> [clogb2(RAM_DEPTH-1)-1:0] addrb;  // Port B address bus, width determined from RAM_DEPTH
//  <wire_or_reg> [RAM_WIDTH-1:0] dina;           // Port A RAM input data
//  <wire_or_reg> [RAM_WIDTH-1:0] dinb;           // Port B RAM input data
//  <wire_or_reg> clka;                           // Port A clock
//  <wire_or_reg> clkb;                           // Port B clock
//  <wire_or_reg> wea;                            // Port A write enable
//  <wire_or_reg> web;                            // Port B write enable
//  <wire_or_reg> ena;                            // Port A RAM Enable, for additional power savings, disable port when not in use
//  <wire_or_reg> enb;                            // Port B RAM Enable, for additional power savings, disable port when not in use
//  <wire_or_reg> rsta;                           // Port A output reset (does not affect memory contents)
//  <wire_or_reg> rstb;                           // Port B output reset (does not affect memory contents)
//  <wire_or_reg> regcea;                         // Port A output register enable
//  <wire_or_reg> regceb;                         // Port B output register enable
//  wire [RAM_WIDTH-1:0] douta;                   // Port A RAM output data
//  wire [RAM_WIDTH-1:0] doutb;                   // Port B RAM output data

  localparam DEPTH = 2**RAM_ADDR_BITS;

  reg [RAM_WIDTH-1:0] RAM [DEPTH-1:0];
  reg [RAM_WIDTH-1:0] RAM_data_1 = {RAM_WIDTH{1'b0}};
  reg [RAM_WIDTH-1:0] RAM_data_2 = {RAM_WIDTH{1'b0}};

  // The following code either initializes the memory values to a specified file or to all zeros to match hardware
  generate
    if (INIT_FILE != "") begin: use_init_file
      initial
        $readmemh(INIT_FILE, RAM, 0, DEPTH-1);
    end else begin: init_bram_to_zero
      integer ram_index;
      initial
        for (ram_index = 0; ram_index < DEPTH; ram_index = ram_index + 1)
          RAM[ram_index] = {RAM_WIDTH{1'b0}};
    end
  endgenerate

  always @(posedge clk)
    if (en1) begin
      RAM_data_1 <= RAM[addr1]; 
      if (we1) begin
        RAM[addr1] <= din1;
      end
    end

  always @(posedge clk)
    if (en2) begin
      RAM_data_2 <= RAM[addr2]; 
      if (we2) begin
        RAM[addr2] <= din2;
      end
    end

  assign dout1 = RAM_data_1;
  assign dout2 = RAM_data_2;

endmodule