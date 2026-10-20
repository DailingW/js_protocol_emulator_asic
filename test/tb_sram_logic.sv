// SPDX-License-Identifier: Apache-2.0
`timescale 1ns/1ps
`default_nettype none

module tb_sram_logic;
  reg clk = 1'b0;
  reg rst_n = 1'b0;
  reg ena = 1'b0;
  reg instr_req = 1'b0;
  reg [31:0] instr_addr = 32'b0;
  wire instr_gnt, instr_rvalid, instr_err;
  wire [31:0] instr_rdata;
  reg data_req = 1'b0;
  reg data_we = 1'b0;
  reg [3:0] data_be = 4'b0;
  reg [31:0] data_addr = 32'b0;
  reg [31:0] data_wdata = 32'b0;
  wire data_gnt, data_rvalid, data_err;
  wire [31:0] data_rdata;
  wire program_en, program_we;
  wire [3:0] program_be;
  wire [9:0] program_word_addr;
  wire [31:0] program_wdata, program_rdata;
  wire data_mem_en, data_mem_we;
  wire [3:0] data_mem_be;
  wire [8:0] data_mem_word_addr;
  wire [31:0] data_mem_wdata, data_mem_rdata;

  sram_logic u_logic (.*);
  sram_banks u_mem (
    .clk(clk),
    .program_en(program_en),
    .program_we(program_we),
    .program_be(program_be),
    .program_word_addr(program_word_addr),
    .program_wdata(program_wdata),
    .program_rdata(program_rdata),
    .data_en(data_mem_en),
    .data_we(data_mem_we),
    .data_be(data_mem_be),
    .data_word_addr(data_mem_word_addr),
    .data_wdata(data_mem_wdata),
    .data_rdata(data_mem_rdata)
  );

  // Test-only preload substitutes for the future external loader.
  initial begin
    for (integer i = 0; i < 1024; i = i + 1)
      u_mem.u_program.i_SRAM_1P_behavioral_bm_bist.memory[i] = 32'ha5000000 + i;
    for (integer i = 0; i < 512; i = i + 1)
      u_mem.u_data.i_SRAM_1P_behavioral_bm_bist.memory[i] = 32'h5a000000 + i;
  end
endmodule

`default_nettype wire
