// I2C Slave Testbench — CD1624
// Bit-bangs SCL and SDA to simulate an I2C master
// SCL-clocked FSM version — no synchronizer signals
`timescale 1ns/1ps

module tb_i2c_slave;

    reg        clk, rst_n;
    reg        mode;
    reg        scl;
    reg        sda_drive;
    wire       sda;
    wire       sda_oe;

    reg  [7:0]  v_ref_oc_a_dflt = 8'd150;
    reg  [7:0]  v_ref_oc_b_dflt = 8'd150;
    reg  [7:0]  v_ref_uv_a_dflt = 8'd80;
    reg  [7:0]  v_ref_uv_b_dflt = 8'd80;
    reg  [7:0]  v_ref_ov_a_dflt = 8'd200;
    reg  [7:0]  v_ref_ov_b_dflt = 8'd200;
    reg  [7:0]  v_ref_ot_dflt   = 8'd180;
    reg  [7:0]  hyst_dflt        = 8'd10;
    reg  [15:0] hb_timeout_dflt  = 16'd10000;
    reg  [7:0]  fault_status     = 8'h00;
    reg  [2:0]  fsm_state        = 3'd1;

    wire [7:0]  v_ref_oc_a, v_ref_oc_b;
    wire [7:0]  v_ref_uv_a, v_ref_uv_b;
    wire [7:0]  v_ref_ov_a, v_ref_ov_b;
    wire [7:0]  v_ref_ot;
    wire [7:0]  hyst;
    wire [15:0] hb_timeout;

    // open drain — master or slave can pull low, pullup = 1
    assign sda = (sda_drive || sda_oe) ? 1'b0 : 1'b1;

    i2c_slave DUT (
        .clk             (clk            ),
        .rst_n           (rst_n          ),
        .mode            (mode           ),
        .scl             (scl            ),
        .sda             (sda            ),
        .sda_oe          (sda_oe         ),
        .v_ref_oc_a_dflt (v_ref_oc_a_dflt),
        .v_ref_oc_b_dflt (v_ref_oc_b_dflt),
        .v_ref_uv_a_dflt (v_ref_uv_a_dflt),
        .v_ref_uv_b_dflt (v_ref_uv_b_dflt),
        .v_ref_ov_a_dflt (v_ref_ov_a_dflt),
        .v_ref_ov_b_dflt (v_ref_ov_b_dflt),
        .v_ref_ot_dflt   (v_ref_ot_dflt  ),
        .hyst_dflt       (hyst_dflt      ),
        .hb_timeout_dflt (hb_timeout_dflt),
        .fault_status    (fault_status   ),
        .fsm_state       (fsm_state      ),
        .v_ref_oc_a      (v_ref_oc_a     ),
        .v_ref_oc_b      (v_ref_oc_b     ),
        .v_ref_uv_a      (v_ref_uv_a     ),
        .v_ref_uv_b      (v_ref_uv_b     ),
        .v_ref_ov_a      (v_ref_ov_a     ),
        .v_ref_ov_b      (v_ref_ov_b     ),
        .v_ref_ot        (v_ref_ot       ),
        .hyst            (hyst           ),
        .hb_timeout      (hb_timeout     )
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("sim/sim_records_tb_i2c_slave.vcd");
        $dumpvars(0, tb_i2c_slave);
    end

    // monitor state and transaction_complete
    always @(DUT.i2c_state)
        $display("  state=%0d t=%0t", DUT.i2c_state, $time);

    always @(posedge DUT.transaction_complete)
        $display("  TRANSACTION COMPLETE t=%0t reg=0x%01h data=0x%02h",
                 $time, DUT.reg_addr, DUT.rx_byte);

    // ─────────────────────────────────────────────
    //  I2C Master Tasks  (SCL half period = 200ns)
    // ─────────────────────────────────────────────

    parameter HALF = 200;

    task i2c_start;
        begin
            sda_drive = 1'b0;   // release SDA high
            scl       = 1'b1;
            #(HALF);
            sda_drive = 1'b1;   // pull SDA low → START
            #(HALF);
            scl = 1'b0;
            #(HALF);
        end
    endtask

    task i2c_stop;
        begin
            sda_drive = 1'b1;   // hold SDA low
            scl       = 1'b0;
            #(HALF);
            scl       = 1'b1;
            #(HALF);
            sda_drive = 1'b0;   // release SDA → STOP
            #(HALF);
        end
    endtask

    task i2c_send_bit;
        input send_val;
        begin
            scl = 1'b0;
            sda_drive = send_val ? 1'b0 : 1'b1;  // 1=release, 0=pull low
            #(HALF);
            scl = 1'b1;
            #(HALF);
            scl = 1'b0;
            #(HALF);
        end
    endtask

    task i2c_send_byte;
        input [7:0] data;
        output      ack_received;
        integer     j;
        begin
            for (j = 7; j >= 0; j = j - 1)
                i2c_send_bit(data[j]);
            // ACK cycle — release SDA, let slave pull low
            sda_drive = 1'b0;
            scl = 1'b0;
            #(HALF);
            scl = 1'b1;
            ack_received = (sda === 1'b0);
            #(HALF);
            scl = 1'b0;
            #(HALF);
        end
    endtask

    task i2c_read_byte;
        output [7:0] data;
        input        send_ack;
        integer      j;
        begin
            sda_drive = 1'b0;
            data = 8'h00;
            for (j = 7; j >= 0; j = j - 1) begin
                scl = 1'b0;
                #(HALF);
                scl = 1'b1;
                data[j] = sda;
                #(HALF);
                scl = 1'b0;
                #(HALF);
            end
            sda_drive = send_ack ? 1'b1 : 1'b0;
            scl = 1'b0;
            #(HALF);
            scl = 1'b1;
            #(HALF);
            scl = 1'b0;
            #(HALF);
            sda_drive = 1'b0;
        end
    endtask

    task i2c_write;
        input [6:0] addr;
        input [3:0] reg_a;
        input [7:0] data;
        reg         ack1, ack2, ack3;
        begin
            $display("  WRITE addr=0x%02h reg=0x%01h data=0x%02h",
                     addr, reg_a, data);
            i2c_start;
            i2c_send_byte({addr, 1'b0}, ack1);
            i2c_send_byte({4'b0, reg_a}, ack2);
            i2c_send_byte(data, ack3);
            i2c_stop;
            $display("  ACKs addr=%b reg=%b data=%b", ack1, ack2, ack3);
            #(HALF * 4);
        end
    endtask

    task i2c_read;
        input  [6:0] addr;
        input  [3:0] reg_a;
        output [7:0] data;
        reg          ack1, ack2;
        begin
            $display("  READ  addr=0x%02h reg=0x%01h", addr, reg_a);
            i2c_start;
            i2c_send_byte({addr, 1'b0}, ack1);
            i2c_send_byte({4'b0, reg_a}, ack2);
            i2c_start;
            i2c_send_byte({addr, 1'b1}, ack1);
            i2c_read_byte(data, 1'b0);
            i2c_stop;
            $display("  data=0x%02h", data);
            #(HALF * 4);
        end
    endtask

    // ─────────────────────────────────────────────
    //  Stimulus
    // ─────────────────────────────────────────────

    reg [7:0] rval;
    reg       ack;

    always @(DUT.i2c_state)
    $display("  state=%0d t=%0t bit_cnt=%0d shift=0x%02h",
             DUT.i2c_state, $time, DUT.bit_cnt, DUT.shift_reg);
    always @(posedge DUT.scl_rising)
    if (DUT.i2c_state == 2)  // ADDR_ACK
        $display("  ADDR_ACK rw=%b", DUT.rw);
    always @(DUT.start_det)
    if (DUT.start_det)
        $display("  START_DET t=%0t state=%0d", $time, DUT.i2c_state);

    initial begin
        rst_n     = 1'b0;
        mode      = 1'b0;
        scl       = 1'b0;
        sda_drive = 1'b0;
        #40 rst_n = 1'b1;
        mode = 1'b1;
        #200;

        // ── 1: analog mode passthrough ────────────────────────────
        $display("\n1: analog mode passthrough");
        mode = 1'b0;
        #100;
        $display("  v_ref_oc_a=%0d (expect 150)", v_ref_oc_a);
        $display("  v_ref_ov_a=%0d (expect 200)", v_ref_ov_a);
        mode = 1'b1;
        #200;

        // ── 2: write OC_THRESH_A = 120 ───────────────────────────
        $display("\n2: write OC_THRESH_A (reg 0x00) = 120");
        i2c_write(7'h48, 4'h0, 8'd120);
        #200;
        $display("  v_ref_oc_a=%0d (expect 120)", v_ref_oc_a);

        // ── 3: write OV_THRESH_B = 230 ───────────────────────────
        $display("\n3: write OV_THRESH_B (reg 0x03) = 230");
        i2c_write(7'h48, 4'h5, 8'd230);
        #200;
        $display("  v_ref_ov_b=%0d (expect 230)", v_ref_ov_b);

        // ── 4: read FAULT_STATUS ──────────────────────────────────
        $display("\n4: read FAULT_STATUS (reg 0x0B)");
        fault_status = 8'b00000101;
        #100;
        i2c_read(7'h48, 4'hB, rval);
        $display("  fault_status=%0d (expect 5)", rval);

        // ── 5: read FSM_STATE ─────────────────────────────────────
        $display("\n5: read FSM_STATE (reg 0x0C)");
        fsm_state = 3'd3;
        #100;
        i2c_read(7'h48, 4'hC, rval);
        $display("  fsm_state=%0d (expect 3)", rval);

        // ── 6: wrong address ignored ──────────────────────────────
        $display("\n6: wrong address 0x49 — ignored");
        i2c_write(7'h49, 4'h0, 8'd50);
        #200;
        $display("  v_ref_oc_a=%0d (expect 120 unchanged)", v_ref_oc_a);

        // ── 7: CFG_RESET ──────────────────────────────────────────
        $display("\n7: CFG_RESET (reg 0x0E = 0xFF)");
        i2c_write(7'h48, 4'hE, 8'hFF);
        #200;
        $display("  v_ref_oc_a=%0d (expect 150 default)", v_ref_oc_a);
        $display("  v_ref_ov_b=%0d (expect 200 default)", v_ref_ov_b);

        // ── 8: sequential writes ──────────────────────────────────
        $display("\n8: sequential writes");
        i2c_write(7'h48, 4'h0, 8'd100);
        i2c_write(7'h48, 4'h1, 8'd110);
        i2c_write(7'h48, 4'h2, 8'd60);
        #200;
        $display("  v_ref_oc_a=%0d (expect 100)", v_ref_oc_a);
        $display("  v_ref_oc_b=%0d (expect 110)", v_ref_oc_b);
        $display("  v_ref_uv_a=%0d (expect 60)",  v_ref_uv_a);

        // ── 9: analog mode ignores registers ─────────────────────
        $display("\n9: analog mode ignores registers");
        mode = 1'b0;
        #100;
        $display("  v_ref_oc_a=%0d (expect 150 default)", v_ref_oc_a);

        $display("\ndone");
        $finish;
    end

endmodule