module fsm import fsm_ctrl_pkg::* import fsm_misc_pkg::*; (
    input logic clk,
    input logic rst,
    input logic en,

    input logic [7:0] uio_in,               // input pads
    input logic [7:0] rise_edge,
    input logic [7:0] fall_edge,
    input misc_t misc,
    input cfg_word_t cfg,

    output logic [ACTION_W-1:0] action;
);

logic [31:0] signals;
assign signals = {uio_in, rise_edge, fall_edge, misc};

logic lut1_sel1 = signals[cfg.lut1_addr[0]];
logic lut1_sel2 = signals[cfg.lut1_addr[1]];
logic lut1_sel3 = signals[cfg.lut1_addr[2]];

logic lut2_sel1 = signals[cfg.lut2_addr[0]];
logic lut2_sel2 = signals[cfg.lut2_addr[1]];
logic lut2_sel3 = signals[cfg.lut2_addr[2]];

if (cfg.lut1_truth[{lut1_sel3, lut1_sel2, lut1_sel1}]) begin
    action = cfg.action[0];
end else if (cfg.lut2_truth[{lut2_sel3, lut2_sel2, lut2_sel1}]) begin
    action = cfg.action[1];
end else begin
    action = cfg.action[2];
end

endmodule
