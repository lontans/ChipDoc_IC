// testbench for i2c_slave module
// bit-bangs SCL and SDA to simulate an I2C master
`timescale 1ns/1ps

module tb_i2c_slave;

    // DUT signals
    reg        clk, rst_n;
    reg        mode;
    reg        scl;
    reg        sda_drive;       // testbench drives SDA low or releases
    wire       sda;             // bidirectional SDA
    wire       sda_oe;          // slave output enable

    // default threshold inputs
    reg  [7:0]  v_ref_oc_a_dflt = 8'd150;
    reg  [7:0]  v_ref_oc_b_dflt = 8'd150;
    reg  [7:0]  v_ref_uv_a_dflt = 8'd80;
    reg  [7:0]  v_ref_uv_b_dflt = 8'd80;
    reg  [7:0]  v_ref_ov_a_dflt = 8'd200;
    reg  [7:0]  v_ref_ov_b_dflt = 8'd200;
    reg  [7:0]  v_ref_ot_dflt   = 8'd180;
    reg  [7:0]  hyst_dflt        = 8'd10;
    reg  [15:0] hb_timeout_dflt  = 16'd10000;

    // status inputs from FSM
    reg  [7:0]  fault_status = 8'b00000000;
    reg  [2:0]  fsm_state    = 3'd1;  // NORMAL

    // configured outputs
    wire [7:0]  v_ref_oc_a, v_ref_oc_b;
    wire [7:0]  v_ref_uv_a, v_ref_uv_b;
    wire [7:0]  v_ref_ov_a, v_ref_ov_b;
    wire [7:0]  v_ref_ot;
    wire [7:0]  hyst;
    wire [15:0] hb_timeout;

    // open drain SDA — both master (testbench) and slave (DUT) can pull low
    assign sda = (sda_drive || sda_oe) ? 1'b0 : 1'b1;

    // instantiate DUT
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

    // internal clock — 100MHz
    initial clk = 0;
    always #5 clk = ~clk;
    
    always @(posedge DUT.byte_done_r2)
    $display("  byte_done t=%0t state=%0d latch=0x%02h addr_match=%b", 
             $time, DUT.i2c_state, DUT.sda_byte_latch,
             (DUT.sda_byte_latch[7:1] == 7'h48));

    always @(posedge DUT.transaction_complete)
        $display("  TRANSACTION COMPLETE t=%0t reg=%0h data=0x%02h",
                $time, DUT.reg_addr, DUT.sda_byte_latch);

    always @(DUT.i2c_state)
        $display("  state change t=%0t state=%0d",
                $time, DUT.i2c_state);

    // waveform dump
    initial begin
        $dumpfile("tb_i2c_slave.vcd");
        $dumpvars(0, tb_i2c_slave);
    end
    always @(posedge DUT.transaction_complete)
    $display("  transaction_complete HIGH at t=%0t", $time);

    always @(posedge DUT.byte_done_r2)
        $display("  byte_done HIGH at t=%0t", $time);

    always @(posedge DUT.byte_done_scl)
        $display("  byte_done_scl HIGH at t=%0t", $time);

    // ─────────────────────────────────────────────
    //  I2C Master Tasks
    //  SCL half period = 100ns (5MHz, slow for sim)
    // ─────────────────────────────────────────────

    parameter HALF = 100;

    // START: SDA falls while SCL high
    task i2c_start;
        begin
            sda_drive = 1'b0;  // release SDA high
            scl       = 1'b1;
            #(HALF);
            sda_drive = 1'b1;  // pull SDA low → START
            #(HALF);
            scl = 1'b0;
            #(HALF);
        end
    endtask

    // STOP: SDA rises while SCL high
    task i2c_stop;
        begin
            sda_drive = 1'b1;  // hold SDA low
            scl       = 1'b0;
            #(HALF);
            scl       = 1'b1;
            #(HALF);
            sda_drive = 1'b0;  // release SDA → STOP
            #(HALF);
        end
    endtask

    // send one bit — set SDA before rising SCL edge
    task i2c_send_bit;
        input send_val;
        begin
            scl = 1'b0;
            if (send_val)
                sda_drive = 1'b0;   // release — pullup = 1
            else
                sda_drive = 1'b1;   // pull low = 0
            #(HALF);
            scl = 1'b1;
            #(HALF);
            scl = 1'b0;
            #(HALF);
        end
    endtask

    // send byte MSB first, then clock one ACK cycle
    // returns ack_received = 1 if slave pulled SDA low
    task i2c_send_byte;
        input [7:0] data;
        output      ack_received;
        integer     j;
        begin
            for (j = 7; j >= 0; j = j - 1)
                i2c_send_bit(data[j]);
            // ACK cycle
            sda_drive = 1'b0;  // release
            scl = 1'b0;
            #(HALF);
            scl = 1'b1;
            #(HALF);
            ack_received = (sda === 1'b0);  // === checks for exact 0, not z or x
            scl = 1'b0;
            #(HALF);
        end
    endtask

    // read one byte, send ACK or NAK after
    task i2c_read_byte;
        output [7:0] data;
        input        send_ack;
        integer      j;
        begin
            sda_drive = 1'b0;  // release SDA — slave drives
            data = 8'h00;
            for (j = 7; j >= 0; j = j - 1) begin
                scl = 1'b0;
                #(HALF);
                scl = 1'b1;
                data[j] = sda;  // sample on rising SCL
                #(HALF);
                scl = 1'b0;
                #(HALF);
            end
            // ACK or NAK
            if (send_ack)
                sda_drive = 1'b1;  // pull low = ACK
            else
                sda_drive = 1'b0;  // release = NAK
            scl = 1'b0;
            #(HALF);
            scl = 1'b1;
            #(HALF);
            scl = 1'b0;
            #(HALF);
            sda_drive = 1'b0;
        end
    endtask

    // full write transaction
    task i2c_write;
        input [6:0] addr;
        input [3:0] reg_a;
        input [7:0] data;
        reg         ack1, ack2, ack3;
        begin
            $display("  I2C WRITE addr=0x%02h reg=0x%01h data=0x%02h", addr, reg_a, data);
            i2c_start;
            i2c_send_byte({addr, 1'b0}, ack1);
            i2c_send_byte({4'b0, reg_a}, ack2);
            i2c_send_byte(data, ack3);
            i2c_stop;
            $display("  ACKs: addr=%b reg=%b data=%b", ack1, ack2, ack3);
            #(HALF * 4);
        end
    endtask

    // full read transaction
    task i2c_read;
        input  [6:0] addr;
        input  [3:0] reg_a;
        output [7:0] data;
        reg          ack1, ack2;
        begin
            $display("  I2C READ  addr=0x%02h reg=0x%01h", addr, reg_a);
            i2c_start;
            i2c_send_byte({addr, 1'b0}, ack1);   // write reg address first
            i2c_send_byte({4'b0, reg_a}, ack2);
            i2c_start;                             // repeated START
            i2c_send_byte({addr, 1'b1}, ack1);   // read
            i2c_read_byte(data, 1'b0);            // NAK on last byte
            i2c_stop;
            $display("  read data=0x%02h", data);
            #(HALF * 4);
        end
    endtask

    // ─────────────────────────────────────────────
    //  Stimulus
    // ─────────────────────────────────────────────

    reg [7:0] read_val;
    reg       ack;

    initial begin
        rst_n     = 1'b0;
        mode      = 1'b0;
        scl       = 1'b0;
        sda_drive = 1'b0;

        #40 rst_n = 1'b1;
        mode = 1'b1;  // digital mode — registers active
        #100;

        // ── scenario 1: analog mode passthrough ──────────────────
        // mode=0, all outputs should equal defaults regardless of registers
        $display("\nscenario 1: analog mode — outputs should equal defaults");
        mode = 1'b0;
        #50;
        $display("  v_ref_oc_a=%0d (expect 150)", v_ref_oc_a);
        $display("  v_ref_ov_a=%0d (expect 200)", v_ref_ov_a);
        #100;

        // switch to digital mode for rest of tests
        mode = 1'b1;
        #100;

        // ── scenario 2: write OC threshold A ─────────────────────
        $display("\nscenario 2: write OC_THRESH_A (reg 0x00) = 120");
        i2c_write(7'h48, 4'h0, 8'd120);
        $display("  v_ref_oc_a=%0d (expect 120)", v_ref_oc_a);

        // ── scenario 3: write OV threshold B ─────────────────────
        $display("\nscenario 3: write OV_THRESH_B (reg 0x03) = 230");
        i2c_write(7'h48, 4'h3, 8'd230);
        $display("  v_ref_ov_b=%0d (expect 230)", v_ref_ov_b);

        // ── scenario 4: write HB timeout low byte ────────────────
        $display("\nscenario 4: write HB_TIMEOUT_L (reg 0x08) = 0x64");
        i2c_write(7'h48, 4'h8, 8'h64);
        $display("  hb_timeout=%0d (expect low byte = 0x64)", hb_timeout);

        // ── scenario 5: read fault status ────────────────────────
        $display("\nscenario 5: read FAULT_STATUS (reg 0x0B)");
        fault_status = 8'b00000001;  // inject oc_a fault
        #50;
        i2c_read(7'h48, 4'hB, read_val);
        $display("  fault_status register=%0d (expect 1)", read_val);

        // ── scenario 6: read FSM state ────────────────────────────
        $display("\nscenario 6: read FSM_STATE (reg 0x0C)");
        fsm_state = 3'd3;  // inject FAULT state
        #50;
        i2c_read(7'h48, 4'hC, read_val);
        $display("  fsm_state register=%0d (expect 3)", read_val);

        // ── scenario 7: wrong address — ignored ──────────────────
        $display("\nscenario 7: wrong address 0x49 — should be ignored");
        i2c_write(7'h49, 4'h0, 8'd50);
        $display("  v_ref_oc_a=%0d (expect 120, unchanged)", v_ref_oc_a);

        // ── scenario 8: CFG_RESET — reload all defaults ──────────
        $display("\nscenario 8: CFG_RESET (reg 0x0E = 0xFF)");
        i2c_write(7'h48, 4'hE, 8'hFF);
        $display("  v_ref_oc_a=%0d (expect 150 default)", v_ref_oc_a);
        $display("  v_ref_ov_b=%0d (expect 200 default)", v_ref_ov_b);

        // ── scenario 9: multiple writes sequential ────────────────
        $display("\nscenario 9: sequential writes to multiple registers");
        i2c_write(7'h48, 4'h0, 8'd100);  // OC_A
        i2c_write(7'h48, 4'h1, 8'd110);  // OC_B
        i2c_write(7'h48, 4'h4, 8'd60 );  // UV_A
        $display("  v_ref_oc_a=%0d (expect 100)", v_ref_oc_a);
        $display("  v_ref_oc_b=%0d (expect 110)", v_ref_oc_b);
        $display("  v_ref_uv_a=%0d (expect 60)",  v_ref_uv_a);

        // ── scenario 10: analog mode ignores registers ────────────
        $display("\nscenario 10: switch back to analog — registers ignored");
        mode = 1'b0;
        #50;
        $display("  v_ref_oc_a=%0d (expect 150 default, not 100)", v_ref_oc_a);

        $display("\nall scenarios complete");
        $finish;
    end

endmodule