
module ISR (
    input               reset,
    input        [63:0] value,
    input               clock,
    output logic [31:0] result,
    output logic        done
);

    // FSM states
    typedef enum logic [2:0] {
        IDLE,           // Waiting for reset
        TRY_BIT,        // Set current bit and start multiplication
        WAIT_MULT,      // Wait for multiplier to complete
        CHECK_RESULT,   // Check if square > value, update result
        FINISH,         // Output done signal for one cycle
        DONE_WAIT       // Wait for next reset
    } state_t;

    state_t state, next_state;

    // Internal registers
    logic [63:0] stored_value;      // Stored input value
    logic [31:0] current_result;    // Current result being computed
    logic [5:0]  bit_index;         // Current bit being tested (0-31)
    
    // Multiplier interface signals
    logic [63:0] mult_mcand, mult_mplier;
    logic        mult_start;
    logic [63:0] mult_product;
    logic        mult_done;
    logic        mult_reset;

    // Instantiate the pipelined multiplier
    mult multiplier (
        .clock   (clock),
        .reset   (mult_reset),
        .mcand   (mult_mcand),
        .mplier  (mult_mplier),
        .start   (mult_start),
        .product (mult_product),
        .done    (mult_done)
    );

    // Multiplier reset should follow system reset
    assign mult_reset = reset;
    
    // Multiplier inputs - we're squaring current_result with the tried bit set
    assign mult_mcand  = {32'b0, current_result | (32'b1 << bit_index[4:0])};
    assign mult_mplier = {32'b0, current_result | (32'b1 << bit_index[4:0])};

    // State machine - sequential logic
    always_ff @(posedge clock) begin
        if (reset) begin
            state          <= TRY_BIT;
            stored_value   <= value;
            current_result <= 32'b0;
            bit_index      <= 6'd31;
            done           <= 1'b0;
        end else begin
            state <= next_state;
            
            case (state)
                TRY_BIT: begin
                    // Just started mult, nothing to do here
                    done <= 1'b0;
                end
                
                WAIT_MULT: begin
                    // Waiting for multiplier
                    done <= 1'b0;
                end
                
                CHECK_RESULT: begin
                    // Check if square <= stored_value
                    if (mult_product <= stored_value) begin
                        // Keep the bit set
                        current_result <= current_result | (32'b1 << bit_index[4:0]);
                    end
                    // Otherwise leave bit as 0
                    
                    // Move to next bit
                    bit_index <= bit_index - 1'b1;
                    done <= 1'b0;
                end
                
                FINISH: begin
                    done <= 1'b1;
                end
                
                DONE_WAIT: begin
                    done <= 1'b0;
                end
                
                default: begin
                    done <= 1'b0;
                end
            endcase
        end
    end

    // Next state logic - combinational
    always_comb begin
        mult_start = 1'b0;
        next_state = state;
        
        case (state)
            IDLE: begin
                // Wait for reset to trigger computation
                next_state = IDLE;
            end
            
            TRY_BIT: begin
                // Start the multiplication
                mult_start = 1'b1;
                next_state = WAIT_MULT;
            end
            
            WAIT_MULT: begin
                // Wait for multiplier to complete
                if (mult_done) begin
                    next_state = CHECK_RESULT;
                end else begin
                    next_state = WAIT_MULT;
                end
            end
            
            CHECK_RESULT: begin
                // After checking, go to next bit or finish
                if (bit_index == 6'd0) begin
                    next_state = FINISH;
                end else begin
                    next_state = TRY_BIT;
                end
            end
            
            FINISH: begin
                // Done for one cycle, then go to wait state
                next_state = DONE_WAIT;
            end
            
            DONE_WAIT: begin
                // Stay here until reset
                next_state = DONE_WAIT;
            end
            
            default: begin
                next_state = IDLE;
            end
        endcase
    end

    // Result output
    assign result = current_result;

endmodule
