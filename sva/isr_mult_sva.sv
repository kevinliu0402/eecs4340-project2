// Assertions for the Project 2 integer square root and its pipelined multiplier.
//
// mult is a chain of `STAGES registers. start goes in one end, done comes
// out the other end `STAGES clocks later, and the low 64 bits of the product
// come out on that same clock. ISR pulses start once per bit, so done is a
// one-cycle pulse. The square-root result is checked only on the cycle ISR's
// own done is high, against stored_value (the value captured at reset), not
// against the value port, which the core is allowed to ignore after that.

`include "mult_defs.svh"

module mult_sva #(
    parameter STAGES = 8
) (
    input              clock,
    input              reset,
    input              start,
    input              done,
    input      [63:0]  mcand,
    input      [63:0]  mplier,
    input      [63:0]  product
);
    // [*STAGES] occupies the start cycle and the STAGES-1 cycles after it,
    // so done is required on cycle STAGES and forbidden before that.
    // A level `start |-> ##STAGES done` would allow a done that arrived early
    // and was still high; the repetition forbids that.
    a_done_latency: assert property (
        @(posedge clock) disable iff (reset)
        start |-> (!done)[*STAGES] ##1 done
    ) else $error("mult.done was not exactly %0d cycles after start", STAGES);

    a_done_only_from_start: assert property (
        @(posedge clock) disable iff (reset)
        done |-> $past(start, STAGES)
    ) else $error("mult.done with no start %0d cycles earlier", STAGES);

    // 64'(a * b) is the low 64 bits, which is the contract in mult.sv.
    a_product: assert property (
        @(posedge clock) disable iff (reset)
        start |-> ##STAGES (product == 64'($past(mcand, STAGES) * $past(mplier, STAGES)))
    ) else $error("mult.product was not the low 64 bits of mcand * mplier");

endmodule

bind mult mult_sva #(.STAGES(`STAGES)) u_mult_sva (
    .clock   (clock),
    .reset   (reset),
    .start   (start),
    .done    (done),
    .mcand   (mcand),
    .mplier  (mplier),
    .product (product)
);

module isr_sva (
    input              clock,
    input              reset,
    input      [63:0]  stored_value,
    input      [31:0]  result,
    input              done,
    input              mult_start,
    input              mult_done
);
    // (result+1)^2 can be 2^64 when result is 2^32-1, so the squares are
    // computed at 128 bits. A 64-bit multiply would wrap that case to 0 and
    // the upper bound would pass for the wrong reason.
    logic [127:0] res_sq;
    logic [127:0] next_sq;

    assign res_sq  = {96'b0, result} * {96'b0, result};
    assign next_sq = ({96'b0, result} + 128'd1) * ({96'b0, result} + 128'd1);

    a_done_pulse: assert property (
        @(posedge clock) disable iff (reset)
        done |=> !done
    ) else $error("ISR done was not a one-cycle pulse");

    a_isqrt: assert property (
        @(posedge clock) disable iff (reset)
        done |-> (res_sq <= {64'b0, stored_value}) &&
                 (next_sq > {64'b0, stored_value})
    ) else $error("sqrt(%0d) = %0d does not satisfy r^2 <= value < (r+1)^2",
                  stored_value, result);

    // Same latency, watched from the ISR side of the mult ports. The bind
    // on mult checks the identical delay for every stage of the pipeline.
    a_mult_latency: assert property (
        @(posedge clock) disable iff (reset)
        mult_start |-> (!mult_done)[*`STAGES] ##1 mult_done
    ) else $error("ISR saw mult_done at the wrong time");

    a_mult_start_pulse: assert property (
        @(posedge clock) disable iff (reset)
        mult_start |=> !mult_start
    ) else $error("ISR held mult_start for more than one cycle");

endmodule

bind ISR isr_sva u_isr_sva (
    .clock        (clock),
    .reset        (reset),
    .stored_value (stored_value),
    .result       (result),
    .done         (done),
    .mult_start   (mult_start),
    .mult_done    (mult_done)
);
