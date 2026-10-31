// repair_props.sv : formal properties of the repair logic (bira + repair_remap), all inputs free
//   the solver may raise err on any row in any cycle, clear at any time, and look up any two rows
//   prove (k-induction): the properties hold in every reachable state, not just the first N cycles
module repair_props #(parameter ROWB = 4, SPARES = 2) (
    input clk, rst_n,
    input clear, en, err,
    input [ROWB-1:0] err_row,
    input remap_en,
    input [ROWB-1:0] ra, rb               // two rows looked up at the same time
);
    wire [SPARES-1:0] valid;
    wire [SPARES*ROWB-1:0] rows;
    wire unrep;
    wire [ROWB:0] pa, pb;
    bira #(.ROWB(ROWB), .SPARES(SPARES)) u_bira (.clk(clk), .rst_n(rst_n), .clear(clear), .en(en), .err(err),
        .err_row(err_row), .valid(valid), .rows(rows), .unrepairable(unrep));
    repair_remap #(.ROWB(ROWB), .SPARES(SPARES)) u_ra (.en(remap_en), .row(ra), .valid(valid), .rows(rows), .prow(pa));
    repair_remap #(.ROWB(ROWB), .SPARES(SPARES)) u_rb (.en(remap_en), .row(rb), .valid(valid), .rows(rows), .prow(pb));

    reg f_init = 1;
    always @(posedge clk) f_init <= 0;
    always @(*) assume(rst_n == !f_init);           // reset in the first cycle only

    // was row r recorded?
    function in_table(input [ROWB-1:0] r);
        integer i;
        begin
            in_table = 1'b0;
            for (i = 0; i < SPARES; i = i + 1) if (valid[i] && rows[i*ROWB +: ROWB] == r) in_table = 1'b1;
        end
    endfunction

    // table: no row stored twice, entries fill from index 0 up, "unrepairable" only when the table is full
    //   (one assertion per pair of entries; unlabelled, because yosys would give every copy the same label)
    genvar gi, gj;
    generate for (gi = 0; gi < SPARES; gi = gi + 1) begin : g_entry
        for (gj = gi + 1; gj < SPARES; gj = gj + 1) begin : g_pair
            always @(*) if (!f_init)
                assert(!(valid[gi] && valid[gj]) || rows[gi*ROWB +: ROWB] != rows[gj*ROWB +: ROWB]);
        end
        if (gi + 1 < SPARES) begin : g_order
            always @(*) if (!f_init) assert(!valid[gi + 1] || valid[gi]);
        end
    end endgenerate
    always @(*) if (!f_init) begin
        a_unrep_full: assert(!unrep || &valid);
        // remap: two different rows never share a physical row (no data aliasing after repair)
        a_injective: assert(ra == rb || pa != pb);
        // remap: a spare is used only for the row stored in its entry; every other row maps to itself
        a_spare_ok: assert(!pa[ROWB] || (remap_en && in_table(ra) && valid[pa[ROWB-1:0]]
                                         && rows[pa[ROWB-1:0]*ROWB +: ROWB] == ra));
        a_identity: assert(pa[ROWB] || (pa[ROWB-1:0] == ra && !(remap_en && in_table(ra))));
    end

    // completeness: after an error is recorded, its row is repaired or the memory is marked unrepairable
    reg f_rec = 0; reg [ROWB-1:0] f_row = 0;
    always @(posedge clk) begin f_rec <= rst_n && en && err && !clear; f_row <= err_row; end
    always @(*) if (!f_init && f_rec && !clear) a_recorded: assert(in_table(f_row) || unrep);

    always @(*) if (!f_init) begin
        c_full:    cover(&valid && !unrep);
        c_unrep:   cover(unrep);
        c_spare1:  cover(remap_en && pa == (1 << ROWB) + 1);
    end
endmodule
