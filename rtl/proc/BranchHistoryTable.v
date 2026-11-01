//========================================================================
// Branch History Table
//========================================================================

`ifndef PROC_BRANCH_HISTORY_TABLE_V
`define PROC_BRANCH_HISTORY_TABLE_V

module proc_BranchHistoryTable
#(
  parameter number_of_entries = 16
)
(
  input  logic clk,
  input  logic reset,

  input logic [31:0] pc_d,
  input logic [31:0] pc_x,
  input logic update_en,
  input logic update_taken,

  output logic pred_taken_d
);

logic [1:0] fsms[number_of_entries];
logic [1:0] lookup;
assign lookup = fsms[pc_d[$clog2(number_of_entries)+1:2]];
logic [$clog2(number_of_entries)-1:0] update_idx;
assign update_idx = pc_x[$clog2(number_of_entries)+1:2];


// Note to self I learned here that SysVerilog indexing is not like python indexing
assign pred_taken_d = lookup[1];

always_ff @(posedge clk) begin
  if (reset) begin
    for (int i = 0; i < number_of_entries; i = i + 1) begin
      // strongly not taken start state
      fsms[i] <= 2'b00;
    end
  end
  else if (update_en) begin
    case (fsms[update_idx])
      2'b00: fsms[update_idx] <= update_taken ? 2'b01 : 2'b00;
      2'b01: fsms[update_idx] <= update_taken ? 2'b10 : 2'b00;
      2'b10: fsms[update_idx] <= update_taken ? 2'b11 : 2'b01;
      2'b11: fsms[update_idx] <= update_taken ? 2'b11 : 2'b10;
      default: fsms[update_idx] <= 2'b00;
    endcase
  end
end




endmodule

`endif /* PROC_BRANCH_HISTORY_TABLE_V */
