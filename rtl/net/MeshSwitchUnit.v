//========================================================================
// Mesh Switch Unit (one per output port)
//========================================================================

`ifndef NET_MESH_SWITCH_UNIT_V
`define NET_MESH_SWITCH_UNIT_V

`include "vc/arbiters.v"
`include "vc/muxes.v"

module net_MeshSwitchUnit
#(
  parameter p_msg_nbits = 44
)
(
  input  logic                     clk,
  input  logic                     reset,

  // input i wants this output when in_val[i] = 1; its packet is
  // in_msg[i*p_msg_nbits +: p_msg_nbits]

  input  logic [4:0]               in_val,
  output logic [4:0]               in_rdy,
  input  logic [5*p_msg_nbits-1:0] in_msg,

  output logic                     out_val,
  input  logic                     out_rdy,
  output logic [p_msg_nbits-1:0]   out_msg
);
  
  // TODO: round-robin arbitration, forward the winner, val/rdy handshake
  logic [4:0] winner;
  vc_RoundRobinArbEn#(5) second_arbiter_l0l
  (
    .clk    (clk),
    .reset  (reset),
    .en     (out_rdy),
    .reqs   (in_val),
    .grants (winner)
  );

  always_comb begin
  out_msg = '0;
  for ( int i = 0; i < 5; i = i + 1 )
    if ( winner[i] )
      out_msg = in_msg[i*p_msg_nbits +: p_msg_nbits];
  end

  assign out_val = ( in_val != 5'b0 );
  assign in_rdy = out_rdy ? winner : 5'b0;



endmodule

`endif /* NET_MESH_SWITCH_UNIT_V */
