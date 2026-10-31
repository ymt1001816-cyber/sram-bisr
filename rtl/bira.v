`timescale 1ns/1ps
// bira.v : built-in redundancy analysis (BIRA) for row repair
// Author: Meiyu Kuo
//   During the first test, every wrong read reports its row (err, err_row). BIRA keeps a small table of
//   SPARES entries {valid, row}: the rows that will be replaced by spare rows.
//     - row already in the table      -> nothing to do (a bad row fails many reads)
//     - new row and a free entry      -> store it in the FIRST free entry (lowest index)
//     - new row and no free entry     -> unrepairable = 1 (more bad rows than spares)
//   The table is flattened into vectors: entry i = valid[i], rows[i*ROWB +: ROWB]
module bira #(parameter ROWB = 4, SPARES = 2) (
    input                         clk, rst_n,
    input                         clear,          // start of a new self-test: empty the table
    input                         en,             // record errors only while enabled (first test)
    input                         err,
    input      [ROWB-1:0]         err_row,
    output reg [SPARES-1:0]       valid,
    output reg [SPARES*ROWB-1:0]  rows,
    output reg                    unrepairable
);
    integer i;
    reg hit, found;                  // hit: err_row is already in the table; found: there is a free entry
    reg [SPARES-1:0] alloc;          // one-hot: the first free entry

    // TODO 2a (combinational): compute hit, found and alloc with a for loop over the entries
    //   start with all three at 0; for each entry i:
    //     - valid and rows[i*ROWB +: ROWB] == err_row  -> hit = 1
    //     - not valid and nothing found yet            -> alloc[i] = 1, found = 1
    always @(*) begin
        hit = 1'b0; found = 1'b0; alloc = {SPARES{1'b0}};
        for (integer j = 0; j < SPARES; j = j + 1) begin
            if (valid[j] && rows[j*ROWB +: ROWB] == err_row) hit = 1;
            if (!valid[j] && !found) begin
                alloc[j] = 1;
                found = 1;
            end
        end
    end

    // TODO 2b (sequential): on en && err && !hit:
    //   - found     -> set the valid bit of the alloc entry, store err_row in that entry
    //   - not found -> unrepairable <= 1
    //   (use <= here; a for loop can pick the entry: if (alloc[i]) rows[i*ROWB +: ROWB] <= err_row;)
    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin valid <= 0; rows <= 0; unrepairable <= 0; end
        else if (clear) begin valid <= 0; rows <= 0; unrepairable <= 0; end
        else if (en && err && !hit) begin
            if (found) begin
                valid <= valid | alloc;
                for (i = 0; i < SPARES; i = i + 1)
                    if (alloc[i]) rows[i*ROWB +: ROWB] <= err_row;
            end else unrepairable <= 1;
        end
endmodule
