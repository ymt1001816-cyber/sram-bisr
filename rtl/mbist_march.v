`timescale 1ns/1ps
// mbist_march.v : March C- memory BIST controller (reused from the cache project, plus err / err_addr for repair)
// Author: Meiyu Kuo
//
// March C- (10N operations, N = number of words):
//   M0 ⇕(w0)   M1 ⇑(r0,w1)   M2 ⇑(r1,w0)   M3 ⇓(r0,w1)   M4 ⇓(r1,w0)   M5 ⇕(r0)
//   ⇑ = address 0 -> N-1, ⇓ = address N-1 -> 0, ⇕ = either order
//   "0" = all-zero word, "1" = all-one word (word-oriented memory: background 0/1 for every bit)
//
// Interface:
//   start   : 1-cycle pulse, starts the test
//   done    : goes to 1 when M5 finishes and stays 1
//   fail    : goes to 1 at the first wrong read and stays 1
//   err     : 1 in every cycle whose read is wrong (not sticky), err_addr = that address (for redundancy analysis)
//   mem_*   : drive the memory; mem_rdata is combinational (valid in the same cycle as mem_addr)
//
// Hints:
//   - one memory operation per clock cycle -> the whole test takes about 10 x 256 = 2,560 cycles
//   - state you need: which element (M0..M5), the address, and inside M1-M4 whether this is the read or the write
//   - for each element decide: direction (up/down), read value, write value, has a read?, has a write?
//   - compare mem_rdata with the expected value in the same cycle as the read
module mbist_march #(parameter AW = 8, DW = 32) (
    input               clk,
    input               rst_n,
    input               start,
    output reg          done,
    output reg          fail,
    output              mem_we,
    output     [AW-1:0] mem_addr,
    output     [DW-1:0] mem_wdata,
    input      [DW-1:0] mem_rdata,
    output              err,
    output     [AW-1:0] err_addr
);
    localparam M0 = 3'd0, M1 = 3'd1, M2 = 3'd2,
               M3 = 3'd3, M4 = 3'd4, M5 = 3'd5;
    localparam [AW-1:0] LAST_ADDR = {AW{1'b1}};
    reg [2:0] el;
    reg [AW-1:0] addr;
    reg phase; // M1-M4: read first (0), then write (1) at the same address
    reg running;

    wire down = (el == M3 || el == M4);
    wire paired = (el >= M1 && el <= M4);
    wire do_read = running && (el == M5 || (paired && !phase));
    wire expected_one = (el == M2 || el == M4);
    wire write_one = (el == M1 || el == M3);
    wire last_word = down ? (addr == 0) : (addr == LAST_ADDR);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            el <= M0;
            addr <= 0;
            phase <= 0;
            running <= 0;
            done <= 0;
            fail <= 0;
        end else if (!running) begin
            if (start) begin
                el <= M0;
                addr <= 0;
                phase <= 0;
                running <= 1;
                done <= 0;
                fail <= 0; // clear sticky results only when a new test starts
            end
        end else begin
            if (do_read && mem_rdata !== {DW{expected_one}})
                fail <= 1; // keep testing after a mismatch; retain the first failure

            if (paired && !phase) begin
                phase <= 1; // do not advance until the following write completes
            end else begin
                phase <= 0;
                if (last_word) begin
                    if (el == M5) begin
                        running <= 0;
                        done <= 1;
                    end else begin
                        el <= el + 1'b1;
                        // M3 and M4 descend; all other elements start at zero.
                        addr <= (el == M2 || el == M3) ? LAST_ADDR : {AW{1'b0}};
                    end
                end else begin
                    addr <= down ? addr - 1'b1 : addr + 1'b1;
                end
            end
        end
    end

    assign mem_we = rst_n && running && (el == M0 || (paired && phase));
    assign mem_addr = addr;
    assign mem_wdata = {DW{write_one}};

    // TODO 1: err = this cycle is a read AND the data is wrong (same compare as the fail flag above, but not sticky)
    //         err_addr = the address being read
    assign err = do_read && (mem_rdata !== {DW{expected_one}});
    assign err_addr = addr;

endmodule
