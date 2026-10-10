<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it works

This is a full-duplex UART with eight data bits, no parity, and one stop bit
(8N1), sent least significant bit first. Supply a 1 MHz clock. Each bit lasts
104 clock cycles, giving approximately 9615 baud for a nominal 9600-baud link.

`ui_in[7:0]` supplies parallel TX data. A byte is accepted on a rising `clk`
edge where `tx_valid` and `tx_ready` are both high. Keep the byte and valid
stable until that edge. TX ready stays low until the entire frame has finished.

The receiver synchronizes serial RX and queues complete frames in an eight-byte
FIFO. `uo_out[7:0]` presents the oldest queued byte while `rx_valid` is high.
The byte and valid remain stable while `rx_ready` is low. A rising edge with
both ready and valid high removes exactly one byte; holding ready high allows
one byte to be removed per clock. The output is zero when the FIFO is empty.

| Bidirectional pin | Direction | Signal |
| --- | --- | --- |
| 0 | Input | TX_VALID |
| 1 | Output | TX_READY |
| 2 | Output | RX_VALID |
| 3 | Input | RX_READY |
| 4 | Output | RX_FIFO_FULL |
| 5 | Output | RX_ERROR |
| 6 | Output | UART_TX |
| 7 | Input | UART_RX |

`RX_ERROR` stays high after an invalid stop bit or FIFO overflow until reset.
Invalid frames are discarded. When full, a newly received byte is discarded
unless a parallel read on the same clock edge makes room. Existing unread
bytes are preserved. FIFO full is a status output, not serial flow control:
the sender must be paced externally if the consumer may stall indefinitely.
Both parallel interfaces must obey setup/hold timing relative to `clk`.

After an invalid stop bit, the receiver enters `RECOVER` and waits for the
synchronized RX line to go high before accepting another start bit. This
prevents a sustained low (UART break) from triggering repeated frame attempts
and potentially queuing a bogus byte when the line returns high. Recovery
checks the line once per bit period; returning high does not clear `RX_ERROR`.

## How to test

Hold `rst_n` low to reset. Keep UART RX high when idle. Offer a transmit byte
through TX_DATA and TX_VALID, and use RX_VALID/RX_READY to consume received
bytes. RX_READY may be held low to retain queued bytes.

Run `make` from `test/` for UART integration tests and `make fifo-test` for
FIFO boundary, simultaneous read/write, and randomized ordering tests.
The single-UART `sustained_low_recovery` test holds RX low for several durations,
checks that neither the low interval nor its release queues a byte, and verifies
that a subsequent valid frame is received while `RX_ERROR` remains set.

## External hardware

A UART peer using compatible logic levels and a controller for the parallel
data and handshake pins. TX and RX connect to the peer's RX and TX respectively.
