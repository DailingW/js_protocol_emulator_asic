`default_nettype none
`timescale 1ns/1ps

// Python drives the parallel interfaces. HDL connects the serial interfaces.
module tb_dual;
  reg clk;
  reg rst_n;
  reg ena;

  reg [7:0] a_tx_data, b_tx_data;
  reg a_tx_valid, b_tx_valid;
  reg a_rx_ready, b_rx_ready;
  wire [7:0] a_rx_data, b_rx_data;
  wire a_tx_ready, b_tx_ready;
  wire a_rx_valid, b_rx_valid;
  wire a_fifo_full, b_fifo_full;
  wire a_rx_error, b_rx_error;
  wire a_tx, b_tx;
  wire a_rx, b_rx;

  // Cross-connect the UARTs: TX from one chip goes to RX on the other.
  assign a_rx = b_tx;
  assign b_rx = a_tx;

  wire [7:0] a_uio_in, b_uio_in;
  wire [7:0] a_uio_out, b_uio_out;
  wire [7:0] a_uio_oe, b_uio_oe;
  // Inputs: bit 7 = serial RX, bit 3 = RX_READY, bit 0 = TX_VALID.
  assign a_uio_in = {a_rx, 3'b000, a_rx_ready, 2'b00, a_tx_valid};
  assign b_uio_in = {b_rx, 3'b000, b_rx_ready, 2'b00, b_tx_valid};
  // Expose named signals to Python instead of packed pin masks.
  assign a_tx_ready = a_uio_out[1];
  assign b_tx_ready = b_uio_out[1];
  assign a_rx_valid = a_uio_out[2];
  assign b_rx_valid = b_uio_out[2];
  assign a_fifo_full = a_uio_out[4];
  assign b_fifo_full = b_uio_out[4];
  assign a_rx_error = a_uio_out[5];
  assign b_rx_error = b_uio_out[5];
  assign a_tx = a_uio_out[6];
  assign b_tx = b_uio_out[6];

  tt_um_protocolemu_dailingw uart_a (
    .ui_in(a_tx_data), .uo_out(a_rx_data),
    .uio_in(a_uio_in), .uio_out(a_uio_out), .uio_oe(a_uio_oe),
    .ena(ena), .clk(clk), .rst_n(rst_n)
  );

  tt_um_protocolemu_dailingw uart_b (
    .ui_in(b_tx_data), .uo_out(b_rx_data),
    .uio_in(b_uio_in), .uio_out(b_uio_out), .uio_oe(b_uio_oe),
    .ena(ena), .clk(clk), .rst_n(rst_n)
  );

  initial begin
    $dumpfile("tb_dual.fst");
    $dumpvars(0, tb_dual);
    #1;
  end
endmodule
