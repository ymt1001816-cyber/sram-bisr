`timescale 1ns/1ps
// sram_array.v : behavioral SRAM with spare rows and injectable faults (stands in for a memory macro)
//   (2**ROWB + SPARES) rows x 2**COLB words per row x DW bits; rows 2**ROWB .. are the spare rows
//   write: synchronous (posedge clk, we = 1)     read: combinational (rdata = word at prow / col)
//   up to NF faults, set from the testbench through f_type / f_row / f_col / f_bit (and f_arow / f_acol):
//     0 none   1 stuck-at-0 cell   2 stuck-at-1 cell   3 transition (cell cannot rise 0 -> 1)
//     4 coupling (a rising write to bit f_bit of the aggressor word f_arow / f_acol flips the victim cell)
//     5 column stuck-at-0 (bit f_bit of column f_col in EVERY row: a broken bit line)
module sram_array #(
    parameter ROWB = 4, COLB = 2, DW = 8, SPARES = 2, NF = 4
) (
    input               clk,
    input               we,
    input  [ROWB:0]     prow,          // physical row: 0 .. 2**ROWB + SPARES - 1
    input  [COLB-1:0]   col,
    input  [DW-1:0]     wdata,
    output [DW-1:0]     rdata
);
    localparam NROW = (1 << ROWB) + SPARES;
    reg [DW-1:0] mem [0:NROW * (1 << COLB) - 1];
    reg [2:0]      f_type [0:NF-1];
    reg [ROWB:0]   f_row  [0:NF-1], f_arow [0:NF-1];
    reg [COLB-1:0] f_col  [0:NF-1], f_acol [0:NF-1];
    reg [7:0]      f_bit  [0:NF-1];
    integer i;
    initial for (i = 0; i < NF; i = i + 1) begin
        f_type[i] = 0; f_row[i] = 0; f_col[i] = 0; f_bit[i] = 0; f_arow[i] = 0; f_acol[i] = 0;
    end

    wire [ROWB+COLB:0] idx = {prow, col};
    reg  [DW-1:0] word;
    always @(posedge clk) if (we) begin
        word = wdata;
        for (i = 0; i < NF; i = i + 1)
            if (f_type[i] == 3 && prow == f_row[i] && col == f_col[i] && !mem[idx][f_bit[i]] && wdata[f_bit[i]])
                word[f_bit[i]] = 1'b0;                                   // transition fault: cannot rise
        mem[idx] <= word;
        for (i = 0; i < NF; i = i + 1)
            if (f_type[i] == 4 && prow == f_arow[i] && col == f_acol[i] && !mem[idx][f_bit[i]] && wdata[f_bit[i]])
                mem[{f_row[i], f_col[i]}][f_bit[i]] <= ~mem[{f_row[i], f_col[i]}][f_bit[i]];   // coupling
    end

    reg [DW-1:0] r;
    always @(*) begin
        r = mem[idx];
        for (i = 0; i < NF; i = i + 1) begin
            if (f_type[i] == 1 && prow == f_row[i] && col == f_col[i]) r[f_bit[i]] = 1'b0;
            if (f_type[i] == 2 && prow == f_row[i] && col == f_col[i]) r[f_bit[i]] = 1'b1;
            if (f_type[i] == 5 && col == f_col[i])                     r[f_bit[i]] = 1'b0;
        end
    end
    assign rdata = r;
endmodule
