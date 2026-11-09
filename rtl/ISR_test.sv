`timescale 1ns/1ps

// Comprehensive testbench for the ISR (Integer Square Root) module
// Tests edge cases and random values, and must catch bugs in ISR_buggy1, ISR_buggy2, ISR_buggy3

module testbench;

    // Signals
    logic        clock;
    logic        reset;
    logic [63:0] value;
    logic [31:0] result;
    logic        done;
    
    // Test tracking
    integer      test_count;
    integer      pass_count;
    logic        test_failed;
    integer      i;
    
    // For verification
    logic [63:0] result_squared;
    logic [63:0] result_plus_one_squared;
    
    // DUT instantiation
    ISR dut (
        .reset  (reset),
        .value  (value),
        .clock  (clock),
        .result (result),
        .done   (done)
    );

    // Clock generation - CLOCK_PERIOD is defined on the commandline by the makefile
    always begin
        #(`CLOCK_PERIOD/2.0);
        clock = ~clock;
    end

    // Task to wait until done signal is asserted
    // From mult_test.sv - handles potential glitches
    task wait_until_done;
        integer timeout_count;
        begin
            timeout_count = 0;
            forever begin : wait_loop
                @(posedge clock);
                #(`CLOCK_PERIOD*0.2); // Short wait for signal stability
                if (done) begin
                    disable wait_until_done;
                end
                timeout_count = timeout_count + 1;
                // Timeout after 600 cycles as per spec
                if (timeout_count > 600) begin
                    $display("@@@ Incorrect - Timeout: ISR took more than 600 cycles");
                    $display("@@@ Incorrect");
                    $finish;
                end
            end
        end
    endtask

    // Task to compute and check ISR result
    // The result is correct if:
    //   1. result * result <= value (result is not too large)
    //   2. (result+1) * (result+1) > value (result is not too small)
    //      OR result is the maximum (2^32-1), where (result+1)^2 would overflow
    task check_result;
        input [63:0] test_value;
        input [31:0] test_result;
        begin
            result_squared = {32'b0, test_result} * {32'b0, test_result};
            result_plus_one_squared = {32'b0, test_result + 32'd1} * {32'b0, test_result + 32'd1};
            
            if (result_squared > test_value) begin
                $display("@@@ Incorrect - Result too large: sqrt(%0d) = %0d, but %0d^2 = %0d > %0d",
                         test_value, test_result, test_result, result_squared, test_value);
                test_failed = 1;
            end else if (test_result == 32'hFFFFFFFF) begin
                // Maximum result (2^32-1): (result+1)^2 would overflow, so just check result^2 <= value
                // If we got here, result_squared <= test_value, which is correct
                pass_count = pass_count + 1;
            end else if (result_plus_one_squared <= test_value) begin
                $display("@@@ Incorrect - Result too small: sqrt(%0d) = %0d, but (%0d+1)^2 = %0d <= %0d",
                         test_value, test_result, test_result, result_plus_one_squared, test_value);
                test_failed = 1;
            end else begin
                pass_count = pass_count + 1;
            end
            test_count = test_count + 1;
        end
    endtask

    // Task to run a single ISR test
    task run_test;
        input [63:0] test_value;
        begin
            @(negedge clock);
            value = test_value;
            reset = 1;
            @(negedge clock);
            reset = 0;
            wait_until_done();
            check_result(test_value, result);
        end
    endtask

    // Task to run ISR test and verify done is high for exactly one cycle
    task run_test_check_done;
        input [63:0] test_value;
        integer done_cycles;
        begin
            @(negedge clock);
            value = test_value;
            reset = 1;
            @(negedge clock);
            reset = 0;
            wait_until_done();
            
            // Count how many cycles done stays high
            // We're currently at posedge where done is 1
            // Wait for next posedge and check if done is still high
            done_cycles = 1;
            @(posedge clock);
            #(`CLOCK_PERIOD*0.2);
            while (done && done_cycles < 10) begin
                done_cycles = done_cycles + 1;
                @(posedge clock);
                #(`CLOCK_PERIOD*0.2);
            end
            
            if (done_cycles > 1) begin
                $display("@@@ Incorrect - Done signal high for %0d cycles (should be 1) for value %0d",
                         done_cycles, test_value);
                test_failed = 1;
            end else begin
                check_result(test_value, result);
            end
        end
    endtask

    // Main test sequence
    initial begin
        // Initialize
        clock = 0;
        reset = 0;
        value = 0;
        test_count = 0;
        pass_count = 0;
        test_failed = 0;

        $display("\n========================================");
        $display("ISR Module Testbench");
        $display("========================================\n");

        // Wait a bit for simulation to stabilize
        @(negedge clock);
        @(negedge clock);

        // ==========================================
        // Edge Case Tests
        // ==========================================
        $display("Running edge case tests...\n");

        // Test 0: sqrt(0) = 0
        $display("Test: sqrt(0)");
        run_test(64'd0);
        if (test_failed) begin
            $display("@@@ Incorrect");
            $finish;
        end

        // Test 1: sqrt(1) = 1
        $display("Test: sqrt(1)");
        run_test(64'd1);
        if (test_failed) begin
            $display("@@@ Incorrect");
            $finish;
        end

        // Test 2: sqrt(2) = 1
        $display("Test: sqrt(2)");
        run_test(64'd2);
        if (test_failed) begin
            $display("@@@ Incorrect");
            $finish;
        end

        // Test 3: sqrt(3) = 1
        $display("Test: sqrt(3)");
        run_test(64'd3);
        if (test_failed) begin
            $display("@@@ Incorrect");
            $finish;
        end

        // Test 4: sqrt(4) = 2 (perfect square)
        $display("Test: sqrt(4)");
        run_test(64'd4);
        if (test_failed) begin
            $display("@@@ Incorrect");
            $finish;
        end

        // Test sqrt(24) = 4 (example from spec)
        $display("Test: sqrt(24)");
        run_test(64'd24);
        if (test_failed) begin
            $display("@@@ Incorrect");
            $finish;
        end

        // Test sqrt(25) = 5 (perfect square)
        $display("Test: sqrt(25)");
        run_test(64'd25);
        if (test_failed) begin
            $display("@@@ Incorrect");
            $finish;
        end

        // Test sqrt(100) = 10
        $display("Test: sqrt(100)");
        run_test(64'd100);
        if (test_failed) begin
            $display("@@@ Incorrect");
            $finish;
        end

        // Test sqrt(1001) - mentioned in question 7
        $display("Test: sqrt(1001)");
        run_test(64'd1001);
        if (test_failed) begin
            $display("@@@ Incorrect");
            $finish;
        end

        // Test sqrt(1000000) = 1000
        $display("Test: sqrt(1000000)");
        run_test(64'd1000000);
        if (test_failed) begin
            $display("@@@ Incorrect");
            $finish;
        end

        // Test sqrt(2^32 - 1) - maximum 32-bit value
        $display("Test: sqrt(2^32 - 1)");
        run_test(64'hFFFFFFFF);
        if (test_failed) begin
            $display("@@@ Incorrect");
            $finish;
        end

        // Test sqrt(2^32) = 2^16 (boundary case)
        $display("Test: sqrt(2^32)");
        run_test(64'h100000000);
        if (test_failed) begin
            $display("@@@ Incorrect");
            $finish;
        end

        // Test sqrt(2^62) - large value
        $display("Test: sqrt(2^62)");
        run_test(64'h4000000000000000);
        if (test_failed) begin
            $display("@@@ Incorrect");
            $finish;
        end

        // Test sqrt(2^63) - very large value
        $display("Test: sqrt(2^63)");
        run_test(64'h8000000000000000);
        if (test_failed) begin
            $display("@@@ Incorrect");
            $finish;
        end

        // Test sqrt(2^64 - 1) - maximum 64-bit value
        $display("Test: sqrt(2^64 - 1)");
        run_test(64'hFFFFFFFFFFFFFFFF);
        if (test_failed) begin
            $display("@@@ Incorrect");
            $finish;
        end

        // Test perfect squares near powers of 2
        $display("Test: sqrt(65536) = 256");
        run_test(64'd65536);
        if (test_failed) begin
            $display("@@@ Incorrect");
            $finish;
        end

        // Test just below a perfect square
        $display("Test: sqrt(65535)");
        run_test(64'd65535);
        if (test_failed) begin
            $display("@@@ Incorrect");
            $finish;
        end

        // Test just above a perfect square
        $display("Test: sqrt(65537)");
        run_test(64'd65537);
        if (test_failed) begin
            $display("@@@ Incorrect");
            $finish;
        end

        // Large perfect square: (2^31 - 1)^2 = max result squared
        $display("Test: sqrt((2^31-1)^2)");
        run_test(64'd4611686014132420609); // (2^31-1)^2
        if (test_failed) begin
            $display("@@@ Incorrect");
            $finish;
        end

        // ==========================================
        // Reset During Computation Test
        // ==========================================
        $display("\nTesting reset during computation...\n");
        
        // Start a computation
        @(negedge clock);
        value = 64'd1000000;
        reset = 1;
        @(negedge clock);
        reset = 0;
        
        // Wait a few cycles then reset with new value
        repeat(5) @(negedge clock);
        value = 64'd49;  // sqrt(49) = 7
        reset = 1;
        @(negedge clock);
        reset = 0;
        wait_until_done();
        
        // Check that the result is for the new value
        check_result(64'd49, result);
        if (test_failed) begin
            $display("@@@ Incorrect - Reset during computation failed");
            $display("@@@ Incorrect");
            $finish;
        end

        // ==========================================
        // Random Tests
        // ==========================================
        $display("\nRunning random tests...\n");

        for (i = 0; i < 20; i = i + 1) begin
            run_test({$random, $random});
            if (test_failed) begin
                $display("@@@ Incorrect");
                $finish;
            end
        end

        // More targeted random tests with smaller values
        for (i = 0; i < 10; i = i + 1) begin
            run_test({32'b0, $random});
            if (test_failed) begin
                $display("@@@ Incorrect");
                $finish;
            end
        end

        // Test some specific values that might expose common bugs
        $display("\nRunning additional targeted tests...\n");

        // Values that are one less than perfect squares
        run_test(64'd8);   // sqrt(8) = 2
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end
        
        run_test(64'd15);  // sqrt(15) = 3
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end
        
        run_test(64'd99);  // sqrt(99) = 9
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end

        // Values that are one more than perfect squares
        run_test(64'd5);   // sqrt(5) = 2
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end
        
        run_test(64'd10);  // sqrt(10) = 3
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end
        
        run_test(64'd101); // sqrt(101) = 10
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end

        // Powers of 2
        run_test(64'd16);
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end
        
        run_test(64'd256);
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end
        
        run_test(64'd4096);
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end

        // Additional tests to catch subtle bugs
        
        // Small perfect squares
        run_test(64'd9);    // sqrt(9) = 3
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end
        
        run_test(64'd36);   // sqrt(36) = 6
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end
        
        run_test(64'd49);   // sqrt(49) = 7
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end
        
        run_test(64'd64);   // sqrt(64) = 8
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end
        
        run_test(64'd81);   // sqrt(81) = 9
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end
        
        run_test(64'd121);  // sqrt(121) = 11
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end
        
        run_test(64'd144);  // sqrt(144) = 12
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end

        // Test consecutive computations (done signal behavior)
        run_test(64'd100);
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end
        run_test(64'd101);
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end
        run_test(64'd102);
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end

        // Specific bit patterns
        run_test(64'hAAAAAAAAAAAAAAAA);  // Alternating bits
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end
        
        run_test(64'h5555555555555555);  // Alternating bits (inverse)
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end
        
        run_test(64'h0F0F0F0F0F0F0F0F);  // Nibble pattern
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end

        // Values near powers of 2
        run_test(64'd127);   // 2^7 - 1
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end
        
        run_test(64'd128);   // 2^7
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end
        
        run_test(64'd129);   // 2^7 + 1
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end
        
        run_test(64'd255);   // 2^8 - 1
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end
        
        run_test(64'd257);   // 2^8 + 1
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end

        run_test(64'd1023);  // 2^10 - 1
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end
        
        run_test(64'd1024);  // 2^10
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end

        // Large values with specific patterns
        run_test(64'h7FFFFFFFFFFFFFFF);  // 2^63 - 1
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end
        
        run_test(64'h0000000100000000);  // 2^32
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end
        
        run_test(64'h00000000FFFFFFFE);  // 2^32 - 2
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end

        // Test value = result^2 - 1 (just below perfect squares)
        run_test(64'd48);   // 49 - 1, sqrt = 6
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end
        
        run_test(64'd80);   // 81 - 1, sqrt = 8
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end
        
        run_test(64'd120);  // 121 - 1, sqrt = 10
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end

        // Very small values
        run_test(64'd5);
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end
        
        run_test(64'd6);
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end
        
        run_test(64'd7);
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end

        // Test done signal is only high for one cycle
        $display("\nTesting done signal duration...\n");
        
        run_test_check_done(64'd16);
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end
        
        run_test_check_done(64'd100);
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end
        
        run_test_check_done(64'd1000);
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end
        
        run_test_check_done(64'd0);
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end
        
        run_test_check_done(64'hFFFFFFFF);
        if (test_failed) begin $display("@@@ Incorrect"); $finish; end

        // ==========================================
        // Summary
        // ==========================================
        $display("\n========================================");
        $display("Test Summary: %0d/%0d tests passed", pass_count, test_count);
        $display("========================================\n");

        if (test_failed) begin
            $display("@@@ Incorrect");
        end else begin
            $display("@@@ Passed");
        end

        $finish;
    end

endmodule
