`default_nettype none

// Eight-byte synchronous FIFO. The oldest byte is visible before rd_en;
// a read accepts that byte on the next rising clock edge.
module fifo (
    input  logic         clk,
    input  logic         rst_n,
    input  logic [7:0]   wr_data,
    input  logic         wr_en,
    output logic [7:0]   rd_data,
    input  logic         rd_en,
    output logic         full,
    output logic         empty
);
    logic [7:0] mem [0:7];
    logic [2:0] wr_ptr, rd_ptr;
    logic [3:0] count;
    logic push, pop;

    assign full = (count == 4'd8);
    assign empty = (count == 4'd0);
    assign rd_data = empty ? 8'b0 : mem[rd_ptr];
    assign pop = rd_en && !empty;
    // When full, a simultaneous pop makes room for the new byte.
    assign push = wr_en && (!full || pop);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            count <= 0;
        end else begin
            if (push) begin
                mem[wr_ptr] <= wr_data;
                wr_ptr <= wr_ptr + 1;
            end

            if (pop) begin
                rd_ptr <= rd_ptr + 1;
            end

            // Simultaneous push/pop preserves occupancy.
            if (push && !pop) begin
                count <= count + 1;
            end else if (pop && !push) begin
                count <= count - 1;
            end
        end
    end

endmodule
