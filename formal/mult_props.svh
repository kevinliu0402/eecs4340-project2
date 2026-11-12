// Formal properties for the 8-stage multiplier (rtl/mult.sv), pasted into a
// copy of the module by the Makefile. Same Yosys SVA subset as isr_props.svh.
//
// Defines:
//   FV_PRODUCT  also prove the product value
//   FV_OPW=n    with FV_PRODUCT: limit both operands to n bits

`ifdef FORMAL
    reg f_past_valid = 1'b0;
    always @(posedge clock) f_past_valid <= 1'b1;
    always @(*) if (!f_past_valid) assume(reset);

    // Starts seen in the last STAGES cycles, newest in bit 0.
    reg [`STAGES-1:0] f_starts;
    always @(posedge clock)
        if (reset) f_starts <= '0;
        else       f_starts <= {f_starts[`STAGES-2:0], start};

    always @(*) if (f_past_valid) begin
        // M1: done is exactly start delayed by STAGES cycles. Starts made
        //     before or during reset never produce a done.
        assert(done == f_starts[`STAGES-1]);

        // H1 (helper): the internal done chain holds the same history.
        assert(internal_dones == f_starts[`STAGES-2:0]);
    end

    always @(*) if (f_past_valid) cover(done);

`ifdef FV_PRODUCT
    // Operands captured at start, aged along with the pipeline.
    reg [63:0] f_a [0:`STAGES-1];
    reg [63:0] f_b [0:`STAGES-1];
    integer f_i;
    always @(posedge clock) begin
        f_a[0] <= mcand;
        f_b[0] <= mplier;
        for (f_i = 1; f_i < `STAGES; f_i = f_i + 1) begin
            f_a[f_i] <= f_a[f_i-1];
            f_b[f_i] <= f_b[f_i-1];
        end
    end

`ifdef FV_OPW
    always @(*) begin
        assume(mcand  < (65'd1 << `FV_OPW));
        assume(mplier < (65'd1 << `FV_OPW));
    end
`endif

    // M2: the product is the low 64 bits of mcand * mplier sampled at start.
    always @(*) if (f_past_valid && done)
        assert(product == f_a[`STAGES-1] * f_b[`STAGES-1]);
`endif
`endif
