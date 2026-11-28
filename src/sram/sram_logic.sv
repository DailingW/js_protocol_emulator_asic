// SPDX-License-Identifier: Apache-2.0
`default_nettype none

// One FSM's 64 x 128-bit state memory. Addresses count state words, not bytes.
// en && !we reads; en && we writes (1 in wmask writes that bit). There is
// one shared port, so programming and state fetches must use different cycles.
// Read data is available after the accepting rising edge, with rvalid high.
// Writes and idle cycles hold the previous read data and deassert rvalid.
// Reset inhibits accesses and clears rvalid; SRAM contents/output are not reset.
module sram_logic (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         en,
    input  wire         we,
    input  wire   [5:0] word_addr,
    input  wire [127:0] wdata,
    input  wire [127:0] wmask,
    output wire [127:0] rdata,
    output reg          rvalid
);
  wire access_en = rst_n && en;

  // Keep this hierarchy stable: config.json uses u_state_mem.u_banks.u_lo/hi
  // relative to fsm_main. Each fsm_main owns its own pair of hard macros.
  sram_banks u_banks (
    .clk(clk),
    .en(access_en),
    .we(we),
    .word_addr(word_addr),
    .wdata(wdata),
    .wmask(wmask),
    .rdata(rdata)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      rvalid <= 1'b0;
    else
      rvalid <= access_en && !we;
  end
endmodule

`default_nettype wire
