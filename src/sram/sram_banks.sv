// SPDX-License-Identifier: Apache-2.0
`default_nettype none

// Two 64 x 64-bit macros in parallel form 64 x 128 bits (1024 bytes).
// Both halves share their address and operation. Native per-bit write masks
// allow either half, individual bytes, or individual bits to be programmed.
// Inputs are sampled on the rising edge; read output changes after that edge.
// There is no reset or initialization of SRAM contents.
module sram_banks (
    input  wire         clk,
    input  wire         en,
    input  wire         we,
    input  wire   [5:0] word_addr,
    input  wire [127:0] wdata,
    input  wire [127:0] wmask,
    output wire [127:0] rdata
);
  RM_IHPSG13_1P_64x64_c2_bm_bist u_lo (
    .A_CLK(clk),
    .A_MEN(en),
    .A_WEN(en && we),
    .A_REN(en && !we),
    .A_ADDR(word_addr),
    .A_DIN(wdata[63:0]),
    .A_DLY(1'b1),
    .A_DOUT(rdata[63:0]),
    .A_BM(wmask[63:0]),
    .A_BIST_CLK(1'b0),
    .A_BIST_EN(1'b0),
    .A_BIST_MEN(1'b0),
    .A_BIST_WEN(1'b0),
    .A_BIST_REN(1'b0),
    .A_BIST_ADDR(6'b0),
    .A_BIST_DIN(64'b0),
    .A_BIST_BM(64'b0)
  );

  RM_IHPSG13_1P_64x64_c2_bm_bist u_hi (
    .A_CLK(clk),
    .A_MEN(en),
    .A_WEN(en && we),
    .A_REN(en && !we),
    .A_ADDR(word_addr),
    .A_DIN(wdata[127:64]),
    .A_DLY(1'b1),
    .A_DOUT(rdata[127:64]),
    .A_BM(wmask[127:64]),
    .A_BIST_CLK(1'b0),
    .A_BIST_EN(1'b0),
    .A_BIST_MEN(1'b0),
    .A_BIST_WEN(1'b0),
    .A_BIST_REN(1'b0),
    .A_BIST_ADDR(6'b0),
    .A_BIST_DIN(64'b0),
    .A_BIST_BM(64'b0)
  );
endmodule

`default_nettype wire
