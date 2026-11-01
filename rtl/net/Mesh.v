//========================================================================
// 2x2 Mesh Network
//========================================================================

`ifndef NET_MESH_V
`define NET_MESH_V

`include "net/MeshRouter.v"

module net_Mesh
#(
  parameter p_msg_nbits = 44
)
(
  input  logic                        clk,
  input  logic                        reset,

  input  logic [3:0]                  in_val,
  output logic [3:0]                  in_rdy,
  input  logic [3:0][p_msg_nbits-1:0] in_msg,

  output logic [3:0]                  out_val,
  input  logic [3:0]                  out_rdy,
  output logic [3:0][p_msg_nbits-1:0] out_msg
);


  //----------------------------------------------------------------------
  // Routers
  //----------------------------------------------------------------------

  logic [4:0]                  r0_in_val,  r1_in_val,  r2_in_val,  r3_in_val;
  logic [4:0]                  r0_in_rdy,  r1_in_rdy,  r2_in_rdy,  r3_in_rdy;
  logic [4:0][p_msg_nbits-1:0] r0_in_msg,  r1_in_msg,  r2_in_msg,  r3_in_msg;
  logic [4:0]                  r0_out_val, r1_out_val, r2_out_val, r3_out_val;
  logic [4:0]                  r0_out_rdy, r1_out_rdy, r2_out_rdy, r3_out_rdy;
  logic [4:0][p_msg_nbits-1:0] r0_out_msg, r1_out_msg, r2_out_msg, r3_out_msg;

  net_MeshRouter#(p_msg_nbits) r0
  (
    .clk       (clk),
    .reset     (reset),
    .router_id (2'd0),
    .in_val    (r0_in_val),
    .in_rdy    (r0_in_rdy),
    .in_msg    (r0_in_msg),
    .out_val   (r0_out_val),
    .out_rdy   (r0_out_rdy),
    .out_msg   (r0_out_msg)
  );

  net_MeshRouter#(p_msg_nbits) r1
  (
    .clk       (clk),
    .reset     (reset),
    .router_id (2'd1),
    .in_val    (r1_in_val),
    .in_rdy    (r1_in_rdy),
    .in_msg    (r1_in_msg),
    .out_val   (r1_out_val),
    .out_rdy   (r1_out_rdy),
    .out_msg   (r1_out_msg)
  );

  net_MeshRouter#(p_msg_nbits) r2
  (
    .clk       (clk),
    .reset     (reset),
    .router_id (2'd2),
    .in_val    (r2_in_val),
    .in_rdy    (r2_in_rdy),
    .in_msg    (r2_in_msg),
    .out_val   (r2_out_val),
    .out_rdy   (r2_out_rdy),
    .out_msg   (r2_out_msg)
  );

  net_MeshRouter#(p_msg_nbits) r3
  (
    .clk       (clk),
    .reset     (reset),
    .router_id (2'd3),
    .in_val    (r3_in_val),
    .in_rdy    (r3_in_rdy),
    .in_msg    (r3_in_msg),
    .out_val   (r3_out_val),
    .out_rdy   (r3_out_rdy),
    .out_msg   (r3_out_msg)
  );

  //----------------------------------------------------------------------
  // Terminals <-> Local ports
  //----------------------------------------------------------------------

  assign r0_in_val[4] = in_val[0];
  assign r0_in_msg[4] = in_msg[0];
  assign in_rdy[0]         = r0_in_rdy[4];
  assign out_val[0]        = r0_out_val[4];
  assign out_msg[0]        = r0_out_msg[4];
  assign r0_out_rdy[4] = out_rdy[0];

  assign r1_in_val[4] = in_val[1];
  assign r1_in_msg[4] = in_msg[1];
  assign in_rdy[1]         = r1_in_rdy[4];
  assign out_val[1]        = r1_out_val[4];
  assign out_msg[1]        = r1_out_msg[4];
  assign r1_out_rdy[4] = out_rdy[1];

  assign r2_in_val[4] = in_val[2];
  assign r2_in_msg[4] = in_msg[2];
  assign in_rdy[2]         = r2_in_rdy[4];
  assign out_val[2]        = r2_out_val[4];
  assign out_msg[2]        = r2_out_msg[4];
  assign r2_out_rdy[4] = out_rdy[2];

  assign r3_in_val[4] = in_val[3];
  assign r3_in_msg[4] = in_msg[3];
  assign in_rdy[3]         = r3_in_rdy[4];
  assign out_val[3]        = r3_out_val[4];
  assign out_msg[3]        = r3_out_msg[4];
  assign r3_out_rdy[4] = out_rdy[3];

  //----------------------------------------------------------------------
  // Horizontal links
  //----------------------------------------------------------------------

  // r0 East -> r1 West
  assign r1_in_val[3]  = r0_out_val[2];
  assign r1_in_msg[3]  = r0_out_msg[2];
  assign r0_out_rdy[2] = r1_in_rdy[3];

  // r1 West -> r0 East
  assign r0_in_val[2]  = r1_out_val[3];
  assign r0_in_msg[2]  = r1_out_msg[3];
  assign r1_out_rdy[3] = r0_in_rdy[2];

  // r2 East -> r3 West
  assign r3_in_val[3]  = r2_out_val[2];
  assign r3_in_msg[3]  = r2_out_msg[2];
  assign r2_out_rdy[2] = r3_in_rdy[3];

  // r3 West -> r2 East
  assign r2_in_val[2]  = r3_out_val[3];
  assign r2_in_msg[2]  = r3_out_msg[3];
  assign r3_out_rdy[3] = r2_in_rdy[2];

  //----------------------------------------------------------------------
  // Vertical links
  //----------------------------------------------------------------------

  // r0 South -> r2 North
  assign r2_in_val[0]  = r0_out_val[1];
  assign r2_in_msg[0]  = r0_out_msg[1];
  assign r0_out_rdy[1] = r2_in_rdy[0];

  // r2 North -> r0 South
  assign r0_in_val[1]  = r2_out_val[0];
  assign r0_in_msg[1]  = r2_out_msg[0];
  assign r2_out_rdy[0] = r0_in_rdy[1];

  // r1 South -> r3 North
  assign r3_in_val[0]  = r1_out_val[1];
  assign r3_in_msg[0]  = r1_out_msg[1];
  assign r1_out_rdy[1] = r3_in_rdy[0];

  // r3 North -> r1 South
  assign r1_in_val[1]  = r3_out_val[0];
  assign r1_in_msg[1]  = r3_out_msg[0];
  assign r3_out_rdy[0] = r1_in_rdy[1];

  //----------------------------------------------------------------------
  // Edge ports: nothing comes in, nothing may go out
  //----------------------------------------------------------------------

  // r0: North and West face off the mesh
  assign r0_in_val[0]  = 1'b0;  assign r0_in_msg[0] = '0;  assign r0_out_rdy[0] = 1'b0;
  assign r0_in_val[3]  = 1'b0;  assign r0_in_msg[3] = '0;  assign r0_out_rdy[3] = 1'b0;

  // r1: North and East
  assign r1_in_val[0]  = 1'b0;  assign r1_in_msg[0] = '0;  assign r1_out_rdy[0] = 1'b0;
  assign r1_in_val[2]  = 1'b0;  assign r1_in_msg[2] = '0;  assign r1_out_rdy[2] = 1'b0;

  // r2: South and West
  assign r2_in_val[1]  = 1'b0;  assign r2_in_msg[1] = '0;  assign r2_out_rdy[1] = 1'b0;
  assign r2_in_val[3]  = 1'b0;  assign r2_in_msg[3] = '0;  assign r2_out_rdy[3] = 1'b0;

  // r3: South and East
  assign r3_in_val[1]  = 1'b0;  assign r3_in_msg[1] = '0;  assign r3_out_rdy[1] = 1'b0;
  assign r3_in_val[2]  = 1'b0;  assign r3_in_msg[2] = '0;  assign r3_out_rdy[2] = 1'b0;

endmodule

`endif /* NET_MESH_V */
