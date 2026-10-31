`timescale 1ns/1ps
// sram_array_ff.v : synthesizable stand-in for model/sram_array.v (same module name and ports, no fault injection)
//   used only by the OpenROAD flow; the array becomes flip-flops, so the area is an upper bound for the storage
//   (a real SRAM bit cell is several times smaller than a flip-flop) and the BISR overhead below is conservative
module sram_array #(
    parameter ROWB = 4, COLB = 2, DW = 8, SPARES = 2, NF = 4
) (
    input               clk,
    input               we,
    /* verilator lint_off UNUSEDSIGNAL */
    input               re,            // read strobe: only the fault model uses it
    /* verilator lint_on UNUSEDSIGNAL */
    input  [ROWB:0]     prow,
    input  [COLB-1:0]   col,
    input  [DW-1:0]     wdata,
    output [DW-1:0]     rdata
);
    localparam NROW = (1 << ROWB) + SPARES;
    reg [DW-1:0] mem [0:NROW * (1 << COLB) - 1];
    always @(posedge clk) if (we) mem[{prow, col}] <= wdata;
    assign rdata = mem[{prow, col}];
endmodule
