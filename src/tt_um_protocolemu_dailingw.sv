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

  // All output pins must be assigned. If not used, assign to 0.
  // [0]: tx_valid input signal; [1]: tx_ready output signal
  // [2]: rx_valid output signal; [3]: rx_ready input signal
  // [4]: rx_fifo_full output signal; [5]: rx_error output signal
  // [6]: tx, [7]: rx
  logic tx_valid, tx_ready;
  logic rx_valid, rx_ready, rx_error;
  wire tx, rx;
  logic [9:0] tx_frame;
  logic [7:0] rx_data;
  logic [7:0] rx_shift;

  logic fifo_wr_en, fifo_rd_en, fifo_full, fifo_empty;
  fifo rx_fifo (
    .clk(clk),
    .rst_n(rst_n),
    .wr_data(rx_shift),
    .wr_en(fifo_wr_en),
    .rd_data(rx_data),
    .rd_en(fifo_rd_en),
    .full(fifo_full),
    .empty(fifo_empty)
  );

  assign tx_valid = uio_in[0];
  assign tx = tx_frame[0];
  assign rx_ready = uio_in[3];
  assign rx = uio_in[7];
  assign rx_valid = !fifo_empty;
  assign fifo_rd_en = rx_valid && rx_ready;
  assign uio_oe = 8'b01110110;
  assign uio_out = {1'b0, tx, rx_error, fifo_full, 1'b0, rx_valid, tx_ready, 1'b0};
  assign uo_out = rx_data;

  localparam int unsigned BAUD = 9600;
  localparam int unsigned CLK_FREQ = 1000000;
  localparam int unsigned BIT_TIME = CLK_FREQ / BAUD;
  localparam int unsigned BAUD_CNT_WIDTH = $clog2(BIT_TIME);
  localparam logic [BAUD_CNT_WIDTH-1:0] BIT_LAST = BAUD_CNT_WIDTH'(BIT_TIME - 1);
  localparam logic [BAUD_CNT_WIDTH-1:0] HALF_BIT_LAST = BAUD_CNT_WIDTH'(BIT_TIME / 2 - 1);

  logic [BAUD_CNT_WIDTH-1:0] rx_baud_cnt, tx_baud_cnt;
  logic [3:0] tx_bits;
  logic [2:0] rx_bits;

  // ================ RX async flip flop ================
  (* async_reg = "true" *) logic rx_meta, rx_sync;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rx_meta <= 1'b1;
      rx_sync <= 1'b1;
    end else begin
      rx_meta <= rx;
      rx_sync <= rx_meta;
    end
  end

  // ================ TX block ================
  always_ff @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0) begin
      tx_frame <= 10'b1111111111;
      tx_baud_cnt <= 0;
      tx_bits <= 0;
      tx_ready <= 1'b1;
    end

    else if (tx_valid && tx_ready) begin
      tx_ready <= 1'b0;
      tx_frame <= {1'b1, ui_in, 1'b0};
      tx_baud_cnt <= 0;
      tx_bits <= 0;
    end

    else if (!tx_ready) begin
      if (tx_baud_cnt == BIT_LAST) begin
        tx_baud_cnt <= 0;
        // Fill with idle ones so TX stays high after the stop bit
        tx_frame <= {1'b1, tx_frame[9:1]};
        if (tx_bits == 4'd9) begin
          tx_bits <= 0;
          tx_ready <= 1'b1;
        end else begin
          tx_bits <= tx_bits + 1;
        end
      end else begin
        tx_baud_cnt <= tx_baud_cnt + 1;
      end
    end
  end

  // ================ RX state machine ================
  typedef enum logic [1:0] {
        IDLE  = 2'b00,
        START = 2'b01,
        DATA = 2'b10,
        STOP = 2'b11
  } rx_read_state;
  rx_read_state rx_state;

  // ================ RX block ================
  always_ff @(posedge clk or negedge rst_n) begin
    if (rst_n == 1'b0) begin
      fifo_wr_en <= 1'b0;
      rx_shift <= 0;
      rx_baud_cnt <= 0;
      rx_bits <= 0;
      rx_error <= 1'b0;       // Clear only on reset
      rx_state <= IDLE;
    end else begin
      // STOP state enables write and overrides this default
      // Write is unenabled next clock
      fifo_wr_en <= 1'b0;
      if (fifo_wr_en && fifo_full && !fifo_rd_en) begin
        rx_error <= 1'b1;
      end
      case (rx_state)
        IDLE: begin
          rx_baud_cnt <= 0;
          rx_bits <= 0;
          if (!rx_sync) begin
            rx_state <= START;
          end
        end

        START: begin
          // Confirm the start bit at its center; reject short low glitches.
          if (rx_baud_cnt == HALF_BIT_LAST) begin
            rx_baud_cnt <= 0;
            if (!rx_sync) begin
              rx_state <= DATA;
            end else begin
              rx_state <= IDLE;
            end
          end else begin
            rx_baud_cnt <= rx_baud_cnt + 1;
          end
        end

        DATA: begin
          // One full bit after start validation is the center of data bit 0.
          if (rx_baud_cnt == BIT_LAST) begin
            rx_baud_cnt <= 0;
            rx_shift[rx_bits] <= rx_sync;
            if (rx_bits == 3'd7) begin
              rx_state <= STOP;
            end else begin
              rx_bits <= rx_bits + 1;
            end
          end else begin
            rx_baud_cnt <= rx_baud_cnt + 1;
          end
        end

        STOP: begin
          if (rx_baud_cnt == BIT_LAST) begin
            rx_baud_cnt <= 0;
            rx_state <= IDLE;
            if (rx_sync) begin    // end bit 1'b1
              fifo_wr_en <= 1'b1;
            end else begin
              rx_error <= 1'b1;
            end
          end else begin
            rx_baud_cnt <= rx_baud_cnt + 1;
          end
        end

        default: begin
          rx_state <= IDLE;
          rx_baud_cnt <= 0;
          rx_bits <= 0;
        end
      endcase
    end
  end

  // List all unused inputs to prevent warnings
  wire _unused = &{ena, uio_in[6:4], uio_in[2:1], 1'b0};

endmodule
