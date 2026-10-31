`timescale 1ns/1ps
// mbist_cov_top.v : the programmable MBIST driving the fault-injectable SRAM directly (no repair),
//   for measuring which faults each March algorithm detects
module mbist_cov_top #(parameter ROWB = 4, COLB = 2, DW = 8) (
    input clk, rst_n, start,
    input [1:0] alg,
    output done, fail
);
    localparam AW = ROWB + COLB;
    wire we, re, err;
    wire [AW-1:0] addr, err_addr;
    wire [DW-1:0] wdata, rdata;
    mbist_prog #(.AW(AW), .DW(DW)) u_mbist (.clk(clk), .rst_n(rst_n), .start(start), .alg(alg), .done(done),
        .fail(fail), .mem_we(we), .mem_re(re), .mem_addr(addr), .mem_wdata(wdata), .mem_rdata(rdata),
        .err(err), .err_addr(err_addr));
    sram_array #(.ROWB(ROWB), .COLB(COLB), .DW(DW)) u_mem (.clk(clk), .we(we), .re(re),
        .prow({1'b0, addr[AW-1:COLB]}), .col(addr[COLB-1:0]), .wdata(wdata), .rdata(rdata));
endmodule
