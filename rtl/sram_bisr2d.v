`timescale 1ns/1ps
// sram_bisr2d.v : SRAM self-repair with spare rows AND spare bit-columns
// Author: Meiyu Kuo
//   like sram_bisr.v, plus: 2D redundancy analysis (bira2d) between test 1 and test 2, and column repair:
//   a replaced bit-column is written to / read from its spare column instead of the array
module sram_bisr2d #(
    parameter ROWB = 4, COLB = 2, DW = 8, SR = 2, SC = 2, K = 8
) (
    input                     clk, rst_n,
    input                     bist_start,
    input      [1:0]          alg,
    output reg                bist_done,
    output reg [1:0]          bist_status,
    output     [SR-1:0]       rows_used,
    output     [SC-1:0]       cols_used,
    input                     we,
    input  [ROWB+COLB-1:0]    addr,
    input  [DW-1:0]           wdata,
    output [DW-1:0]           rdata
);
    localparam AW = ROWB + COLB, BCW = COLB + 3;
    localparam S_NONE = 2'd0, S_PASS = 2'd1, S_REPAIRED = 2'd2, S_FAIL = 2'd3;
    localparam IDLE = 3'd0, T1 = 3'd1, T1_WAIT = 3'd2, RA = 3'd3, RA_WAIT = 3'd4, T2 = 3'd5, T2_WAIT = 3'd6;

    reg  [2:0] state;
    reg        m_start, ra_start, remap_en;
    wire       m_done, m_fail, m_we, m_re, m_err;
    wire [AW-1:0] m_addr;
    /* verilator lint_off UNUSEDSIGNAL */
    wire [AW-1:0] m_err_addr;
    /* verilator lint_on UNUSEDSIGNAL */
    wire [DW-1:0] m_wdata;
    wire [SR-1:0] rvalid; wire [SR*ROWB-1:0] rrow;
    wire [SC-1:0] cvalid; wire [SC*BCW-1:0] ccol;
    wire unrep, ra_busy;
    wire bist_active = (state != IDLE);

    wire          a_we   = bist_active ? m_we    : we;
    wire [AW-1:0] a_addr = bist_active ? m_addr  : addr;
    wire [DW-1:0] a_wd   = bist_active ? m_wdata : wdata;
    wire [COLB-1:0] a_col = a_addr[COLB-1:0];
    wire [ROWB:0] prow;
    wire [DW-1:0] raw_rd;
    reg  [DW-1:0] a_rd;
    reg  [SC-1:0] sc_we, sc_wd;
    wire [SC-1:0] sc_rd;

    mbist_prog #(.AW(AW), .DW(DW)) u_mbist (.clk(clk), .rst_n(rst_n), .start(m_start), .alg(alg), .done(m_done),
        .fail(m_fail), .mem_we(m_we), .mem_re(m_re), .mem_addr(m_addr), .mem_wdata(m_wdata), .mem_rdata(a_rd),
        .err(m_err), .err_addr(m_err_addr));
    bira2d #(.ROWB(ROWB), .COLB(COLB), .DW(DW), .SR(SR), .SC(SC), .K(K)) u_bira (.clk(clk), .rst_n(rst_n),
        .clear(bist_start && !bist_active), .en(state == T1 || state == T1_WAIT), .err(m_err),
        .err_row(m_err_addr[AW-1:COLB]), .err_col(m_err_addr[COLB-1:0]), .err_bits(a_rd ^ m_wdata),
        .analyze(ra_start), .busy(ra_busy), .rvalid(rvalid), .rrow(rrow), .cvalid(cvalid), .ccol(ccol),
        .unrepairable(unrep));
    repair_remap #(.ROWB(ROWB), .SPARES(SR)) u_remap (.en(remap_en), .row(a_addr[AW-1:COLB]),
        .valid(rvalid), .rows(rrow), .prow(prow));
    sram_array #(.ROWB(ROWB), .COLB(COLB), .DW(DW), .SPARES(SR), .SCOLS(SC)) u_mem (.clk(clk), .we(a_we),
        .re(bist_active && m_re), .prow(prow), .col(a_col), .wdata(a_wd), .rdata(raw_rd),
        .sc_we(sc_we), .sc_wdata(sc_wd), .sc_rdata(sc_rd));

    // column repair: the replaced bit is written to / read from its spare column instead
    integer k;
    always @(*) begin
        a_rd = raw_rd; sc_we = 0; sc_wd = 0;
        // TODO D: column steering. For each spare column k: if remap_en, cvalid[k], and its word column
        //   ccol[k*BCW+3 +: COLB] equals a_col, then bit b = ccol[k*BCW +: 3] of this word lives in spare column k:
        //   sc_we[k] = 1, sc_wd[k] = a_wd[b] (write the bit to the spare), and a_rd[b] = sc_rd[k] (read it back)
        for (k = 0; k < SC; k = k + 1)
            if (remap_en && cvalid[k] && ccol[k*BCW+3 +: COLB] == a_col) begin
                sc_we[k] = 1;
                sc_wd[k] = a_wd[ccol[k*BCW +: 3]];
                a_rd[ccol[k*BCW +: 3]] = sc_rd[k];
            end
    end
    assign rdata = a_rd;
    assign rows_used = rvalid;
    assign cols_used = cvalid;

    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            state <= IDLE; m_start <= 0; ra_start <= 0; remap_en <= 0; bist_done <= 0; bist_status <= S_NONE;
        end else begin
            m_start <= 0; ra_start <= 0;
            case (state)
                IDLE: if (bist_start) begin
                    state <= T1; m_start <= 1; remap_en <= 0; bist_done <= 0; bist_status <= S_NONE;
                end
                T1: state <= T1_WAIT;
                T1_WAIT: if (m_done) begin
                    if (!m_fail) begin state <= IDLE; bist_done <= 1; bist_status <= S_PASS; remap_en <= 1; end
                    // TODO E: on a failure, do not decide yet: start the analysis (state <= RA, ra_start <= 1)
                    else begin state <= RA; ra_start <= 1; end
                end
                // TODO E (continued):
                //   RA      : one wait cycle (busy is raised on the next edge) -> RA_WAIT
                //   RA_WAIT : when !ra_busy: unrep -> IDLE, done, S_FAIL; otherwise -> T2, m_start <= 1, remap_en <= 1
                //   T2, T2_WAIT : the same as in sram_bisr.v
                RA: state <= RA_WAIT;
                RA_WAIT: if (!ra_busy) begin
                    if (unrep) begin state <= IDLE; bist_done <= 1; bist_status <= S_FAIL; end
                    else begin state <= T2; m_start <= 1; remap_en <= 1; end
                end
                T2: state <= T2_WAIT;
                T2_WAIT: if (m_done) begin
                    state <= IDLE; bist_done <= 1;
                    bist_status <= m_fail ? S_FAIL : S_REPAIRED;
                end
                default: state <= IDLE;
            endcase
        end
endmodule
