module rx_fsm (
    input logic clk,
    input logic rx_en,
    input logic rst_n,
    input logic [2:0] rx_width,             // data bus width (000 = 1 bit, 001 = 2 bits, etc.)
    input logic [7:0] uio_in,               // input pads
    input logic [7:0] uio_ie,               // input pads (~uio_oe)
    input logic [2:0] rx_data_index [7:0],  // bit order map of parallel rx data pads
    input logic [7:0] rx_fsm_cond,          // transition condition for rx_fsm (NOTE: may have multiple conditions in future with LUT3)
    input logic [31:0] rx_fsm_exe,          // execution control for rx_fsm
    output logic rx_out,                    // rx output stream
    output logic [4:0] rx_state             // 32 states; address for corresponding rx_fsm_cond
);

logic [4:0] rx_fsm_state;

logic [7:0] rx_buf;
logic rx_ready;
logic [2:0] serial_ind;



assign rx_out = rx_buf[rx_data_index[serial_ind]];

// Data stream (serialize if parallel)
// If serial stream, should be continuous, no extra cycle between frames
always_ff @(posedge clk or negedge rst_n) begin
    if (!rx_en || !rst_n) begin
        rx_buf <= 8'b0;
        rx_ready <= 1'b1;
        serial_ind <= 3'b0;
        rx_state <= 5'b0;
    end else begin
        if (rx_ready) begin
            rx_buf <= uio_in;
            serial_ind <= 3'b0;
        end else begin
            serial_ind <= serial_ind + 1'b1;
        end
        if (serial_ind == rx_width) begin // NOTE width limit
            rx_ready <= 1'b1;
        end else begin
            rx_ready <= 1'b0;
        end
    end
end

// LUT state machine
// NOTE: state vector may not just be rx_buf. May need to include other signals like bit count.
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rx_fsm_state <= 5'b0;
    end else if (~|((rx_buf ^ rx_fsm_cond) & uio_ie)) begin
        rx_exe(rx_fsm_exe, rx_fsm_state, uio_in, uio_ie);
    end
end

endmodule

module rx_exe (
    input logic [31:0] rx_fsm_exe,
    input logic [4:0] rx_fsm_state,
    input logic [7:0] uio_in,
    input logic [7:0] uio_ie
);
    // ...
    // How much to jump fsm state
    // Potentially gate TX signal (like how reading line busy must block transmission)
    // 
endmodule