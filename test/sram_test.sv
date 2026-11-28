// SPDX-License-Identifier: Apache-2.0
`timescale 1ns/1ps
`default_nettype none

module sram_test;
  reg clk = 1'b0;
  always #10 clk = !clk;

  reg rst_n = 1'b0;
  reg en = 1'b0;
  reg we = 1'b0;
  reg [5:0] addr = 6'b0;
  reg [127:0] wdata = 128'b0;
  reg [127:0] wmask = 128'b0;
  wire [127:0] rdata;
  wire rvalid;
  reg [127:0] expected [0:63];
  reg [127:0] held_data;
  integer i;

  fsm_main dut (
    .clk(clk), .rx_en(1'b0), .tx_en(1'b0), .rst_n(rst_n), .uio_in(8'b0),
    .state_mem_en(en), .state_mem_we(we), .state_mem_addr(addr),
    .state_mem_wdata(wdata), .state_mem_wmask(wmask),
    .state_word(rdata), .state_word_valid(rvalid),
    .state(), .count(), .timer()
  );

  task automatic write_word(input [5:0] a, input [127:0] d, input [127:0] m);
    @(negedge clk);
    en = 1'b1;
    we = 1'b1;
    addr = a;
    wdata = d;
    wmask = m;
    @(posedge clk);
    #1;
    if (rvalid !== 1'b0) $fatal(1, "Write asserted read-valid");
    expected[a] = (expected[a] & ~m) | (d & m);
  endtask

  task automatic read_word(input [5:0] a);
    @(negedge clk);
    held_data = rdata;
    en = 1'b1;
    we = 1'b0;
    addr = a;
    #1;
    if (rdata !== held_data) $fatal(1, "Read changed before clock edge");
    @(posedge clk);
    #1;
    if (rvalid !== 1'b1 || rdata !== expected[a])
      $fatal(1, "Read addr=%0d expected=%032h got=%032h valid=%b",
             a, expected[a], rdata, rvalid);
  endtask

  initial begin
    // Ensure reset clears the response flag before any memory access.
    repeat (2) @(negedge clk);
    if (rvalid !== 1'b0) $fatal(1, "Reset did not clear read-valid");
    rst_n = 1'b1;

    // Different patterns in both halves catch swapped lanes/address aliasing.
    // Full-mask writes initialize every SRAM word without an RTL reset loop.
    for (i = 0; i < 64; i = i + 1)
      write_word(i[5:0], {32'h89abcdef ^ i, 32'h76543210 + i,
                          32'h01234567 ^ i, 32'hfedcba98 - i}, {128{1'b1}});
    for (i = 0; i < 64; i = i + 1) read_word(i[5:0]);

    // Consecutive identical reads and read-output hold on write-only cycles.
    read_word(6'd17);
    read_word(6'd17);
    held_data = rdata;
    write_word(6'd17, 128'hffffffffffffffff_0000000000000000,
                         128'h0000000000000000_ffffffffffffffff);
    if (rdata !== held_data) $fatal(1, "Write-only changed read output");
    read_word(6'd17);
    write_word(6'd17, 128'h0123456789abcdef_ffffffffffffffff,
                         128'hffffffffffffffff_0000000000000000);
    read_word(6'd17);

    // Bit masks across the 63/64 bank boundary and at the outermost bits.
    write_word(6'd17, ~expected[17],
                         128'h8000000000000001_8000000000000001);
    read_word(6'd17);
    // A zero mask must preserve every bit in both banks.
    write_word(6'd17, ~expected[17], 128'b0);
    read_word(6'd17);

    // Neither reads nor writes take effect while memory enable is low.
    @(negedge clk);
    held_data = rdata;
    en = 1'b0;
    we = 1'b1;
    wdata = ~expected[17];
    wmask = {128{1'b1}};
    @(posedge clk);
    #1;
    if (rvalid !== 1'b0 || rdata !== held_data)
      $fatal(1, "Disabled write changed output/valid");
    @(negedge clk);
    we = 1'b0;
    addr = 6'd63;
    @(posedge clk);
    #1;
    if (rvalid !== 1'b0 || rdata !== held_data)
      $fatal(1, "Disabled read changed output/valid");
    read_word(6'd17);

    // Reset cancels accesses/valid without erasing stored state words.
    @(negedge clk);
    rst_n = 1'b0;
    en = 1'b1;
    we = 1'b1;
    addr = 6'd17;
    wdata = ~expected[17];
    wmask = {128{1'b1}};
    #1;
    if (rvalid !== 1'b0) $fatal(1, "Reset did not clear valid asynchronously");
    repeat (2) @(posedge clk);
    #1;
    if (rdata !== held_data) $fatal(1, "Reset changed SRAM output");
    @(negedge clk);
    en = 1'b0;
    we = 1'b0;
    rst_n = 1'b1;
    for (i = 63; i >= 0; i = i - 1) read_word(i[5:0]);

    $display("PASS: fsm_main SRAM: 64 x 128, synchronous reads, masks, enables, reset retention");
    $finish;
  end

  initial begin
    #100000;
    $fatal(1, "SRAM test timed out");
  end
endmodule

`default_nettype wire
