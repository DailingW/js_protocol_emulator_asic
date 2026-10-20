// SPDX-License-Identifier: Apache-2.0
`default_nettype none

// Physical SRAM instances, shared by synthesis and simulation.
// Addresses here count 32-bit WORDS. A CPU bus adapter must decode byte
// addresses and drop bits [1:0] before driving these ports.
// Each enabled operation is sampled on the rising clock edge; read data
// becomes available after that edge. SRAM contents have no reset value.
// This wrapper provides neither Ibex handshakes nor a program loader.
module sram_banks (
    input  wire        clk,
    input  wire        program_en,
    input  wire        program_we,
    input  wire  [3:0] program_be,
    input  wire  [9:0] program_word_addr,
    input  wire [31:0] program_wdata,
    output wire [31:0] program_rdata,
    input  wire        data_en,
    input  wire        data_we,
    input  wire  [3:0] data_be,
    input  wire  [8:0] data_word_addr,
    input  wire [31:0] data_wdata,
    output wire [31:0] data_rdata
);
  // IHP masks are per bit, with 1 meaning write. Expand each byte enable.
  wire [31:0] program_mask = {{8{program_be[3]}}, {8{program_be[2]}},
                             {8{program_be[1]}}, {8{program_be[0]}}};
  wire [31:0] data_mask = {{8{data_be[3]}}, {8{data_be[2]}},
                          {8{data_be[1]}}, {8{data_be[0]}}};

  // 4 KiB program SRAM. A loader must write it before CPU execution starts.
  RM_IHPSG13_1P_1024x32_c2_bm_bist u_program (
    .A_CLK(clk),
    .A_MEN(program_en),
    .A_WEN(program_we),
    .A_REN(!program_we),
    .A_ADDR(program_word_addr),
    .A_DIN(program_wdata),
    .A_DLY(1'b1),
    .A_DOUT(program_rdata),
    .A_BM(program_mask),
    .A_BIST_CLK(1'b0),
    .A_BIST_EN(1'b0),
    .A_BIST_MEN(1'b0),
    .A_BIST_WEN(1'b0),
    .A_BIST_REN(1'b0),
    .A_BIST_ADDR(10'b0),
    .A_BIST_DIN(32'b0),
    .A_BIST_BM(32'b0)
  );

  // 2 KiB data SRAM.
  RM_IHPSG13_1P_512x32_c2_bm_bist u_data (
    .A_CLK(clk),
    .A_MEN(data_en),
    .A_WEN(data_we),
    .A_REN(!data_we),
    .A_ADDR(data_word_addr),
    .A_DIN(data_wdata),
    .A_DLY(1'b1),
    .A_DOUT(data_rdata),
    .A_BM(data_mask),
    .A_BIST_CLK(1'b0),
    .A_BIST_EN(1'b0),
    .A_BIST_MEN(1'b0),
    .A_BIST_WEN(1'b0),
    .A_BIST_REN(1'b0),
    .A_BIST_ADDR(9'b0),
    .A_BIST_DIN(32'b0),
    .A_BIST_BM(32'b0)
  );
endmodule

`default_nettype wire
