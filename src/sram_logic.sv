// SPDX-License-Identifier: Apache-2.0
`default_nettype none

// Independent, one-cycle Ibex memory paths:
//   instruction fetches: 0x00000000..0x00000fff (4 KiB)
//   data loads/stores:   0x10000000..0x100007ff (2 KiB)
// Invalid requests receive an error response without accessing either SRAM.
module sram_logic (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        ena,

    input  wire        instr_req,
    input  wire [31:0] instr_addr,
    output wire        instr_gnt,
    output reg         instr_rvalid,
    output wire [31:0] instr_rdata,
    output reg         instr_err,

    input  wire        data_req,
    input  wire        data_we,
    input  wire  [3:0] data_be,
    input  wire [31:0] data_addr,
    input  wire [31:0] data_wdata,
    output wire        data_gnt,
    output reg         data_rvalid,
    output wire [31:0] data_rdata,
    output reg         data_err,

    output wire        program_en,
    output wire        program_we,
    output wire  [3:0] program_be,
    output wire  [9:0] program_word_addr,
    output wire [31:0] program_wdata,
    input  wire [31:0] program_rdata,

    output wire        data_mem_en,
    output wire        data_mem_we,
    output wire  [3:0] data_mem_be,
    output wire  [8:0] data_mem_word_addr,
    output wire [31:0] data_mem_wdata,
    input  wire [31:0] data_mem_rdata
);
  // Ibex presents word-aligned byte addresses, including byte/halfword stores.
  wire instr_hit = (instr_addr[31:12] == 20'h00000) &&
                   (instr_addr[1:0] == 2'b00);
  wire data_hit = (data_addr[31:11] == 21'h020000) &&
                  (data_addr[1:0] == 2'b00);

  // Each independent bank can accept a request on every clock.
  assign instr_gnt = rst_n && ena && instr_req;
  assign data_gnt = rst_n && ena && data_req;

  assign program_en = instr_gnt && instr_hit;
  assign program_we = 1'b0; // CPU fetch path is read-only; loader comes later.
  assign program_be = 4'b0000;
  assign program_word_addr = instr_addr[11:2];
  assign program_wdata = 32'b0;

  assign data_mem_en = data_gnt && data_hit;
  assign data_mem_we = data_we;
  assign data_mem_be = data_be;
  assign data_mem_word_addr = data_addr[10:2];
  assign data_mem_wdata = data_wdata;

  reg data_write_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      instr_rvalid <= 1'b0;
      instr_err    <= 1'b0;
      data_rvalid  <= 1'b0;
      data_err     <= 1'b0;
      data_write_q <= 1'b0;
    end else begin
      // Metadata lines up with the SRAM's clocked output. An accepted request
      // completes even if ena is subsequently lowered to stop new requests.
      instr_rvalid <= instr_gnt;
      instr_err    <= instr_gnt && !instr_hit;
      data_rvalid  <= data_gnt;
      data_err     <= data_gnt && !data_hit;
      data_write_q <= data_gnt && data_we;
    end
  end

  // Stores still receive a response; their return data is ignored by Ibex.
  assign instr_rdata = (instr_rvalid && !instr_err) ? program_rdata : 32'b0;
  assign data_rdata = (data_rvalid && !data_err && !data_write_q) ?
                      data_mem_rdata : 32'b0;
endmodule

`default_nettype wire
