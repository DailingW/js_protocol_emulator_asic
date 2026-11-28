// SPDX-License-Identifier: Apache-2.0
`default_nettype none

// Synthesis sees the hard macro as a black box. Simulations instead compile
// the PDK model with SIM and FUNCTIONAL defined (test/sram_models.mk).

`ifndef SIM
/* verilator lint_off DECLFILENAME */
/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off UNDRIVEN */
(* blackbox *)
module RM_IHPSG13_1P_64x64_c2_bm_bist
(
    input  wire        A_CLK,
    input  wire        A_MEN,
    input  wire        A_WEN,
    input  wire        A_REN,
    input  wire  [5:0] A_ADDR,
    input  wire [63:0] A_DIN,
    input  wire        A_DLY,
    output wire [63:0] A_DOUT,
    input  wire [63:0] A_BM,
    input  wire        A_BIST_CLK,
    input  wire        A_BIST_EN,
    input  wire        A_BIST_MEN,
    input  wire        A_BIST_WEN,
    input  wire        A_BIST_REN,
    input  wire  [5:0] A_BIST_ADDR,
    input  wire [63:0] A_BIST_DIN,
    input  wire [63:0] A_BIST_BM
);
endmodule
/* verilator lint_on UNDRIVEN */
/* verilator lint_on UNUSEDSIGNAL */
/* verilator lint_on DECLFILENAME */
`endif

`default_nettype wire
