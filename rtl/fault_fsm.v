// one sequential block for the state register, one combinational block for next-state logic:
// 
// Block 1: always @(posedge clk) — holds current state
// Block 2: always @(*)           — computes next_state from inputs
// Block 3: always @(*)           — drives outputs from current state
// 
// inputs:  clk, rst_n, oc_a, oc_b, uv_a, ov_a, uv_b, ov_b, ot, hb_fault, mr
// outputs: en_out, health, warn

`timescale 1ns/1ps

module fault_fsm
(
    input wire clk,
    input wire rst_n,
    input wire oc_a,
    input wire oc_b,
    input wire uv_a,
    input wire uv_b,
    input wire ov_a,
    input wire ov_b,
    input wire ot,
    input wire hb_fault,
    input wire mr,
    output reg en_out,
    output reg health,
    output reg warn,
    output reg [2:0] state,
    output reg [7:0] fault_status
);
localparam INIT     = 3'd0;
localparam NORMAL   = 3'd1;
localparam WARN     = 3'd2;
localparam FAULT    = 3'd3;
localparam RECOVERY = 3'd4;

reg [2:0] next_state;
reg [3:0] warn_count;
reg       latched;

always @(posedge clk or negedge rst_n) begin
    fault_status <= {oc_a, oc_b, uv_a, uv_b, ov_a, ov_b, ot, hb_fault};
    if (!rst_n) begin
        state <= INIT;
        warn_count <= 4'd0;
        latched <= 1'b0;
    end else begin
        state <= next_state;

        // Settling warn_count
        if (next_state == WARN)
            warn_count <= warn_count + 4'd1;
        else
            warn_count <= 4'd0;

        // Settling latching
        if (state == NORMAL && (ov_a || ov_b || hb_fault))
            latched <= 1'b1;
        else if (state == RECOVERY)
            latched <= 1'b0;   
    end
end

always @(*) begin
    next_state = state;
    case (state)
        INIT: begin
            next_state = NORMAL;
        end
        NORMAL: begin
            if (ov_a || ov_b || hb_fault) 
                next_state = FAULT;
            else if (oc_a || oc_b || uv_a || uv_b || ot) begin
                    next_state = WARN;
            end else next_state = NORMAL;
        end
        WARN: begin
            if (ov_a || ov_b || hb_fault || (warn_count >= 4'd10 ))
                next_state = FAULT;
            else if (oc_a || oc_b || uv_a || uv_b || ot)
                next_state = WARN;
            else 
                next_state = NORMAL;
        end
        FAULT: begin
            if ((!(oc_a || oc_b || ov_a || ov_b || uv_a || uv_b || ot || hb_fault)) && (mr || !latched)) begin
                next_state = RECOVERY;         
            end else next_state = FAULT;
        end
        RECOVERY: begin
            if (ov_a || ov_b || hb_fault)
                next_state = FAULT;
            else if (oc_a || oc_b || uv_a || uv_b || ot)
                next_state = WARN;
            else
                next_state = NORMAL;
        end
    endcase
end

always @(*) begin
    en_out = (state == FAULT) ? 1'b0 : 1'b1; 
    health = (state == FAULT) ? 1'b0 : 1'b1; 
    warn   = (state == FAULT || state == WARN) ? 1'b1 : 1'b0;
end

endmodule