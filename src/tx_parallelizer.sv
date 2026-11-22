module tx_parallelizer (
    input logic clk,
    input logic tx_en,
    input logic rst_n,
    input logic [2:0] tx_width,             // [CONST] data bus width (000 = 1 bit, etc.)
    input logic [7:0] uio_out,               // output pads
    input logic [7:0] uio_oe,               // output enable pads
    input logic [2:0] tx_index_map [7:0],   // [MEM] bit order map of parallel tx data pads
    input logic tx_in_stream,               // incoming data from spi controller
    input logic tx_in_stream_valid,         // incoming data from spi controller is valid
    input logic tx_out_stream_ready,          // ready to transfer data out of buf to pads

    output logic tx_in_stream_ready,        // ready to accept new data from spi controller
    output logic [7:0] tx_out_stream,             // parallelized bit stream
    output logic tx_out_stream_valid        // parallel bits are ready
);

logic [7:0] tx_buf;
logic [2:0] index_map_lane;
logic busy, load, index_map_last_lane;

assign index_map_last_lane = (index_map_lane == tx_width);
assign load = !busy || (busy && index_map_last_lane);   // ready to load new data into buf
assign tx_in_stream_ready = tx_en && load;

assign tx_out_stream_valid = tx_en && busy && index_map_last_lane;
assign tx_out_stream = tx_buf;

// Data stream (serialize if parallel)
// If 1b serial stream, should be continuous, no extra cycle between frames
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tx_buf <= 8'b0;
        busy <= 1'b0;
        index_map_lane <= 3'b0;
    end else if (!tx_en) begin
        busy <= 1'b0;
        index_map_lane <= 3'd0;
    end else if (load) begin
        // update the buf if new data is available and not busy with current snapshot
        index_map_lane <= 3'b0;
        busy <= tx_in_stream_valid;
        if (tx_out_stream_ready) begin
            uio_out <= (uio_out & ~uio_oe) | (tx_buf & uio_oe);
        end
        if (tx_in_stream_valid) begin
            tx_buf[tx_index_map[index_map_lane]] <= tx_in_stream;
        end
    end else begin
        // LSB to MSB or MSB to LSB depending on how rx_index_map is set
        index_map_lane <= index_map_lane + 3'b1;
        if (tx_in_stream_valid) begin
            tx_buf[tx_index_map[index_map_lane]] <= tx_in_stream;
        end
    end
end

endmodule
