`timescale 1ns/1ps
// bira2d.v : 2D redundancy analysis: SR spare rows + SC spare bit-columns
// Author: Meiyu Kuo
//   During test 1 (en), every wrong read reports err_row, err_col and err_bits (which bits were wrong).
//   1. collect : pick the lowest wrong bit not already covered (by a spare row, a spare column, or a recorded
//                fault). At most one new fault per read; a March reads every word several times, so the
//                others are picked up on later reads.
//   2. must-repair, right away : if that row would have more faults than the spare columns left can fix, it MUST
//                take a spare row; if that column would have more faults than the spare rows left, a spare column.
//                Otherwise remember the fault in a small table (K entries: cv valid, cr row, cc bit-column).
//   3. analyze (after test 1, `analyze` pulse): one line per cycle, the row or column with the most faults left
//                in the table (rows win ties), until the table is empty (done) or no spare fits (unrepairable).
//   bit-column = {word column, bit index} (COLB + 3 bits for DW = 8)
module bira2d #(parameter ROWB = 4, COLB = 2, DW = 8, SR = 2, SC = 2, K = 8) (
    input                        clk, rst_n,
    input                        clear,
    input                        en,
    input                        err,
    input      [ROWB-1:0]        err_row,
    input      [COLB-1:0]        err_col,
    input      [DW-1:0]          err_bits,
    input                        analyze,
    output reg                   busy,
    output reg [SR-1:0]          rvalid,
    output reg [SR*ROWB-1:0]     rrow,
    output reg [SC-1:0]          cvalid,
    output reg [SC*(COLB+3)-1:0] ccol,
    output reg                   unrepairable
);
    localparam BCW = COLB + 3;            // bit-column = {word column, bit}; DW = 8 -> 3 bit index
    integer i, j, b;
    reg [K-1:0]        cv;
    reg [ROWB-1:0]     cr [0:K-1];
    reg [BCW-1:0]      cc [0:K-1];

    function [3:0] pop(input [K-1:0] v);
        integer n; begin pop = 0; for (n = 0; n < K; n = n + 1) pop = pop + v[n]; end
    endfunction
    function [2:0] popn(input [7:0] v);   // spares are few; up to 7
        integer n; begin popn = 0; for (n = 0; n < 8; n = n + 1) popn = popn + v[n]; end
    endfunction
    wire [2:0] rused = popn({{(8-SR){1'b0}}, rvalid});
    wire [2:0] cused = popn({{(8-SC){1'b0}}, cvalid});
    localparam [3:0] SR4 = SR, SC4 = SC;
    wire [3:0] rleft = SR4 - {1'b0, rused};     // spare rows still free
    wire [3:0] cleft = SC4 - {1'b0, cused};     // spare columns still free

    // ---- collect: pick the lowest failing bit not yet covered ----
    reg row_rep, found, masked;
    reg [2:0] nb;
    reg [BCW-1:0] nc;
    reg [3:0] rcnt, ccnt;
    reg [SR-1:0] rfree; reg [SC-1:0] cfree; reg [K-1:0] kfree;
    reg rf, cf, kf;
    always @(*) begin
        row_rep = 1'b0;
        for (i = 0; i < SR; i = i + 1) if (rvalid[i] && rrow[i*ROWB +: ROWB] == err_row) row_rep = 1'b1;
        found = 1'b0; nb = 0;
        // TODO A: for each bit b (0 .. DW-1): it is a NEW fault if err_bits[b] = 1 and it is not covered:
        //   not row_rep, not a valid spare column with ccol == {err_col, b[2:0]},
        //   not a valid table entry with cr == err_row and cc == {err_col, b[2:0]}.
        //   The FIRST (lowest) new bit: found = 1, nb = b[2:0]. (use the `masked` variable as a scratch flag)
        masked = 0;
        for (b = 0; b < DW; b = b + 1) begin
            masked = row_rep;
            for (i = 0; i < SC; i = i + 1)
                if (cvalid[i] && ccol[i*BCW +: BCW] == {err_col, b[2:0]}) masked = 1;
            for (i = 0; i < K; i = i + 1)
                if (cv[i] && cr[i] == err_row && cc[i] == {err_col, b[2:0]}) masked = 1;
            if (err_bits[b] && !masked && !found) begin found = 1; nb = b[2:0]; end
        end
        nc = {err_col, nb};
        rcnt = 1; ccnt = 1;
        for (i = 0; i < K; i = i + 1) begin
            if (cv[i] && cr[i] == err_row) rcnt = rcnt + 1;
            if (cv[i] && cc[i] == nc)      ccnt = ccnt + 1;
        end
        rf = 0; rfree = 0; for (i = 0; i < SR; i = i + 1) if (!rf && !rvalid[i]) begin rf = 1; rfree[i] = 1; end
        cf = 0; cfree = 0; for (i = 0; i < SC; i = i + 1) if (!cf && !cvalid[i]) begin cf = 1; cfree[i] = 1; end
        kf = 0; kfree = 0; for (i = 0; i < K; i = i + 1) if (!kf && !cv[i]) begin kf = 1; kfree[i] = 1; end
    end

    // ---- analyze (after test 1): greedy over the remaining entries ----
    reg [3:0] erc [0:K-1], ecc [0:K-1];
    reg pick, pick_row; reg [3:0] best; reg [ROWB-1:0] prow_sel; reg [BCW-1:0] pcol_sel;
    always @(*) begin
        for (i = 0; i < K; i = i + 1) begin
            erc[i] = 0; ecc[i] = 0;
            for (j = 0; j < K; j = j + 1) begin
                if (cv[i] && cv[j] && cr[j] == cr[i]) erc[i] = erc[i] + 1;
                if (cv[i] && cv[j] && cc[j] == cc[i]) ecc[i] = ecc[i] + 1;
            end
        end
        pick_row = 0; best = 0; prow_sel = 0; pcol_sel = 0;
        // TODO C: greedy. For each valid entry i: if a spare row is free (rf) and erc[i] > best, choose its row
        //   (best = erc[i], pick_row = 1, prow_sel = cr[i]); then if a spare column is free (cf) and ecc[i] > best,
        //   choose its column (best = ecc[i], pick_row = 0, pcol_sel = cc[i]). Rows are checked first, so they win ties.
        for (i = 0; i < K; i = i + 1) if (cv[i]) begin
            if (rf && (erc[i] > best || (erc[i] == best && !pick_row))) begin
                best = erc[i]; pick_row = 1; prow_sel = cr[i];
            end
            if (cf && ecc[i] > best) begin best = ecc[i]; pick_row = 0; pcol_sel = cc[i]; end
        end
        pick = (best != 0);
    end

    task alloc_row(input [ROWB-1:0] r);
        begin
            for (i = 0; i < SR; i = i + 1) if (rfree[i]) begin rvalid[i] <= 1'b1; rrow[i*ROWB +: ROWB] <= r; end
            for (i = 0; i < K; i = i + 1) if (cv[i] && cr[i] == r) cv[i] <= 1'b0;
        end
    endtask
    task alloc_col(input [BCW-1:0] c);
        begin
            for (i = 0; i < SC; i = i + 1) if (cfree[i]) begin cvalid[i] <= 1'b1; ccol[i*BCW +: BCW] <= c; end
            for (i = 0; i < K; i = i + 1) if (cv[i] && cc[i] == c) cv[i] <= 1'b0;
        end
    endtask

    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin rvalid <= 0; rrow <= 0; cvalid <= 0; ccol <= 0; cv <= 0; unrepairable <= 0; busy <= 0; end
        else if (clear) begin rvalid <= 0; rrow <= 0; cvalid <= 0; ccol <= 0; cv <= 0; unrepairable <= 0; busy <= 0; end
        else if (busy) begin
            if (cv == 0 || unrepairable) busy <= 1'b0;
            else if (!pick) begin unrepairable <= 1'b1; busy <= 1'b0; end
            else if (pick_row) alloc_row(prow_sel);
            else alloc_col(pcol_sel);
        end
        else if (analyze) busy <= 1'b1;
        else if (en && err && found && !unrepairable) begin
            // TODO B: the new fault (err_row, nc):
            //   rcnt > cleft  -> must-repair row:    if (rf) alloc_row(err_row); else unrepairable <= 1
            //   ccnt > rleft  -> must-repair column: if (cf) alloc_col(nc);      else unrepairable <= 1
            //   otherwise     -> store it in the free table entry (kfree one-hot): cv <= 1, cr <= err_row, cc <= nc;
            //                    no free entry (kf = 0) -> unrepairable <= 1
            if (rcnt > cleft) begin
                if (rf) alloc_row(err_row); else unrepairable <= 1;
            end else if (ccnt > rleft) begin
                if (cf) alloc_col(nc); else unrepairable <= 1;
            end else if (kf) begin
                for (i = 0; i < K; i = i + 1) if (kfree[i]) begin
                    cv[i] <= 1; cr[i] <= err_row; cc[i] <= nc;
                end
            end else unrepairable <= 1;
        end
endmodule
