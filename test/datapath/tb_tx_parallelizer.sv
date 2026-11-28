`timescale 1ns/1ps
`default_nettype none

module tb_tx_parallelizer;
    reg clk;
    reg rst_n;
    reg tx_en;
    reg [2:0] tx_width;
    wire [7:0] uio_out;
    reg [7:0] uio_oe;
    reg [23:0] index_map_flat;
    wire [2:0] tx_index_map [7:0];
    reg tx_in_stream;
    reg tx_in_stream_valid;
    reg tx_out_stream_ready;
    wire tx_in_stream_ready;
    wire tx_out_stream_valid;

    for (genvar lane = 0; lane < 8; lane = lane + 1) begin : map_bridge
        assign tx_index_map[lane] = index_map_flat[3*lane +: 3];
    end

    // uio_out is driven by the DUT; the testbench only drives its inputs.
    tx_parallelizer dut (.*);

    initial begin
        $dumpfile("sim_build/tx_parallelizer/waves.fst");
        $dumpvars(0, tb_tx_parallelizer);
    end
endmodule

`default_nettype wire
