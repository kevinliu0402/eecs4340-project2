// Concrete run for run_mutants.sh: Yosys `sim` drives clock and reset, and
// value is tied to 1001 (the example in the Project 2 questions). The
// properties inside ISR are checked on every cycle of the run.
module sim_top (input clock, input reset);
    wire [31:0] result;
    wire        done;
    ISR dut (.reset(reset), .value(64'd1001), .clock(clock),
             .result(result), .done(done));
endmodule
