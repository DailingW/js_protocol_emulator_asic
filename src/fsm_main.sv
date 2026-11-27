module fsm_main (
    input logic clk,
    input logic rx_en,
    input logic tx_en,
    input logic rst_n,

    input logic [7:0] uio_in,               // input pads
    input logic [127:0] state_word,         // retrieved using state value

    output logic [5:0] state,              // 64 states
    output logic [15:0] count,
    output logic [15:0] timer
);

logic [7:0] uio_in_prev;  // last sampled pad state
logic uio_in_prev_valid;  // initial settling on startup doesn't count
logic [7:0] rise, fall;   // rising edge, falling edge detection
assign rise = uio_in_prev_valid ? (uio_in & ~uio_in_prev) : 8'b0;
assign fall = uio_in_prev_valid ? (~uio_in & uio_in_prev) : 8'b0;

always_ff (posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        uio_in_prev <= 8'b0;
        uio_in_prev_valid <= 1'b0;
    end else begin
        uio_in_prev <= uio_in;
        uio_in_prev_valid <= 1'b1;
    end
end

// FSM logic goes here

endmodule