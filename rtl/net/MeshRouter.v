//========================================================================
// Mesh Router
//========================================================================
// ports: N = 0, S = 1, E = 2, W = 3, L = 4. Messages use the
// vc/net-msgs.v format: {src[2], dest[2], opaque[8], data}.

`ifndef NET_MESH_ROUTER_V
`define NET_MESH_ROUTER_V

`include "vc/queues.v"
`include "net/MeshRouteUnit.v"
`include "net/MeshSwitchUnit.v"

module net_MeshRouter
#(
  parameter p_msg_nbits = 44
)
(
  input  logic                        clk,
  input  logic                        reset,

  input  logic [1:0]                  router_id,

  input  logic [4:0]                  in_val,
  output logic [4:0]                  in_rdy,
  input  logic [4:0][p_msg_nbits-1:0] in_msg,

  output logic [4:0]                  out_val,
  input  logic [4:0]                  out_rdy,
  output logic [4:0][p_msg_nbits-1:0] out_msg
);


  //----------------------------------------------------------------------
  // Input queues: the packet at the head of each queue
  //----------------------------------------------------------------------

  logic [4:0]                  head_val;
  logic [4:0]                  head_rdy;
  logic [4:0][p_msg_nbits-1:0] head_msg;

  vc_Queue#(`VC_QUEUE_NORMAL, p_msg_nbits, 2) queue_n
  (
    .clk              (clk),
    .reset            (reset),
    .enq_val          (in_val[0]),
    .enq_rdy          (in_rdy[0]),
    .enq_msg          (in_msg[0]),
    .deq_val          (head_val[0]),
    .deq_rdy          (head_rdy[0]),
    .deq_msg          (head_msg[0]),
    .num_free_entries ()
  );

  vc_Queue#(`VC_QUEUE_NORMAL, p_msg_nbits, 2) queue_s
  (
    .clk              (clk),
    .reset            (reset),
    .enq_val          (in_val[1]),
    .enq_rdy          (in_rdy[1]),
    .enq_msg          (in_msg[1]),
    .deq_val          (head_val[1]),
    .deq_rdy          (head_rdy[1]),
    .deq_msg          (head_msg[1]),
    .num_free_entries ()
  );

  vc_Queue#(`VC_QUEUE_NORMAL, p_msg_nbits, 2) queue_e
  (
    .clk              (clk),
    .reset            (reset),
    .enq_val          (in_val[2]),
    .enq_rdy          (in_rdy[2]),
    .enq_msg          (in_msg[2]),
    .deq_val          (head_val[2]),
    .deq_rdy          (head_rdy[2]),
    .deq_msg          (head_msg[2]),
    .num_free_entries ()
  );

  vc_Queue#(`VC_QUEUE_NORMAL, p_msg_nbits, 2) queue_w
  (
    .clk              (clk),
    .reset            (reset),
    .enq_val          (in_val[3]),
    .enq_rdy          (in_rdy[3]),
    .enq_msg          (in_msg[3]),
    .deq_val          (head_val[3]),
    .deq_rdy          (head_rdy[3]),
    .deq_msg          (head_msg[3]),
    .num_free_entries ()
  );

  vc_Queue#(`VC_QUEUE_NORMAL, p_msg_nbits, 2) queue_l
  (
    .clk              (clk),
    .reset            (reset),
    .enq_val          (in_val[4]),
    .enq_rdy          (in_rdy[4]),
    .enq_msg          (in_msg[4]),
    .deq_val          (head_val[4]),
    .deq_rdy          (head_rdy[4]),
    .deq_msg          (head_msg[4]),
    .num_free_entries ()
  );

  //----------------------------------------------------------------------
  // Route units: which output each head packet wants
  //----------------------------------------------------------------------
  // dest is bits [p_msg_nbits-3 : p_msg_nbits-4] of a message.

  logic [4:0] route_n;
  logic [4:0] route_s;
  logic [4:0] route_e;
  logic [4:0] route_w;
  logic [4:0] route_l;

  net_MeshRouteUnit route_unit_n
  (
    .router_id (router_id),
    .dest      (head_msg[0][p_msg_nbits-3:p_msg_nbits-4]),
    .route     (route_n)
  );

  net_MeshRouteUnit route_unit_s
  (
    .router_id (router_id),
    .dest      (head_msg[1][p_msg_nbits-3:p_msg_nbits-4]),
    .route     (route_s)
  );

  net_MeshRouteUnit route_unit_e
  (
    .router_id (router_id),
    .dest      (head_msg[2][p_msg_nbits-3:p_msg_nbits-4]),
    .route     (route_e)
  );

  net_MeshRouteUnit route_unit_w
  (
    .router_id (router_id),
    .dest      (head_msg[3][p_msg_nbits-3:p_msg_nbits-4]),
    .route     (route_w)
  );

  net_MeshRouteUnit route_unit_l
  (
    .router_id (router_id),
    .dest      (head_msg[4][p_msg_nbits-3:p_msg_nbits-4]),
    .route     (route_l)
  );

  //----------------------------------------------------------------------
  // Requests: which inputs want each output (bit i = input i)
  //----------------------------------------------------------------------

  logic [4:0] want_n;
  logic [4:0] want_s;
  logic [4:0] want_e;
  logic [4:0] want_w;
  logic [4:0] want_l;

  assign want_n = head_val & { route_l[0], route_w[0], route_e[0], route_s[0], route_n[0] };
  assign want_s = head_val & { route_l[1], route_w[1], route_e[1], route_s[1], route_n[1] };
  assign want_e = head_val & { route_l[2], route_w[2], route_e[2], route_s[2], route_n[2] };
  assign want_w = head_val & { route_l[3], route_w[3], route_e[3], route_s[3], route_n[3] };
  assign want_l = head_val & { route_l[4], route_w[4], route_e[4], route_s[4], route_n[4] };

  //----------------------------------------------------------------------
  // Switch units: each output picks one input (take_* = who it takes)
  //----------------------------------------------------------------------

  logic [4:0] take_n;
  logic [4:0] take_s;
  logic [4:0] take_e;
  logic [4:0] take_w;
  logic [4:0] take_l;

  net_MeshSwitchUnit#(p_msg_nbits) switch_unit_n
  (
    .clk     (clk),
    .reset   (reset),
    .in_val  (want_n),
    .in_rdy  (take_n),
    .in_msg  (head_msg),
    .out_val (out_val[0]),
    .out_rdy (out_rdy[0]),
    .out_msg (out_msg[0])
  );

  net_MeshSwitchUnit#(p_msg_nbits) switch_unit_s
  (
    .clk     (clk),
    .reset   (reset),
    .in_val  (want_s),
    .in_rdy  (take_s),
    .in_msg  (head_msg),
    .out_val (out_val[1]),
    .out_rdy (out_rdy[1]),
    .out_msg (out_msg[1])
  );

  net_MeshSwitchUnit#(p_msg_nbits) switch_unit_e
  (
    .clk     (clk),
    .reset   (reset),
    .in_val  (want_e),
    .in_rdy  (take_e),
    .in_msg  (head_msg),
    .out_val (out_val[2]),
    .out_rdy (out_rdy[2]),
    .out_msg (out_msg[2])
  );

  net_MeshSwitchUnit#(p_msg_nbits) switch_unit_w
  (
    .clk     (clk),
    .reset   (reset),
    .in_val  (want_w),
    .in_rdy  (take_w),
    .in_msg  (head_msg),
    .out_val (out_val[3]),
    .out_rdy (out_rdy[3]),
    .out_msg (out_msg[3])
  );

  net_MeshSwitchUnit#(p_msg_nbits) switch_unit_l
  (
    .clk     (clk),
    .reset   (reset),
    .in_val  (want_l),
    .in_rdy  (take_l),
    .in_msg  (head_msg),
    .out_val (out_val[4]),
    .out_rdy (out_rdy[4]),
    .out_msg (out_msg[4])
  );

  //----------------------------------------------------------------------
  // A head packet leaves its queue when any output takes it
  //----------------------------------------------------------------------

  assign head_rdy = take_n | take_s | take_e | take_w | take_l;

endmodule

`endif /* NET_MESH_ROUTER_V */
