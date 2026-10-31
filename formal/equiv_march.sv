// equiv_march.sv : equivalence check (miter): the programmable MBIST running March C- (alg = 2) must behave
//   exactly like the hand-written March C- controller from the cache project, cycle by cycle,
//   for any start pulses and ANY memory read data (so every possible fault behaviour is covered)
module equiv_march #(parameter AW = 3, DW = 2) (
    input clk, rst_n, start,
    input [DW-1:0] mem_rdata            // free: the solver plays every possible (faulty) memory
);
    wire d1, f1, we1, e1, d2, f2, we2, re2, e2;
    wire [AW-1:0] a1, ea1, a2, ea2;
    wire [DW-1:0] wd1, wd2;
    mbist_march #(.AW(AW), .DW(DW)) u_ref (.clk(clk), .rst_n(rst_n), .start(start), .done(d1), .fail(f1),
        .mem_we(we1), .mem_addr(a1), .mem_wdata(wd1), .mem_rdata(mem_rdata), .err(e1), .err_addr(ea1));
    mbist_prog #(.AW(AW), .DW(DW)) u_new (.clk(clk), .rst_n(rst_n), .start(start), .alg(2'd2), .done(d2), .fail(f2),
        .mem_we(we2), .mem_re(re2), .mem_addr(a2), .mem_wdata(wd2), .mem_rdata(mem_rdata), .err(e2), .err_addr(ea2));

    reg f_init = 1;
    always @(posedge clk) f_init <= 0;
    always @(*) assume(rst_n == !f_init);           // reset in the first cycle only

    always @(*) if (!f_init) begin
        a_done:  assert(d1 == d2);
        a_fail:  assert(f1 == f2);
        a_we:    assert(we1 == we2);
        a_addr:  assert(a1 == a2);
        a_wdata: assert(!we1 || wd1 == wd2);        // write data only matters when writing
        a_err:   assert(e1 == e2);
    end
    always @(*) if (!f_init) begin
        c_done:  cover(d1 && d2);                   // a complete March C- run is reachable
        c_fail:  cover(d2 && f2);
    end
endmodule
