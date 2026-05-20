// Comparator needs to :
// 1. Compare two numbers, one is the input and the other is a threshold value
// 2. Output 1 if the first number is greater than the second, otherwise output 0
// Value: inputs for v_in, v_ref, hyst etc, outputs fault signal
// Vin, Vref, Hyst, Vout
module comparator #(
    parameter WIDTH = 8
)(
    input wire [WIDTH-1:0] v_in,
    input wire [WIDTH-1:0] v_ref,
    input wire [WIDTH-1:0] hyst,
    input wire             clk,
    input wire             rst_n,
    output reg             fault
);


always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin // reset state
        fault <= 1'b0;                      // fault recovery forced
    end else begin // non-reset state
        if (fault) begin // fault present
            if (v_in < (v_ref - hyst)) begin
                fault <= 1'b0;              // fault recovered naturally
            end
        end else begin // fault = 0
            if (v_in >= (v_ref)) begin
                fault <= 1'b1;              // fault asserted
            end
        end
    end
end

endmodule