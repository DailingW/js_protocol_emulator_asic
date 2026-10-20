// SPDX-License-Identifier: Apache-2.0
`timescale 1ns/1ps
`default_nettype none

module tb_sram;
  reg clk = 1'b0;
  reg program_en = 1'b0;
  reg program_we = 1'b0;
  reg [3:0] program_be = 4'b0;
  reg [9:0] program_word_addr = 10'b0;
  reg [31:0] program_wdata = 32'b0;
  wire [31:0] program_rdata;
  reg data_en = 1'b0;
  reg data_we = 1'b0;
  reg [3:0] data_be = 4'b0;
  reg [8:0] data_word_addr = 9'b0;
  reg [31:0] data_wdata = 32'b0;
  wire [31:0] data_rdata;

  sram_banks u_memories (.*);
endmodule

`default_nettype wire
