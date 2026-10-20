/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_protocolemu_dailingw (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  // Strictly separate instruction/data SRAM paths. A future loader must fill
  // both banks before the CPU starts; the SRAMs have no power-up contents.
  wire [31:0] instr_rdata, data_rdata;
  wire instr_gnt, instr_rvalid, instr_err;
  wire data_gnt, data_rvalid, data_err;
  wire instr_req, data_req, data_we;
  wire [3:0] data_be;
  wire [31:0] instr_addr, data_addr, data_wdata;
  wire core_sleep, alert_minor, alert_major_internal, alert_major_bus;
  wire double_fault_seen;

  wire program_en, program_we;
  wire [3:0] program_be;
  wire [9:0] program_word_addr;
  wire [31:0] program_wdata, program_rdata;
  wire data_mem_en, data_mem_we;
  wire [3:0] data_mem_be;
  wire [8:0] data_mem_word_addr;
  wire [31:0] data_mem_wdata, data_mem_rdata;

  // RV32EC configuration and all Ibex tie-offs are in ibex_area_core.sv.
  ibex_area_core u_ibex (
    .clk(clk),
    .rst_n(rst_n),
    .ena(ena),
    .instr_gnt(instr_gnt),
    .instr_rvalid(instr_rvalid),
    .instr_err(instr_err),
    .data_gnt(data_gnt),
    .data_rvalid(data_rvalid),
    .data_err(data_err),
    .irq_external(ena && ui_in[6]),
    .debug_req(ena && ui_in[7]),
    .instr_rdata(instr_rdata),
    .data_rdata(data_rdata),
    .instr_req(instr_req),
    .data_req(data_req),
    .data_we(data_we),
    .data_be(data_be),
    .instr_addr(instr_addr),
    .data_addr(data_addr),
    .data_wdata(data_wdata),
    .core_sleep(core_sleep),
    .alert_minor(alert_minor),
    .alert_major_internal(alert_major_internal),
    .alert_major_bus(alert_major_bus),
    .double_fault_seen(double_fault_seen)
  );

  sram_logic u_sram_logic (
    .clk(clk),
    .rst_n(rst_n),
    .ena(ena),
    .instr_req(instr_req),
    .instr_addr(instr_addr),
    .instr_gnt(instr_gnt),
    .instr_rvalid(instr_rvalid),
    .instr_rdata(instr_rdata),
    .instr_err(instr_err),
    .data_req(data_req),
    .data_we(data_we),
    .data_be(data_be),
    .data_addr(data_addr),
    .data_wdata(data_wdata),
    .data_gnt(data_gnt),
    .data_rvalid(data_rvalid),
    .data_rdata(data_rdata),
    .data_err(data_err),
    .program_en(program_en),
    .program_we(program_we),
    .program_be(program_be),
    .program_word_addr(program_word_addr),
    .program_wdata(program_wdata),
    .program_rdata(program_rdata),
    .data_mem_en(data_mem_en),
    .data_mem_we(data_mem_we),
    .data_mem_be(data_mem_be),
    .data_mem_word_addr(data_mem_word_addr),
    .data_mem_wdata(data_mem_wdata),
    .data_mem_rdata(data_mem_rdata)
  );

  // Every byte of the CPU's address/write-data outputs is observable. An unused
  // reduction named _unused would only silence lint; it would NOT retain logic.
  reg [7:0] observation;
  always @* begin
    case (uio_in[7:4])
      4'd0:  observation = instr_addr[7:0];
      4'd1:  observation = instr_addr[15:8];
      4'd2:  observation = instr_addr[23:16];
      4'd3:  observation = instr_addr[31:24];
      4'd4:  observation = data_addr[7:0];
      4'd5:  observation = data_addr[15:8];
      4'd6:  observation = data_addr[23:16];
      4'd7:  observation = data_addr[31:24];
      4'd8:  observation = data_wdata[7:0];
      4'd9:  observation = data_wdata[15:8];
      4'd10: observation = data_wdata[23:16];
      4'd11: observation = data_wdata[31:24];
      4'd12: observation = {core_sleep, data_be, data_we, data_req, instr_req};
      4'd13: observation = {4'b0, double_fault_seen, alert_major_bus,
                            alert_major_internal, alert_minor};
      4'd14: observation = {2'b0, data_err, instr_err, data_rvalid,
                            instr_rvalid, data_gnt, instr_gnt};
      default: observation = 8'b0;
    endcase
  end
  assign uo_out  = observation;
  assign uio_out = 8'b0;
  assign uio_oe  = 8'b0;

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

  // Reserved for the future loader; these pins no longer drive CPU responses.
  wire _unused = &{1'b0, ui_in[5:0], uio_in[3:0]};

endmodule
