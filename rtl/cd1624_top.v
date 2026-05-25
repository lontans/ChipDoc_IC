`include "rtl/comparator.v"
`include "rtl/debounce.v"
`include "rtl/edge_detect.v"
`include "rtl/fault_fsm.v"
`include "rtl/wd_timer.v"
`include "rtl/i2c_slave.v"
`timescale 1ns/1ps

module cd1624_top #(
    parameter CLK = 100, // default 100MHz
    parameter V_REF_OC_A  = 8'd200,
    parameter V_REF_OV_A  = 8'd220,
    parameter V_REF_OC_B  = 8'd200,
    parameter V_REF_OV_B  = 8'd220,
    parameter V_REF_UV_A  = 8'd100,
    parameter V_REF_UV_B  = 8'd100,
    parameter V_REF_OT    = 8'd180,
    parameter HYST        = 8'd10,
    parameter HB_TIMEOUT  = 16'd10000
)(
    input wire [7:0] vsen_a,
    input wire [7:0] vsen_b,
    input wire [7:0] isen_a,
    input wire [7:0] isen_b,
    input wire [7:0] tsen,
    input wire       hb,
    input wire       mr,
    input wire       mode,
    input wire       scl,
    inout wire       sda,
    input wire       rst_n,
    output wire      health,
    output wire      warn,
    output wire      en_out
);

reg int_clk;
initial int_clk = 0;
always #(CLK/20) int_clk = ~int_clk; // Period is dependent on the clock parameter

// I2C
wire [7:0]  v_ref_oc_a, v_ref_oc_b;
wire [7:0]  v_ref_ov_a, v_ref_ov_b;
wire [7:0]  v_ref_uv_a, v_ref_uv_b;
wire [7:0]  v_ref_ot;
wire [7:0]  hyst;
wire [15:0] hb_timeout;
wire [2:0] fsm_state;
wire [7:0] fault_status;
wire sda_oe;
assign sda = sda_oe ? 1'b0 : 1'bz; // Set sda combinationally, z is ambiguous (unlatched)


i2c_slave i2c_slave (
    .clk             (int_clk     ),
    .rst_n           (rst_n       ),
    .mode            (mode        ),
    .sda             (sda         ),
    .scl             (scl         ),
    .v_ref_oc_a_dflt (V_REF_OC_A  ),
    .v_ref_oc_b_dflt (V_REF_OC_B  ),
    .v_ref_uv_a_dflt (V_REF_UV_A  ),
    .v_ref_uv_b_dflt (V_REF_UV_B  ),
    .v_ref_ov_a_dflt (V_REF_OV_A  ),
    .v_ref_ov_b_dflt (V_REF_OV_B  ),
    .v_ref_ot_dflt   (V_REF_OT    ),
    .hyst_dflt       (HYST        ),
    .hb_timeout_dflt (HB_TIMEOUT  ),
    .v_ref_oc_a      (v_ref_oc_a  ),
    .v_ref_oc_b      (v_ref_oc_b  ),
    .v_ref_uv_a      (v_ref_uv_a  ),
    .v_ref_uv_b      (v_ref_uv_b  ),
    .v_ref_ov_a      (v_ref_ov_a  ),
    .v_ref_ov_b      (v_ref_ov_b  ),
    .v_ref_ot        (v_ref_ot    ),
    .hyst            (hyst        ),
    .hb_timeout      (hb_timeout  ),
    .fsm_state       (fsm_state   ),
    .fault_status    (fault_status),
    .sda_oe          (sda_oe      )
);


// Overcurrent
wire oc_fault_a, oc_fault_b;
wire oc_fault_db_a, oc_fault_db_b;

comparator #(.WIDTH(8)) oc_comp_a (
    .clk   (int_clk),
    .rst_n (rst_n),
    .v_in  (isen_a),
    .v_ref (v_ref_oc_a),
    .hyst  (hyst),
    .fault (oc_fault_a)
);

comparator #(.WIDTH(8)) oc_comp_b (
    .clk   (int_clk),
    .rst_n (rst_n),
    .v_in  (isen_b),
    .v_ref (v_ref_oc_b),
    .hyst  (hyst),
    .fault (oc_fault_b)
);

debounce #(.THRESHOLD(10), .CTR_WIDTH(4)) oc_debounce_a (
    .clk       (int_clk),
    .rst_n     (rst_n),
    .fault_in  (oc_fault_a),
    .fault_out (oc_fault_db_a)
);

debounce #(.THRESHOLD(10), .CTR_WIDTH(4)) oc_debounce_b (
    .clk       (int_clk),
    .rst_n     (rst_n),
    .fault_in  (oc_fault_b),
    .fault_out (oc_fault_db_b)
);

// Overvoltage
wire ov_fault_a, ov_fault_b;
wire ov_fault_db_a, ov_fault_db_b;

comparator #(.WIDTH(8)) ov_comp_a (
    .clk   (int_clk),
    .rst_n (rst_n),
    .v_in  (vsen_a),
    .v_ref (v_ref_ov_a),
    .hyst  (hyst),
    .fault (ov_fault_a)
);

comparator #(.WIDTH(8)) ov_comp_b (
    .clk   (int_clk),
    .rst_n (rst_n),
    .v_in  (vsen_b),
    .v_ref (v_ref_ov_b),
    .hyst  (hyst),
    .fault (ov_fault_b)
);

debounce #(.THRESHOLD(10), .CTR_WIDTH(4)) ov_debounce_a (
    .clk       (int_clk),
    .rst_n     (rst_n),
    .fault_in  (ov_fault_a),
    .fault_out (ov_fault_db_a)
);

debounce #(.THRESHOLD(10), .CTR_WIDTH(4)) ov_debounce_b (
    .clk       (int_clk),
    .rst_n     (rst_n),
    .fault_in  (ov_fault_b),
    .fault_out (ov_fault_db_b)
);

// Undervoltage
wire uv_fault_a, uv_fault_b;
wire uv_fault_db_a, uv_fault_db_b;

comparator #(.WIDTH(8)) uv_comp_a (
    .clk   (int_clk),
    .rst_n (rst_n),
    .v_in  (v_ref_uv_a),
    .v_ref (vsen_a),
    .hyst  (hyst),
    .fault (uv_fault_a)
);

comparator #(.WIDTH(8)) uv_comp_b (
    .clk   (int_clk),
    .rst_n (rst_n),
    .v_in  (v_ref_uv_b),
    .v_ref (vsen_b),
    .hyst  (hyst),
    .fault (uv_fault_b)
);

debounce #(.THRESHOLD(10), .CTR_WIDTH(4)) uv_debounce_a (
    .clk       (int_clk),
    .rst_n     (rst_n),
    .fault_in  (uv_fault_a),
    .fault_out (uv_fault_db_a)
);

debounce #(.THRESHOLD(10), .CTR_WIDTH(4)) uv_debounce_b (
    .clk       (int_clk),
    .rst_n     (rst_n),
    .fault_in  (uv_fault_b),
    .fault_out (uv_fault_db_b)
);

// Temperature
wire ot_fault;
wire ot_fault_db;

comparator #(.WIDTH(8)) t_comp (
    .clk   (int_clk),
    .rst_n (rst_n),
    .v_in  (tsen),
    .v_ref (v_ref_ot),
    .hyst  (hyst),
    .fault (ot_fault)
);

debounce #(.THRESHOLD(10), .CTR_WIDTH(4)) t_debounce (
    .clk       (int_clk),
    .rst_n     (rst_n),
    .fault_in  (ot_fault),
    .fault_out (ot_fault_db)
);

// HB
wire hb_edge;
wire hb_fault;

edge_detect hb_edge_detect (
    .clk        (int_clk),
    .rst_n      (rst_n),
    .hb_in      (hb),
    .edge_pulse (hb_edge)
);

wd_timer #(.WIDTH(16)) hb_wd_timer (
    .clk         (int_clk),
    .rst_n       (rst_n),
    .edge_pulse  (hb_edge),
    .timeout_cfg (hb_timeout),
    .hb_fault    (hb_fault)
);

// Fault FSM
fault_fsm fault_fsm (
    .clk          (int_clk),
    .rst_n        (rst_n),
    .oc_a         (oc_fault_db_a),
    .oc_b         (oc_fault_db_b),
    .uv_a         (uv_fault_db_a),
    .uv_b         (uv_fault_db_b),
    .ov_a         (ov_fault_db_a),
    .ov_b         (ov_fault_db_b),
    .ot           (ot_fault_db),
    .hb_fault     (hb_fault),  // No db as wd_timer already detects sustained fault
    .mr           (mr),
    .en_out       (en_out),
    .health       (health),
    .warn         (warn),
    .fault_status (fault_status),
    .state        (fsm_state)
);

endmodule