`timescale 1ns/1ps
// sram_array.v : behavioral SRAM with spare rows and injectable faults (stands in for a memory macro)
//   (2**ROWB + SPARES) rows x 2**COLB words per row x DW bits; rows 2**ROWB .. are the spare rows
//   write: synchronous (posedge clk, we = 1)     read: combinational (rdata = word at prow / col);
//   re = 1 marks a read cycle (read-disturb faults act at the end of it; leave unconnected if unused)
//   SCOLS spare bit-columns: spare column k is one extra bit per physical row, written when sc_we[k] = 1 (with
//   sc_wdata[k]) and read on sc_rdata[k]; the repair logic decides which bit it stands in for (unused: leave open)
//   up to NF faults, set from the testbench through f_type / f_row / f_col / f_bit / f_arow / f_acol / f_val.
//   cell = (f_row, f_col, bit f_bit); aggressor = (f_arow, f_acol, the same bit):
//      0 none
//      1 stuck-at-0               2 stuck-at-1
//      3 transition, cannot rise (0 -> 1 write fails)       6 transition, cannot fall (1 -> 0 write fails)
//      4 inversion coupling CFin: a transition write on the aggressor flips the cell
//        (rising if f_dir = 0, falling if f_dir = 1; the same for 7)
//      5 column stuck-at-0: bit f_bit of column f_col in EVERY row (a broken bit line)
//      7 idempotent coupling CFid: a transition write on the aggressor forces the cell to f_val
//      8 state coupling CFst: while the aggressor holds 1, the cell reads f_val
//      9 read destructive RDF: a read returns the inverted value and flips the cell
//     10 deceptive read destructive DRDF: a read returns the right value but flips the cell
//     11 write destructive WDF: a write that does not change the cell (0 over 0, 1 over 1) flips it
//     12 address decoder AF: a write to the aggressor word also writes the cell's word
//     13 spare column stuck-at: spare column f_col, row f_row reads f_val
module sram_array #(
    parameter ROWB = 4, COLB = 2, DW = 8, SPARES = 2, SCOLS = 2, NF = 8
) (
    input               clk,
    input               we,
    input               re,
    input  [ROWB:0]     prow,          // physical row: 0 .. 2**ROWB + SPARES - 1
    input  [COLB-1:0]   col,
    input  [DW-1:0]     wdata,
    output [DW-1:0]     rdata,
    input  [SCOLS-1:0]  sc_we,
    input  [SCOLS-1:0]  sc_wdata,
    output [SCOLS-1:0]  sc_rdata
);
    localparam NROW = (1 << ROWB) + SPARES;
    reg [DW-1:0] mem [0:NROW * (1 << COLB) - 1];
    reg [NROW-1:0] scol [0:SCOLS-1];               // spare column k: one bit per physical row
    reg [3:0]      f_type [0:NF-1];
    reg [ROWB:0]   f_row  [0:NF-1], f_arow [0:NF-1];
    reg [COLB-1:0] f_col  [0:NF-1], f_acol [0:NF-1];
    reg [7:0]      f_bit  [0:NF-1];
    reg            f_val  [0:NF-1], f_dir [0:NF-1];
    integer i;
    initial for (i = 0; i < NF; i = i + 1) begin
        f_type[i] = 0; f_row[i] = 0; f_col[i] = 0; f_bit[i] = 0; f_arow[i] = 0; f_acol[i] = 0; f_val[i] = 0; f_dir[i] = 0;
    end

    wire [ROWB+COLB:0] idx = {prow, col};
    wire is_read = (re === 1'b1) && !we;
    reg  [DW-1:0] word;
    always @(posedge clk) begin
        if (we) begin
            word = wdata;
            for (i = 0; i < NF; i = i + 1) if (prow == f_row[i] && col == f_col[i]) begin
                if (f_type[i] == 3 && !mem[idx][f_bit[i]] &&  wdata[f_bit[i]]) word[f_bit[i]] = 1'b0;
                if (f_type[i] == 6 &&  mem[idx][f_bit[i]] && !wdata[f_bit[i]]) word[f_bit[i]] = 1'b1;
                if (f_type[i] == 11 && mem[idx][f_bit[i]] === wdata[f_bit[i]]) word[f_bit[i]] = ~wdata[f_bit[i]];
            end
            mem[idx] <= word;
            for (i = 0; i < NF; i = i + 1) if (prow == f_arow[i] && col == f_acol[i]) begin
                if (f_type[i] == 4 && mem[idx][f_bit[i]] === f_dir[i] && wdata[f_bit[i]] === !f_dir[i])
                    mem[{f_row[i], f_col[i]}][f_bit[i]] <= ~mem[{f_row[i], f_col[i]}][f_bit[i]];
                if (f_type[i] == 7 && mem[idx][f_bit[i]] === f_dir[i] && wdata[f_bit[i]] === !f_dir[i])
                    mem[{f_row[i], f_col[i]}][f_bit[i]] <= f_val[i];
                if (f_type[i] == 12)
                    mem[{f_row[i], f_col[i]}] <= wdata;
            end
        end
        if (is_read)
            for (i = 0; i < NF; i = i + 1)
                if ((f_type[i] == 9 || f_type[i] == 10) && prow == f_row[i] && col == f_col[i])
                    mem[idx][f_bit[i]] <= ~mem[idx][f_bit[i]];
    end

    reg [DW-1:0] r;
    always @(*) begin
        r = mem[idx];
        for (i = 0; i < NF; i = i + 1) begin
            if (prow == f_row[i] && col == f_col[i]) begin
                if (f_type[i] == 1) r[f_bit[i]] = 1'b0;
                if (f_type[i] == 2) r[f_bit[i]] = 1'b1;
                if (f_type[i] == 9) r[f_bit[i]] = ~mem[idx][f_bit[i]];
                if (f_type[i] == 8 && mem[{f_arow[i], f_acol[i]}][f_bit[i]] === 1'b1) r[f_bit[i]] = f_val[i];
            end
            if (f_type[i] == 5 && col == f_col[i]) r[f_bit[i]] = 1'b0;
        end
    end
    assign rdata = r;

    // spare columns
    integer k;
    always @(posedge clk)
        for (k = 0; k < SCOLS; k = k + 1)
            if (we && sc_we[k] === 1'b1) scol[k][prow] <= sc_wdata[k];
    reg [SCOLS-1:0] sr;
    always @(*) begin
        for (k = 0; k < SCOLS; k = k + 1) sr[k] = scol[k][prow];
        for (i = 0; i < NF; i = i + 1)
            if (f_type[i] == 13 && f_col[i] < SCOLS && prow == f_row[i]) sr[f_col[i]] = f_val[i];
    end
    assign sc_rdata = sr;
endmodule
