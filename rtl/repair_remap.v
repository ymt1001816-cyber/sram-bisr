`timescale 1ns/1ps
// repair_remap.v : logical row -> physical row (the actual "repair": a bad row is never used again)
// Author: Meiyu Kuo
//   physical rows 0 .. 2**ROWB-1 are the normal rows, 2**ROWB + i is spare row i
//   if en and entry i of the BIRA table is valid and holds this row -> use spare row i, otherwise the row itself
module repair_remap #(parameter ROWB = 4, SPARES = 2) (
    input                         en,
    input      [ROWB-1:0]         row,
    input      [SPARES-1:0]       valid,
    input      [SPARES*ROWB-1:0]  rows,
    output reg [ROWB:0]           prow
);
    localparam [ROWB:0] SPARE0 = 1 << ROWB;   // physical row of spare 0
    integer i;
    // TODO 3: default prow = {1'b0, row}; then if en, loop over the entries and replace it on a match
    //   (spare i is SPARE0 + i[ROWB:0])
    always @(*) begin
        prow = {1'b0, row};
        if (en)
            for (i = 0; i < SPARES; i = i + 1)
                if (valid[i] && rows[i*ROWB +: ROWB] == row)
                    prow = SPARE0 + i[ROWB:0];
    end
endmodule
