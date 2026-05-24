// I2C module, processes reference signals

`timescale 1ns/1ps

module i2c_slave
(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        mode,
    input  wire        scl,
    input  wire        sda,

    // default values in
    input  wire [7:0]  v_ref_oc_a_dflt,
    input  wire [7:0]  v_ref_oc_b_dflt,
    input  wire [7:0]  v_ref_ov_a_dflt,
    input  wire [7:0]  v_ref_ov_b_dflt,
    input  wire [7:0]  v_ref_uv_a_dflt,
    input  wire [7:0]  v_ref_uv_b_dflt,
    input  wire [7:0]  v_ref_ot_dflt,
    input  wire [7:0]  hyst_dflt,
    input  wire [15:0] hb_timeout_dflt,

    // configured values out
    output reg [7:0]  v_ref_oc_a,
    output reg [7:0]  v_ref_oc_b,
    output reg [7:0]  v_ref_ov_a,
    output reg [7:0]  v_ref_ov_b,
    output reg [7:0]  v_ref_uv_a,
    output reg [7:0]  v_ref_uv_b,
    output reg [7:0]  v_ref_ot,
    output reg [7:0]  hyst,
    output reg [15:0] hb_timeout
);

// stub — passthrough regardless of mode
always @(*) begin
    if (mode) begin
        v_ref_oc_a = v_ref_oc_a_dflt;
        v_ref_oc_b = v_ref_oc_b_dflt;
        v_ref_ov_a = v_ref_ov_a_dflt;
        v_ref_ov_b = v_ref_ov_b_dflt;
        v_ref_uv_a = v_ref_uv_a_dflt;
        v_ref_uv_b = v_ref_uv_b_dflt;
        v_ref_ot   = v_ref_ot_dflt;
        hyst       = hyst_dflt;
        hb_timeout = hb_timeout_dflt;
    end else begin
        v_ref_oc_a = v_ref_oc_a_dflt;
        v_ref_oc_b = v_ref_oc_b_dflt;
        v_ref_ov_a = v_ref_ov_a_dflt;
        v_ref_ov_b = v_ref_ov_b_dflt;
        v_ref_uv_a = v_ref_uv_a_dflt;
        v_ref_uv_b = v_ref_uv_b_dflt;
        v_ref_ot   = v_ref_ot_dflt;
        hyst       = hyst_dflt;
        hb_timeout = hb_timeout_dflt;
    end
end

endmodule