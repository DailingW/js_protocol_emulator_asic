module fifo #(
    parameter int WIDTH = 8,
    parameter int DEPTH = 16
)
(
    input logic clk,
    input logic rst_n,
    input logic wr_en,
    input logic rd_en,
    input logic [WIDTH-1:0] din,
    output logic [WIDTH-1:0] dout,
    output logic full,
    output logic empty
);

localparam int PTR_WIDTH = $clog2(DEPTH);

logic [WIDTH-1:0] mem [0:DEPTH-1];
logic [PTR_WIDTH:0] wr_ptr, rd_ptr;
logic [PTR_WIDTH-1:0] wr_addr, rd_addr;

assign wr_addr = wr_ptr[PTR_WIDTH-1:0];
assign rd_addr = rd_ptr[PTR_WIDTH-1:0];

assign full = (wr_ptr[PTR_WIDTH] != rd_ptr[PTR_WIDTH]) &&
    (wr_ptr[PTR_WIDTH-1:0] == rd_ptr[PTR_WIDTH-1:0]);
assign empty = (wr_ptr == rd_ptr);

assign dout = mem[rd_addr];

always_ff @(posedge clk) begin
    if (!full && wr_en) begin
        mem[wr_addr] <= din;
    end
end

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wr_ptr <= 0;
        rd_ptr <= 0;
        dout <= 0;
    end else begin
        if (!empty && rd_en) begin
            rd_ptr <= rd_ptr + 1;
        end
        if (!full && wr_en) begin
            wr_ptr <= wr_ptr + 1;
        end
    end
end

endmodule