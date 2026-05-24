// inputs:  clk, rst_n, edge_pulse, timeout_cfg [15:0]
// outputs: hb_fault
// takes edge_pulse from edge_detect and outputs hb_fault to the FSM. 
// Conceptually just a counter that resets on every pulse and faults when it times out.

`timescale 1ns/1ps

module wd_timer #(
    parameter WIDTH = 16

)(
    input wire              clk,
    input wire              rst_n,
    input wire              edge_pulse,
    input wire  [WIDTH-1:0] timeout_cfg,
    output reg              hb_fault
);

reg [WIDTH-1:0] count;

always @(posedge clk or negedge rst_n ) begin
    if (!rst_n) begin
        count <= 0;
        hb_fault <= 1'b0;
    end else begin
        if (edge_pulse) begin
            count <= 0;
            hb_fault <= 1'b0;
        end else begin
            count <= count + 1;
            hb_fault <= (count >= timeout_cfg);
        end
    end
end

endmodule