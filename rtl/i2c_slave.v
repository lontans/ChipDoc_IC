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
    input  wire [7:0]  v_ref_uv_a_dflt,
    input  wire [7:0]  v_ref_uv_b_dflt,
    input  wire [7:0]  v_ref_ov_a_dflt,
    input  wire [7:0]  v_ref_ov_b_dflt,
    input  wire [7:0]  v_ref_ot_dflt,
    input  wire [7:0]  hyst_dflt,
    input  wire [15:0] hb_timeout_dflt,
    input  wire [7:0]  fault_status, // fault_status: oc_a, oc_b, uv_a, uv_b, ov_a, ov_b, ot, hb_fault
    input  wire [2:0]  fsm_state,

    // configured values out
    output  wire [7:0]  v_ref_oc_a,
    output  wire [7:0]  v_ref_oc_b,
    output  wire [7:0]  v_ref_uv_a,
    output  wire [7:0]  v_ref_uv_b,
    output  wire [7:0]  v_ref_ov_a,
    output  wire [7:0]  v_ref_ov_b,
    output  wire [7:0]  v_ref_ot,
    output  wire [7:0]  hyst,
    output  wire [15:0] hb_timeout
);

// Parameters and State Encoding:
localparam MY_ADDR = 7'h48; // can be overwritten by mode pin
localparam I2C_IDLE      = 4'd0;
localparam I2C_ADDR      = 4'd1;
localparam I2C_ADDR_ACK  = 4'd2;
localparam I2C_REG       = 4'd3;
localparam I2C_REG_ACK   = 4'd4;
localparam I2C_DATA_W    = 4'd5;
localparam I2C_DATA_ACK  = 4'd6;
localparam I2C_DATA_R    = 4'd7;
localparam I2C_READ_ACK  = 4'd8;

// Internal Signals
reg sda_prev;
wire start_det;
wire stop_det;
reg sda_oe;  // 1 = pull low (ACK), 0 = release

// Shift register and byte tracking
reg [7:0] sda_buffer;  // shifts in bits from SDA, complete byte read when bit_cnt==7, becomes data
reg [2:0] bit_cnt;
reg [1:0] byte_num;

// Transaction state
reg [3:0] i2c_state;
reg [3:0] reg_addr;
reg transaction_complete;
reg rw;

// Read Data Mux Output
reg [7:0] read_data; // Data to shift out during transactions

// Register File
reg [7:0] registers [0:13]; // 14 2D Registers, 8 Bits Wide

// START/STOP detect:
always @ (posedge clk or negedge rst_n) begin // still using internal clock
    if (!rst_n)
        sda_prev <= 1'b1; // lags one cycle behind sda during the internal clk high time, rst can cause start
    else if (scl)
        sda_prev <= sda; // lags one cycle behind sda during the internal clk high time, so sda_prev is stored while sda can change
end
assign start_det = scl && sda_prev && !sda; // SDA falls, SCL high
assign stop_det  = scl && !sda_prev && sda; // SDA rises, SCL high


// Shift Register, using scl since sampling scl based signals
always @(posedge scl or negedge rst_n) begin
    if (!rst_n) 
        sda_buffer <= 8'h00;
    else
        sda_buffer <= {sda_buffer[6:0], sda} // shift sda_buffer left, new bit at LSb
end

// Bit counter
always @(posedge scl or negedge rst_n or start_det) begin
    if (!rst_n || start_det)
        bit_cnt <= 3'd0; // Start bit, restart at 0
    else
        bit_cnt <= bit_cnt + 1  // increment the bit count
end

// Parameters and State Encoding:
localparam MY_ADDR = 7'h48; // can be overwritten by mode pin
localparam I2C_IDLE      = 4'd0;
localparam I2C_ADDR      = 4'd1;
localparam I2C_ADDR_ACK  = 4'd2;
localparam I2C_REG       = 4'd3;
localparam I2C_REG_ACK   = 4'd4;
localparam I2C_DATA_W    = 4'd5;
localparam I2C_DATA_ACK  = 4'd6;
localparam I2C_DATA_R    = 4'd7;
localparam I2C_READ_ACK  = 4'd8;

