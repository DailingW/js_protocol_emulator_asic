module rx_serializer (
    input logic clk,
    input logic rx_en,
    input logic rst_n,
    input logic [2:0] rx_width,             // [CONST] data bus width (000 = 1 bit, etc.)
    input logic [7:0] uio_in,               // input pads
    input logic [2:0] rx_index_map [7:0],   // [MEM] bit order map of parallel rx data pads
    input logic rx_in_stream_valid,         // incoming data on pads is valid
    input logic rx_out_stream_ready,          // ready to transfer data out of buf to downstream FIFO

    output logic rx_out_stream,             // serialized bit stream
    output logic rx_in_stream_ready,        // ready to accept new data from pads
    output logic rx_out_stream_valid        // bit is real data
);

logic [7:0] rx_buf;
logic [2:0] index_map_lane;
logic busy, load, index_map_last_lane;

assign index_map_last_lane = (index_map_lane == rx_width);
assign load = rx_en && (!busy || (rx_out_stream_ready && index_map_last_lane));

assign rx_out_stream_valid = rx_en && busy;
assign rx_in_stream_ready = rx_en && load;      // diagnostic signal, unused
assign rx_out_stream = rx_buf[rx_index_map[index_map_lane]];

// Data stream (serialize if parallel)
// If 1b serial stream, should be continuous, no extra cycle between frames
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        rx_buf <= 8'b0;
        busy <= 1'b0;
        index_map_lane <= 3'b0;
    end else if (rx_en) begin
        if (load) begin
            // update the buf if new data is available and not busy with current snapshot
            index_map_lane <= 3'b0;
            busy <= rx_in_stream_valid;
            if (rx_in_stream_valid) begin
                rx_buf <= uio_in;
            end
        end else if (rx_out_stream_ready) begin
            // LSB to MSB or MSB to LSB depending on how rx_index_map is set
            index_map_lane <= index_map_lane + 3'b1;
        end
    end
end

endmodule
