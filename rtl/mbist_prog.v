`timescale 1ns/1ps
// mbist_prog.v : programmable March memory BIST: one engine runs any March algorithm stored in a small table
// Author: Meiyu Kuo
//   alg selects the algorithm: 0 MATS+ (5N), 1 March X (6N), 2 March C- (10N), 3 March SS (22N)
//   same handshake as mbist_march.v (start / done / fail / err / err_addr); mem_re marks read cycles
//
//   An algorithm is a list of up to 8 march ELEMENTS. Each element visits every address (up or down) and does
//   1..5 OPERATIONS at each address before moving on, e.g. March C- element 1 = up(r0, w1):
//   at address 0: read expect 0, write 1; then address 1: read expect 0, write 1; ...
module mbist_prog #(parameter AW = 6, DW = 8) (
    input               clk, rst_n,
    input               start,
    input      [1:0]    alg,          // 0 MATS+, 1 March X, 2 March C-, 3 March SS
    output reg          done,
    output reg          fail,
    output              mem_we,
    output              mem_re,
    output     [AW-1:0] mem_addr,
    output     [DW-1:0] mem_wdata,
    input      [DW-1:0] mem_rdata,
    output              err,
    output     [AW-1:0] err_addr
);
    // element = {dir, nops[2:0], op4, op3, op2, op1, op0}; op = {write, value}; nops = 0 ends the algorithm
    localparam R0 = 2'b00, R1 = 2'b01, W0 = 2'b10, W1 = 2'b11, UP = 1'b0, DN = 1'b1;
    function [13:0] elem(input [1:0] a, input [2:0] e);
        begin
            elem = 14'd0;
            case (a)
            2'd0: case (e)   // MATS+ 5N: (w0) up(r0,w1) dn(r1,w0)
                3'd0: elem = {UP, 3'd1, 8'd0, W0};
                3'd1: elem = {UP, 3'd2, 6'd0, W1, R0};
                3'd2: elem = {DN, 3'd2, 6'd0, W0, R1};
                default: ;
                endcase
            2'd1: case (e)   // March X 6N: (w0) up(r0,w1) dn(r1,w0) (r0)
                3'd0: elem = {UP, 3'd1, 8'd0, W0};
                3'd1: elem = {UP, 3'd2, 6'd0, W1, R0};
                3'd2: elem = {DN, 3'd2, 6'd0, W0, R1};
                3'd3: elem = {UP, 3'd1, 8'd0, R0};
                default: ;
                endcase
            2'd2: case (e)   // March C- 10N
                3'd0: elem = {UP, 3'd1, 8'd0, W0};
                3'd1: elem = {UP, 3'd2, 6'd0, W1, R0};
                3'd2: elem = {UP, 3'd2, 6'd0, W0, R1};
                3'd3: elem = {DN, 3'd2, 6'd0, W1, R0};
                3'd4: elem = {DN, 3'd2, 6'd0, W0, R1};
                3'd5: elem = {UP, 3'd1, 8'd0, R0};
                default: ;
                endcase
            default: case (e) // March SS 22N
                // TODO 1: March SS  =  (w0) up(r0,r0,w0,r0,w1) up(r1,r1,w1,r1,w0) dn(r0,r0,w0,r0,w1) dn(r1,r1,w1,r1,w0) (r0)
                //   op0 is the FIRST operation and sits in the LOWEST bits: {dir, nops, op4, op3, op2, op1, op0}
                //   look at how March C- element 1 up(r0,w1) is written above: {UP, 3'd2, 6'd0, W1, R0}
                3'd0: elem = {UP, 3'd1, 8'd0, W0};
                3'd1: elem = {UP, 3'd5, W1, R0, W0, R0, R0};
                3'd2: elem = {UP, 3'd5, W0, R1, W1, R1, R1};
                3'd3: elem = {DN, 3'd5, W1, R0, W0, R0, R0};
                3'd4: elem = {DN, 3'd5, W0, R1, W1, R1, R1};
                3'd5: elem = {UP, 3'd1, 8'd0, R0};
                default: ;
                endcase
            endcase
        end
    endfunction

    localparam [AW-1:0] LAST = {AW{1'b1}};
    reg running;
    reg [2:0] el, op;                    // current element, current operation inside the element
    reg [AW-1:0] addr;
    wire [13:0] e    = elem(alg, el);              // current element
    /* verilator lint_off UNUSEDSIGNAL */          // only dir and nops of the next element are needed
    wire [13:0] e_nx = elem(alg, el + 3'd1);       // next element (its nops = 0 means the algorithm ends)
    /* verilator lint_on UNUSEDSIGNAL */
    wire        dir  = e[13];
    wire [2:0]  nops = e[12:10];
    wire [1:0]  code = e[op*2 +: 2];               // current operation: code[1] = write, code[0] = value
    wire        last_op   = (op == nops - 3'd1);
    wire        last_addr = dir ? (addr == 0) : (addr == LAST);

    // TODO 2: memory interface (one operation per cycle while running)
    //   mem_we = running and the operation is a write;  mem_re = running and it is a read
    //   mem_wdata = the value repeated DW times (all-0 or all-1 word)
    //   err = a read whose data is not the expected all-0 / all-1 word (use !== like in mbist_march.v)
    assign mem_we    = running && code[1];
    assign mem_re    = running && !code[1];
    assign mem_addr  = addr;
    assign mem_wdata = {DW{code[0]}};
    assign err       = mem_re && (mem_rdata !== {DW{code[0]}});
    assign err_addr  = addr;

    // TODO 3: the sequencer (start, done and fail are already written, like in mbist_march.v)
    //   each cycle while running:
    //     - not the last operation of this element      -> next operation
    //     - last operation, not the last address        -> op back to 0, next address (up or down by dir)
    //     - last operation, last address:
    //         next element has nops = 0 (or el is 7)    -> stop: running <= 0, done <= 1
    //         otherwise                                 -> next element, addr = its start (LAST if it goes down)
    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin running <= 0; el <= 0; op <= 0; addr <= 0; done <= 0; fail <= 0; end
        else if (!running) begin
            if (start) begin running <= 1; el <= 0; op <= 0; addr <= 0; done <= 0; fail <= 0; end
        end else begin
            if (err) fail <= 1;
            if (!last_op) op <= op + 3'd1;
            else begin
                op <= 0;
                if (!last_addr) addr <= dir ? addr - 1'b1 : addr + 1'b1;
                else if (el == 3'd7 || e_nx[12:10] == 0) begin
                    running <= 0;
                    done <= 1;
                end else begin
                    el <= el + 3'd1;
                    addr <= e_nx[13] ? LAST : {AW{1'b0}};
                end
            end
        end
endmodule