// I2C Slave FSM (Internal CLK Clocked)
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        i2c_state            <= I2C_IDLE;
        byte_num             <= 2'd0;
        rw                   <= 1'b0; // write
        reg_addr             <= 4'd0; // 0th register
        transaction_complete <= 1'b0;
        sda_oe               <= 1'b0; // release output
    end else begin
        transaction_complete <= 1'b0;

        if (stop_det) begin // Cover bases when stop detected, go back to idle, release output
            i2c_state <= I2C_IDLE;
            sda_oe    <= 1'b0;
        end else begin
            case (i2c_state)
                I2C_IDLE: begin
                    if (start_det) begin
                        i2c_state <= I2C_ADDR; // start receiving address in next cycle
                        byte_num <= 2'd1;      // byte becomes the first byte
                    end
                end
                I2C_ADDR: begin
                    
                end
                I2C_ADDR_ACK: begin
                    
                end
                I2C_REG: begin
                    
                end
                I2C_REG_ACK: begin
                    
                end
                I2C_DATA_W: begin
                    
                end
                I2C_DATA_ACK: begin
                    
                end
                I2C_DATA_R: begin
                    
                end
                I2C_READ_ACK begin
                    
                end
                default: 
        
            endcase
        end
    end
end



// Register File
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin // Loading dflt values on reset
        registers[0] <= v_ref_oc_a_dflt;
        registers[1] <= v_ref_oc_b_dflt;
        registers[2] <= v_ref_uv_a_dflt;
        registers[3] <= v_ref_uv_b_dflt;
        registers[4] <= v_ref_ov_a_dflt;
        registers[5] <= v_ref_ov_b_dflt;
        registers[6] <= v_ref_ot_dflt;
        registers[7] <= hyst_dflt;
        registers[8] <= hb_timeout_dflt[7:0];
        registers[9] <= hb_timeout_dflt[15:8];
    end else begin
        if (!rw && reg_addr == 4'he && sda_buffer == 8'hFF) begin  // Load dflt values per MCU instruction
            registers[0] <= v_ref_oc_a_dflt;
            registers[1] <= v_ref_oc_b_dflt;
            registers[2] <= v_ref_uv_a_dflt;
            registers[3] <= v_ref_uv_b_dflt;
            registers[4] <= v_ref_ov_a_dflt;
            registers[5] <= v_ref_ov_b_dflt;
            registers[6] <= v_ref_ot_dflt;
            registers[7] <= hyst_dflt;
            registers[8] <= hb_timeout_dflt[7:0];
            registers[9] <= hb_timeout_dflt[15:8];
        end else if (!rw && transaction_complete) begin
            registers[reg_addr] <= sda_buffer; // Write to the write address if write enabled
        end
    end
end

// Read Data Mux
always @(*) begin
    case (reg_addr)
        4'hB:    read_data = fault_status;
        4'hC:    read_data = {5'b0, fsm_state};
        default: read_data = registers[reg_addr];
    endcase
end

// Output Mux (Analog vs Digital Mode)

// Mux chooses between registers and defaults based on mode
assign v_ref_oc_a = (mode) ? registers[0] : v_ref_oc_a_dflt;
assign v_ref_oc_b = (mode) ? registers[1] : v_ref_oc_b_dflt;
assign v_ref_uv_a = (mode) ? registers[2] : v_ref_uv_a_dflt;
assign v_ref_uv_b = (mode) ? registers[3] : v_ref_uv_b_dflt;
assign v_ref_ov_a = (mode) ? registers[4] : v_ref_ov_a_dflt;
assign v_ref_ov_b = (mode) ? registers[5] : v_ref_ov_b_dflt;
assign v_ref_ot   = (mode) ? registers[6] : v_ref_ot_dflt;
assign hyst       = (mode) ? registers[7] : hyst_dflt;
assign hb_timeout = (mode) ? {registers[9], registers[8]} : hb_timeout_dflt;

endmodule