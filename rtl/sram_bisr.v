`timescale 1ns/1ps
// sram_bisr.v : SRAM with built-in self-repair (BISR)
// Author: Meiyu Kuo
//   bist_start runs:  test 1 (March C-, BIRA records bad rows)  ->  repair (remap bad rows to spares)
//                     ->  test 2 (March C- again through the remap: checks the spares and the repair)
//   bist_status: PASS (no fault), REPAIRED (faults, all fixed), FAIL (too many bad rows, or test 2 fails)
//   while the self-test runs it owns the memory; otherwise the normal port (we / addr / wdata / rdata) does
module sram_bisr #(
    parameter ROWB = 4, COLB = 2, DW = 8, SPARES = 2
) (
    input                     clk, rst_n,
    input                     bist_start,
    output reg                bist_done,
    output reg [1:0]          bist_status,
    output     [SPARES-1:0]   spares_used,
    input                     we,
    input  [ROWB+COLB-1:0]    addr,
    input  [DW-1:0]           wdata,
    output [DW-1:0]           rdata
);
    localparam AW = ROWB + COLB;
    localparam S_NONE = 2'd0, S_PASS = 2'd1, S_REPAIRED = 2'd2, S_FAIL = 2'd3;
    localparam IDLE = 3'd0, T1 = 3'd1, T1_WAIT = 3'd2, T2 = 3'd3, T2_WAIT = 3'd4;

    reg  [2:0] state;
    reg        m_start;
    wire       m_done, m_fail, m_we, m_err;
    wire [AW-1:0] m_addr;
    /* verilator lint_off UNUSEDSIGNAL */   // repair is per row: the column bits of the failing address are not needed
    wire [AW-1:0] m_err_addr;
    /* verilator lint_on UNUSEDSIGNAL */
    wire [DW-1:0] m_wdata;
    wire [SPARES-1:0] valid;
    wire [SPARES*ROWB-1:0] rows;
    wire unrep;
    wire bist_active = (state != IDLE);
    reg  remap_en;

    wire          a_we   = bist_active ? m_we    : we;
    wire [AW-1:0] a_addr = bist_active ? m_addr  : addr;
    wire [DW-1:0] a_wd   = bist_active ? m_wdata : wdata;
    wire [ROWB:0] prow;
    wire [DW-1:0] a_rd;

    mbist_march #(.AW(AW), .DW(DW)) u_mbist (.clk(clk), .rst_n(rst_n), .start(m_start), .done(m_done), .fail(m_fail),
        .mem_we(m_we), .mem_addr(m_addr), .mem_wdata(m_wdata), .mem_rdata(a_rd), .err(m_err), .err_addr(m_err_addr));
    bira #(.ROWB(ROWB), .SPARES(SPARES)) u_bira (.clk(clk), .rst_n(rst_n), .clear(bist_start && !bist_active),
        .en(state == T1 || state == T1_WAIT), .err(m_err), .err_row(m_err_addr[AW-1:COLB]),
        .valid(valid), .rows(rows), .unrepairable(unrep));
    repair_remap #(.ROWB(ROWB), .SPARES(SPARES)) u_remap (.en(remap_en), .row(a_addr[AW-1:COLB]),
        .valid(valid), .rows(rows), .prow(prow));
    sram_array #(.ROWB(ROWB), .COLB(COLB), .DW(DW), .SPARES(SPARES)) u_mem (.clk(clk), .we(a_we),
        .prow(prow), .col(a_addr[COLB-1:0]), .wdata(a_wd), .rdata(a_rd));
    assign rdata = a_rd;
    assign spares_used = valid;

    // TODO 4: the BISR state machine
    //   every cycle: m_start <= 0 (a 1-cycle pulse when you set it)
    //   IDLE    : on bist_start -> T1, m_start <= 1, remap_en <= 0, bist_done <= 0, bist_status <= S_NONE
    //   T1      : one wait cycle (mbist's done is still 1 from the last run) -> T1_WAIT
    //   T1_WAIT : when m_done:
    //               no fail            -> back to IDLE, done, S_PASS, remap_en <= 1
    //               fail, unrep        -> back to IDLE, done, S_FAIL
    //               fail, repairable   -> T2, m_start <= 1, remap_en <= 1 (test 2 goes through the repair)
    //   T2      : one wait cycle -> T2_WAIT
    //   T2_WAIT : when m_done -> IDLE, done, S_REPAIRED if no fail, otherwise S_FAIL
    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            state <= IDLE; m_start <= 0; remap_en <= 0; bist_done <= 0; bist_status <= S_NONE;
        end else begin
            m_start <= 0;
            case (state)
                IDLE: if (bist_start) begin
                    state <= T1;
                    m_start <= 1;
                    remap_en <= 0; // collect all bad rows before enabling any repair
                    bist_done <= 0;
                    bist_status <= S_NONE;
                end
                T1: state <= T1_WAIT; // allow MBIST to clear its previous sticky done
                T1_WAIT: if (m_done) begin
                    if (!m_fail) begin
                        state <= IDLE;
                        bist_done <= 1;
                        bist_status <= S_PASS;
                        remap_en <= 1;
                    end else if (unrep) begin
                        state <= IDLE;
                        bist_done <= 1;
                        bist_status <= S_FAIL;
                    end else begin
                        state <= T2;
                        m_start <= 1;
                        remap_en <= 1; // verify the replacement rows with a second complete March
                    end
                end
                T2: state <= T2_WAIT;
                T2_WAIT: if (m_done) begin
                    state <= IDLE;
                    bist_done <= 1;
                    bist_status <= m_fail ? S_FAIL : S_REPAIRED;
                end
                default: state <= IDLE;
            endcase
        end
endmodule
