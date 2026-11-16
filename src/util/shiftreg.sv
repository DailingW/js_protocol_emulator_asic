module shiftreg #(
    parameter int DEPTH = 32,
    parameter int WIDTH = 8
)(
    input logic clk,
    input logic rst_n,
    input logic en,
    input logic din,
    output logic dout
);

logic [WIDTH-1:0] pipe [DEPTH-1:0];
assign dout = pipe[DEPTH-1];

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pipe <= '{default: 0};
    end else if (en) begin
        for (int i = DEPTH-1; i > 0; i--) begin
            pipe[i] <= pipe[i-1];
        end
        pipe[0] <= din;
    end
end
endmodule