module fsm_main (
    input logic clk,
    input logic rx_en,
    input logic tx_en,
    input logic rst_n,

    input logic [7:0] uio_in,               // input pads

    // Single-port state memory; addresses select one of 64 128-bit words.
    // Keep this interface explicit until the FSM fetch/loader logic is added.
    input logic state_mem_en,
    input logic state_mem_we,
    input logic [5:0] state_mem_addr,
    input logic [127:0] state_mem_wdata,
    input logic [127:0] state_mem_wmask,    // 1 = write this bit
    output wire [127:0] state_word,        // clocked SRAM read output
    output wire state_word_valid,

    output logic [5:0] state,              // 64 states
    output logic [15:0] count,
    output logic [15:0] timer
);

// SRAM memory
// - State memory for the FSM 2x 64x64 per FSM, 4 total (RX and TX FSM)
// Flip Flop CSRs (?)
// - Bit order map 8x 3b per FSM, 48b total
// - Counter 4x 16b per FSM, 128b total
// - Counter limit 4x 16b per FSM, 128b total
// - (optional) Counter alternate limits 4x 16b per counter limit, 256b total
// - flags, 2b per FSM, 4b total
// - RX pattern match registers 4x 32b, 128b total
// - State counter 6b per FSM, 12b total

// Each fsm_main owns two 64x64 macros. A read completes after the accepting
// rising edge with state_word_valid high; writes/idle hold state_word.
// Reset blocks accesses without clearing SRAM. Program words before use.
// The future fetch controller must account for the synchronous read latency.
sram_logic u_state_mem (
    .clk(clk),
    .rst_n(rst_n),
    .en(state_mem_en),
    .we(state_mem_we),
    .word_addr(state_mem_addr),
    .wdata(state_mem_wdata),
    .wmask(state_mem_wmask),
    .rdata(state_word),
    .rvalid(state_word_valid)
);

logic [7:0] uio_in_prev;  // last sampled pad state
logic uio_in_prev_valid;  // initial settling on startup doesn't count
logic [7:0] rise, fall;   // rising edge, falling edge detection
assign rise = uio_in_prev_valid ? (uio_in & ~uio_in_prev) : 8'b0;
assign fall = uio_in_prev_valid ? (~uio_in & uio_in_prev) : 8'b0;

always_ff @(posedge clk or negedge rst_n) begin
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
