module tx_parallelizer (
    input logic clk,
    input logic tx_en,
    input logic rst_n,
    input logic [2:0] tx_width,             // [CONST] data bus width (000 = 1 bit, etc.)
    input logic tx_in_stream,               // incoming data from spi controller
    input logic [7:0] uio_oe,               // output enable pads
    input logic [2:0] tx_index_map [7:0],   // [MEM] bit order map of parallel tx data pads
    input logic tx_in_stream_valid,         // incoming data from spi controller is valid
    input logic tx_out_stream_ready,          // ready to transfer data out of buf to pads

    output logic [7:0] uio_out,               // output pads
    output logic tx_in_stream_ready,        // ready to accept new data from spi controller
    output logic tx_out_stream_valid        // parallel bits are ready
);

logic [7:0] tx_buf;
logic [2:0] index_map_lane;
logic load, index_map_last_lane;

assign index_map_last_lane = (index_map_lane == tx_width);
assign load = tx_en && tx_out_stream_valid && tx_out_stream_ready;   // ready to load new data into buf
assign tx_in_stream_ready = tx_en && (load || !tx_out_stream_valid);   // ready to accept new data if tx_buf is being or has already been written to output pads

// Data stream (serialize if parallel)
// If 1b serial stream, should be continuous, no extra cycle between frames
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tx_buf <= 8'b0;
        index_map_lane <= 3'b0;
        tx_out_stream_valid <= 1'b0;
    end else if (tx_en) begin
        if (load) begin
            // update the buf if new data is available and not busy with current snapshot
            uio_out <= (uio_out & ~uio_oe) | (tx_buf & uio_oe);
            tx_out_stream_valid <= 1'b0;
        end
        if (tx_in_stream_ready && tx_in_stream_valid) begin
            // LSB to MSB or MSB to LSB depending on how tx_index_map is set
            tx_buf[tx_index_map[index_map_lane]] <= tx_in_stream;
            if (index_map_last_lane) begin
                index_map_lane <= 3'b0;
            end
            tx_out_stream_valid <= index_map_last_lane;
            if (!index_map_last_lane) begin
                index_map_lane <= index_map_lane + 3'b1;
            end
        end
    end
end

endmodule
