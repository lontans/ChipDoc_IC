// Edge detector module
// edge_pulse = 1 for one clock cycle during edge transition

`timescale 1ns/1ps

module edge_detect
(
    input wire hb_in,
    input wire clk,
    input wire rst_n,
    output reg edge_pulse
);

reg prev_hb;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        prev_hb <= 1'b0;
        edge_pulse <= 1'b0;
    end else begin
       prev_hb <= hb_in;
       edge_pulse <= (hb_in != prev_hb); 
    end   
end

endmodule