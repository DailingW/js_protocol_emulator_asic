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

  // Area-reference harness, not a complete SoC: no program ROM or data RAM.
  // Load any byte of the two independent memory response words:
  //   uio_in[3] = write enable, uio_in[2:0] = byte index, ui_in = byte data.
  // Indices 0..3 load instruction data; indices 4..7 load data-memory data.
  // With write enable low, ui_in supplies the bus handshake/control signals.
  // Keeping all 32 response bits independently controllable avoids specializing
  // the processor to a constant instruction stream or a narrow load-data bus.
  reg [31:0] instr_rdata;
  reg [31:0] data_rdata;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      instr_rdata <= 32'b0;
      data_rdata  <= 32'b0;
    end else if (ena && uio_in[3]) begin
      case (uio_in[2:0])
        3'd0: instr_rdata[7:0]   <= ui_in;
        3'd1: instr_rdata[15:8]  <= ui_in;
        3'd2: instr_rdata[23:16] <= ui_in;
        3'd3: instr_rdata[31:24] <= ui_in;
        3'd4: data_rdata[7:0]    <= ui_in;
        3'd5: data_rdata[15:8]   <= ui_in;
        3'd6: data_rdata[23:16]  <= ui_in;
        3'd7: data_rdata[31:24]  <= ui_in;
      endcase
    end
  end

  wire bus_active = ena && !uio_in[3];
  wire instr_req, data_req, data_we;
  wire [3:0] data_be;
  wire [31:0] instr_addr, data_addr, data_wdata;
  wire core_sleep, alert_minor, alert_major_internal, alert_major_bus;
  wire double_fault_seen;

  // RV32EC configuration and all Ibex tie-offs are in ibex_area_core.sv.
  ibex_area_core u_ibex (
    .clk(clk),
    .rst_n(rst_n),
    .ena(ena),
    .bus_active(bus_active),
    .ui_in(ui_in),
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
      default: observation = 8'b0;
    endcase
  end
  assign uo_out  = observation;
  assign uio_out = 8'b0;
  assign uio_oe  = 8'b0;

endmodule
