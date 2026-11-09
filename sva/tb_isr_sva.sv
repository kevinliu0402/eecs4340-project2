// A few square-root values, including the two edges the inequality cares
// about: 0, and a value whose root is 2^32-1 (so (result+1)^2 does not fit
// in 64 bits). The numeric check itself is the assertion in isr_mult_sva.sv.
// Simulation has to run a couple of clocks after `done`, because `done |=> !done`
// is still in flight on the cycle done is first high.

module tb_isr_sva;
    logic        clock;
    logic        reset;
    logic [63:0] value;
    logic [31:0] result;
    logic        done;

    ISR dut (
        .reset  (reset),
        .value  (value),
        .clock  (clock),
        .result (result),
        .done   (done)
    );

    initial clock = 1'b0;
    always #5 clock = ~clock;

    task automatic run_one(input logic [63:0] v);
        integer cycles;
        value = v;
        reset = 1'b1;
        repeat (3) @(posedge clock);
        // Drop reset on the negedge so the DUT and the assertions sample a
        // stable reset at the following posedge. Changing it on the posedge
        // races the always_ff that looks at reset.
        @(negedge clock);
        reset = 1'b0;
        cycles = 0;
        forever begin
            @(posedge clock);
            #1;
            if (done) begin
                $display("ISR value %0d -> %0d", value, result);
                break;
            end
            cycles++;
            if (cycles > 800)
                $fatal(1, "ISR timed out for value %0d", v);
        end
        repeat (3) @(posedge clock);
    endtask

    initial begin
        run_one(64'd0);
        run_one(64'd1);
        run_one(64'd2);
        run_one(64'd144);                  // 12^2
        run_one(64'd1000);
        run_one(64'h1_0000_0000);          // 2^32, root is 65536
        run_one(64'hFFFF_FFFF_FFFF_FFFF);  // root is 2^32-1
        $display("SVA PASS isr");
        $finish;
    end
endmodule
