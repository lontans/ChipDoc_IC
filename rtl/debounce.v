// Takes any fault flag from a comparator and ensures it's been active 
// for a minimum number of cycles before passing it to the FSM. Filters single-cycle glitches.
// 
// inputs:  clk, rst_n, fault_in
// outputs: fault_out
// parameters: THRESHOLD, CTR_WIDTH
// 
// Concept is almost identical to wd_timer but inverted logic — counter increments 
// while fault_in is high, resets when it goes low, and fault_out asserts when counter 
// reaches threshold:
// 
// fault_in high → increment counter
// fault_in low  → reset counter to 0
// fault_out     → counter >= THRESHOLD
`timescale 1ns/1ps

module debounce #(
    parameter THRESHOLD = 10,
    parameter CTR_WIDTH = 4
)(
    input wire clk,
    input wire rst_n,
    input wire fault_in,
    output reg fault_out
);

reg [CTR_WIDTH-1: 0] count;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        fault_out <= 1'b0;
        count <= 0;
    end else begin
        if (fault_in) begin
            if (count < THRESHOLD)
                count <= count + 1;   // stop incrementing at threshold
            fault_out <= (count >= THRESHOLD);
        end else begin
            count <= 0;
            fault_out <= 1'b0;
        end
        
    end
end

endmodule