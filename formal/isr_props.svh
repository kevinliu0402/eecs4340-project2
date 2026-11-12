// Formal properties for ISR. The Makefile pastes this file into a copy of
// rtl/ISR.sv just before `endmodule`, so the properties can see the FSM and
// datapath registers directly. rtl/ISR.sv itself is not modified.
//
// Written in the SVA subset that open-source Yosys reads: immediate
// assertions inside always blocks, with $past for history.
//
// Defines (set per task in isr.sby):
//   FV_ALGO        prove the square-root algorithm for every 64-bit input
//   FV_ASSUME_CTRL assume (rather than assert) the control properties
//
// How the algorithm proof is split (assume-guarantee):
//   - Here the multiplier's product is a free value. Ghost registers record
//     each square ISR reads and which number it is the square of. The proof
//     shows that when done is high, M(result) <= value < M(result + 1),
//     where M(x) is the product the multiplier returned for x * x, and that
//     the operands were exactly x and x when that product was started.
//   - The multiplier's own property (mult_props.svh, M2) is M(x) = x * x.
//   Together: result^2 <= value < (result+1)^2, i.e. result = floor(sqrt).
//   Keeping multiplication out of the invariants keeps the proof linear.

`ifdef FORMAL
    // Control properties are asserted in the control task and assumed in the
    // algo task (FV_ASSUME_CTRL), which then only has to prove the A* ones.
`ifdef FV_ASSUME_CTRL
    `define CTRL assume
`else
    `define CTRL assert
`endif

    // ---------------------------------------------------------------- env
    // Reset is held on the first cycle. After that it is a free input, so
    // every property also covers a reset arriving mid-computation.
    reg f_past_valid = 1'b0;
    always @(posedge clock) f_past_valid <= 1'b1;
    always @(*) if (!f_past_valid) assume(reset);

    // Cycles since reset was released (saturates).
    reg [8:0] f_cyc;
    always @(posedge clock)
        if (reset)               f_cyc <= 9'd0;
        else if (f_cyc != 9'h1ff) f_cyc <= f_cyc + 9'd1;

    wire f_computing = (state == TRY_BIT) || (state == WAIT_MULT) ||
                       (state == CHECK_RESULT);

    // Bits [bit_index:0] of the result are still undecided.
    wire [32:0] f_low_mask = (33'd2 << bit_index[4:0]) - 33'd1;

    // ------------------------------------------------------ control (C*)
    always @(*) if (f_past_valid) begin
        // C1: the FSM never reaches IDLE or an unused encoding.
        `CTRL(f_computing || state == FINISH || state == DONE_WAIT);

        // C2: done rises exactly once, 321 cycles after reset is released
        //     (32 bits x (1 TRY_BIT + 8 WAIT_MULT + 1 CHECK_RESULT) + FINISH).
        `CTRL(done == (f_cyc == 9'd321));

        // C3: bit_index walks 31..0 while computing, and has wrapped after.
        if (f_computing) `CTRL(bit_index <= 6'd31);
        else             `CTRL(bit_index == 6'd63);

        // C4: the multiplier is started only from TRY_BIT, and its done
        //     pulse only arrives while ISR is waiting for it.
        `CTRL(mult_start == (state == TRY_BIT));
        if (mult_done) `CTRL(state == WAIT_MULT);

        // C5: bits not yet tried are still zero.
        if (f_computing) `CTRL((current_result & f_low_mask[31:0]) == 32'd0);

        // H1 (helper for induction): the whole schedule is fixed by the
        // cycle count. Bit b is tried in cycles 10*(31-b) .. 10*(31-b)+9:
        // TRY_BIT, then 8 cycles of WAIT_MULT, then CHECK_RESULT.
        if (f_cyc < 9'd320) begin
            `CTRL(bit_index == 6'd31 - f_cyc / 9'd10);
            `CTRL(state == ((f_cyc % 9'd10 == 9'd0) ? TRY_BIT :
                            (f_cyc % 9'd10 == 9'd9) ? CHECK_RESULT : WAIT_MULT));
        end else if (f_cyc == 9'd320) begin
            `CTRL(state == FINISH);
        end else begin
            `CTRL(state == DONE_WAIT);
        end
    end

    always @(posedge clock) if (f_past_valid && !$past(reset)) begin
        // C6: the sampled input never changes after reset.
        `CTRL(stored_value == $past(stored_value));

        // C7: the result changes only in CHECK_RESULT, and then only by
        //     setting the bit being tried.
        if ($past(state) != CHECK_RESULT)
            `CTRL(current_result == $past(current_result));
        else
            `CTRL((current_result == $past(current_result)) ||
                   (current_result == ($past(current_result) |
                                       (32'b1 << $past(bit_index[4:0])))));

        // C8: TRY_BIT always hands off to WAIT_MULT on the next cycle.
        if ($past(state) == TRY_BIT) `CTRL(state == WAIT_MULT);
    end

    // ------------------------------------------------------------- covers
    always @(*) if (f_past_valid) begin
        cover(done);
        cover(state == CHECK_RESULT && mult_product <= stored_value);
        cover(state == CHECK_RESULT && mult_product >  stored_value);
    end

`ifdef FV_ALGO
    // ------------------------------------------------ algorithm (A*)
    wire [31:0] f_try = current_result | (32'b1 << bit_index[4:0]);
    wire        f_keep = (state == CHECK_RESULT) && (mult_product <= stored_value);
    wire        f_drop = (state == CHECK_RESULT) && !(mult_product <= stored_value);

    // Operands at the last TRY_BIT, to tie each product read in
    // CHECK_RESULT to the number it was started with.
    reg [63:0] f_op_a, f_op_b;
    always @(posedge clock)
        if (state == TRY_BIT) begin
            f_op_a <= mult_mcand;
            f_op_b <= mult_mplier;
        end

    // lo: the root is at least lo_arg, and lo_sq = M(lo_arg) <= value.
    // hi: the root is below hi_arg, and value < hi_sq = M(hi_arg).
    //     hi_top marks hi_arg = 2^32, whose square (2^64) exceeds any value.
    reg [31:0] f_lo_arg, f_hi_arg;
    reg [63:0] f_lo_sq,  f_hi_sq;
    reg        f_hi_top;
    always @(posedge clock)
        if (reset) begin
            f_lo_arg <= 32'd0;  f_lo_sq <= 64'd0;    // 0 * 0 = 0
            f_hi_arg <= 32'd0;  f_hi_sq <= 64'd0;  f_hi_top <= 1'b1;
        end else if (f_keep) begin
            f_lo_arg <= f_try;  f_lo_sq <= mult_product;
        end else if (f_drop) begin
            f_hi_arg <= f_try;  f_hi_sq <= mult_product;  f_hi_top <= 1'b0;
        end

    always @(*) if (f_past_valid) begin
        // A1: each product read in CHECK_RESULT is the square of the guess:
        //     both operands were {32'b0, guess} when it was started (and the
        //     guess does not move while the multiplier runs).
        if (state == WAIT_MULT || state == CHECK_RESULT) begin
            assert(f_op_a == {32'b0, f_try});
            assert(f_op_b == {32'b0, f_try});
        end

        // A2: the bounds. lo is the current result; hi sits one past the
        //     largest result the untried bits could still produce.
        assert(f_lo_arg == current_result);
        assert(f_lo_sq <= stored_value);
        assert(f_hi_top || stored_value < f_hi_sq);
        if (f_computing)
            assert({f_hi_top, f_hi_arg} == {1'b0, current_result} + (33'd2 << bit_index[4:0]));
        else
            assert({f_hi_top, f_hi_arg} == {1'b0, current_result} + 33'd1);

        // A3: at done, result = lo_arg and result + 1 = hi_arg, so
        //     M(result) <= value < M(result + 1).
        if (done) begin
            assert(f_lo_arg == current_result && f_lo_sq <= stored_value);
            assert({f_hi_top, f_hi_arg} == {1'b0, current_result} + 33'd1);
            assert(f_hi_top || stored_value < f_hi_sq);
        end
    end
`endif
`endif
