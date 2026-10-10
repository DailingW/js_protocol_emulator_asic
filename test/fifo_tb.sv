`default_nettype none
`timescale 1ns/1ps

module fifo_tb;
  logic clk = 0;
  logic rst_n = 0;
  logic [7:0] wr_data = 0;
  logic wr_en = 0, rd_en = 0;
  wire [7:0] rd_data;
  wire full, empty;
  fifo dut (.*);
  always #5 clk = ~clk;

  logic [7:0] expected [0:7];
  integer count = 0, head = 0, tail = 0;

  task automatic check_outputs;
    if (full !== (count == 8) || empty !== (count == 0))
      $fatal(1, "FIFO flags disagree with occupancy %0d", count);
    if (count == 0) begin
      if (rd_data !== 8'b0) $fatal(1, "Empty FIFO output is not zero");
    end else if (rd_data !== expected[head]) begin
      $fatal(1, "FIFO order: expected %02h, got %02h", expected[head], rd_data);
    end
  endtask

  task automatic step(input logic write_request, read_request, input logic [7:0] data);
    logic do_read, do_write;
    @(negedge clk);
    wr_en = write_request;
    rd_en = read_request;
    wr_data = data;
    check_outputs();
    do_read = read_request && count != 0;
    do_write = write_request && (count != 8 || do_read);
    if (do_read) head = (head + 1) % 8;
    if (do_write) begin
      expected[tail] = data;
      tail = (tail + 1) % 8;
    end
    count = count + integer'(do_write) - integer'(do_read);
    @(posedge clk);
    #1;
    check_outputs();
  endtask

  initial begin
    repeat (2) @(negedge clk);
    rst_n = 1;
    #1;
    check_outputs();
    step(0, 1, 0); // Empty read is ignored.
    step(1, 1, 8'hA5); // Empty simultaneous requests enqueue one byte.
    step(1, 1, 8'h3C); // Replace the sole queued byte.
    step(0, 1, 0);
    for (integer i = 0; i < 8; i++) step(1, 0, 8'(i));
    step(1, 0, 8'hEE); // Full write is ignored.
    step(1, 1, 8'h96); // Full simultaneous read/write must accept both.
    for (integer i = 0; i < 8; i++) step(0, 1, 0);
    for (integer i = 0; i < 500; i++)
      step(1'($urandom_range(0, 1)), 1'($urandom_range(0, 1)), 8'($urandom));
    // Reset while occupied discards all data without resetting memory cells.
    @(negedge clk);
    rst_n = 0;
    count = 0;
    head = 0;
    tail = 0;
    #1;
    check_outputs();
    $display("FIFO boundary and 500 randomized operations passed");
    $finish;
  end
endmodule
