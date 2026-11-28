`timescale 1ns/1ps
`default_nettype none

module tb_rx_serializer;
    reg clk;
    reg rst_n;
    reg rx_en;
    reg [2:0] rx_width;
    reg [7:0] uio_in;
    reg [23:0] index_map_flat;
    wire [2:0] rx_index_map [7:0];
    reg rx_in_stream_valid;
    reg rx_out_stream_ready;
    wire rx_in_stream_ready;
    wire rx_out_stream;
    wire rx_out_stream_valid;

    // A packed bridge lets cocotb drive unpacked input arrays on Icarus.
    // Lane zero occupies bits [2:0]; no DUT behavior is changed here.
    for (genvar lane = 0; lane < 8; lane = lane + 1) begin : map_bridge
        assign rx_index_map[lane] = index_map_flat[3*lane +: 3];
    end

    rx_serializer dut (.*);

    initial begin
        $dumpfile("sim_build/rx_serializer/waves.fst");
        $dumpvars(0, tb_rx_serializer);
    end
endmodule

`default_nettype wire
