`ifndef PIEO_DATATYPES
`define PIEO_DATATYPES

package pieo_datatypes;

typedef struct packed
{
    logic [ID_LOG-1:0] id;
    logic [RANK_LOG-1:0] rank; //init with infinity
    logic [TIME_LOG-1:0] send_time;
} SublistElement;

typedef struct packed
{
    logic [$clog2(NUM_OF_SUBLIST)-1:0] id;
    logic [RANK_LOG-1:0] smallest_rank; //init with infinity
    logic [TIME_LOG-1:0] smallest_send_time; //init with infinity
    logic full;
    logic [$clog2(NUM_OF_SUBLIST/2)-1:0] num;
} PointerElement;

endpackage
`endif
