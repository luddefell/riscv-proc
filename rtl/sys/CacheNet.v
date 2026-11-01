//========================================================================
// CacheNet: 4 procs <-> 4 cache banks
//========================================================================

`ifndef SYS_CACHE_NET_V
`define SYS_CACHE_NET_V

`include "vc/mem-msgs.v"
`include "net/Mesh.v"
`include "sys/MsgAdapters.v"

module sys_CacheNet
(
  input  logic                   clk,
  input  logic                   reset,

  input  mem_req_4B_t  [3:0]     procreq_msg,
  input  logic         [3:0]     procreq_val,
  output logic         [3:0]     procreq_rdy,

  output mem_resp_4B_t [3:0]     procresp_msg,
  output logic         [3:0]     procresp_val,
  input  logic         [3:0]     procresp_rdy,

  output mem_req_4B_t  [3:0]     cachereq_msg,
  output logic         [3:0]     cachereq_val,
  input  logic         [3:0]     cachereq_rdy,

  input  mem_resp_4B_t [3:0]     cacheresp_msg,
  input  logic         [3:0]     cacheresp_val,
  output logic         [3:0]     cacheresp_rdy
);

  localparam W_req  = $bits(mem_req_4B_t)  + 12;
  localparam W_resp = $bits(mem_resp_4B_t) + 12;

  //----------------------------------------------------------------------
  // Networks
  //----------------------------------------------------------------------

  logic [3:0]              reqnet_in_val,   reqnet_in_rdy;
  logic [3:0][W_req-1:0]   reqnet_in_msg;
  logic [3:0]              reqnet_out_val,  reqnet_out_rdy;
  logic [3:0][W_req-1:0]   reqnet_out_msg;

  logic [3:0]              respnet_in_val,  respnet_in_rdy;
  logic [3:0][W_resp-1:0]  respnet_in_msg;
  logic [3:0]              respnet_out_val, respnet_out_rdy;
  logic [3:0][W_resp-1:0]  respnet_out_msg;

  net_Mesh#(W_req) req_net
  (
    .clk     (clk),
    .reset   (reset),
    .in_val  (reqnet_in_val),
    .in_rdy  (reqnet_in_rdy),
    .in_msg  (reqnet_in_msg),
    .out_val (reqnet_out_val),
    .out_rdy (reqnet_out_rdy),
    .out_msg (reqnet_out_msg)
  );

  net_Mesh#(W_resp) resp_net
  (
    .clk     (clk),
    .reset   (reset),
    .in_val  (respnet_in_val),
    .in_rdy  (respnet_in_rdy),
    .in_msg  (respnet_in_msg),
    .out_val (respnet_out_val),
    .out_rdy (respnet_out_rdy),
    .out_msg (respnet_out_msg)
  );

  //----------------------------------------------------------------------
  // Proc side: upstream adapters
  //----------------------------------------------------------------------

  sys_UpstreamAdapter u0
  (
    .terminal_id (2'd0),
    .memreq_msg  (procreq_msg[0]),
    .memreq_val  (procreq_val[0]),
    .memreq_rdy  (procreq_rdy[0]),
    .memresp_msg (procresp_msg[0]),
    .memresp_val (procresp_val[0]),
    .memresp_rdy (procresp_rdy[0]),
    .netreq_msg  (reqnet_in_msg[0]),
    .netreq_val  (reqnet_in_val[0]),
    .netreq_rdy  (reqnet_in_rdy[0]),
    .netresp_msg (respnet_out_msg[0]),
    .netresp_val (respnet_out_val[0]),
    .netresp_rdy (respnet_out_rdy[0])
  );

  sys_UpstreamAdapter u1
  (
    .terminal_id (2'd1),
    .memreq_msg  (procreq_msg[1]),
    .memreq_val  (procreq_val[1]),
    .memreq_rdy  (procreq_rdy[1]),
    .memresp_msg (procresp_msg[1]),
    .memresp_val (procresp_val[1]),
    .memresp_rdy (procresp_rdy[1]),
    .netreq_msg  (reqnet_in_msg[1]),
    .netreq_val  (reqnet_in_val[1]),
    .netreq_rdy  (reqnet_in_rdy[1]),
    .netresp_msg (respnet_out_msg[1]),
    .netresp_val (respnet_out_val[1]),
    .netresp_rdy (respnet_out_rdy[1])
  );

  sys_UpstreamAdapter u2
  (
    .terminal_id (2'd2),
    .memreq_msg  (procreq_msg[2]),
    .memreq_val  (procreq_val[2]),
    .memreq_rdy  (procreq_rdy[2]),
    .memresp_msg (procresp_msg[2]),
    .memresp_val (procresp_val[2]),
    .memresp_rdy (procresp_rdy[2]),
    .netreq_msg  (reqnet_in_msg[2]),
    .netreq_val  (reqnet_in_val[2]),
    .netreq_rdy  (reqnet_in_rdy[2]),
    .netresp_msg (respnet_out_msg[2]),
    .netresp_val (respnet_out_val[2]),
    .netresp_rdy (respnet_out_rdy[2])
  );

  sys_UpstreamAdapter u3
  (
    .terminal_id (2'd3),
    .memreq_msg  (procreq_msg[3]),
    .memreq_val  (procreq_val[3]),
    .memreq_rdy  (procreq_rdy[3]),
    .memresp_msg (procresp_msg[3]),
    .memresp_val (procresp_val[3]),
    .memresp_rdy (procresp_rdy[3]),
    .netreq_msg  (reqnet_in_msg[3]),
    .netreq_val  (reqnet_in_val[3]),
    .netreq_rdy  (reqnet_in_rdy[3]),
    .netresp_msg (respnet_out_msg[3]),
    .netresp_val (respnet_out_val[3]),
    .netresp_rdy (respnet_out_rdy[3])
  );

  //----------------------------------------------------------------------
  // Cache side: downstream adapters
  //----------------------------------------------------------------------

  sys_DownstreamAdapter d0
  (
    .terminal_id (2'd0),
    .netreq_msg  (reqnet_out_msg[0]),
    .netreq_val  (reqnet_out_val[0]),
    .netreq_rdy  (reqnet_out_rdy[0]),
    .netresp_msg (respnet_in_msg[0]),
    .netresp_val (respnet_in_val[0]),
    .netresp_rdy (respnet_in_rdy[0]),
    .memreq_msg  (cachereq_msg[0]),
    .memreq_val  (cachereq_val[0]),
    .memreq_rdy  (cachereq_rdy[0]),
    .memresp_msg (cacheresp_msg[0]),
    .memresp_val (cacheresp_val[0]),
    .memresp_rdy (cacheresp_rdy[0])
  );

  sys_DownstreamAdapter d1
  (
    .terminal_id (2'd1),
    .netreq_msg  (reqnet_out_msg[1]),
    .netreq_val  (reqnet_out_val[1]),
    .netreq_rdy  (reqnet_out_rdy[1]),
    .netresp_msg (respnet_in_msg[1]),
    .netresp_val (respnet_in_val[1]),
    .netresp_rdy (respnet_in_rdy[1]),
    .memreq_msg  (cachereq_msg[1]),
    .memreq_val  (cachereq_val[1]),
    .memreq_rdy  (cachereq_rdy[1]),
    .memresp_msg (cacheresp_msg[1]),
    .memresp_val (cacheresp_val[1]),
    .memresp_rdy (cacheresp_rdy[1])
  );

  sys_DownstreamAdapter d2
  (
    .terminal_id (2'd2),
    .netreq_msg  (reqnet_out_msg[2]),
    .netreq_val  (reqnet_out_val[2]),
    .netreq_rdy  (reqnet_out_rdy[2]),
    .netresp_msg (respnet_in_msg[2]),
    .netresp_val (respnet_in_val[2]),
    .netresp_rdy (respnet_in_rdy[2]),
    .memreq_msg  (cachereq_msg[2]),
    .memreq_val  (cachereq_val[2]),
    .memreq_rdy  (cachereq_rdy[2]),
    .memresp_msg (cacheresp_msg[2]),
    .memresp_val (cacheresp_val[2]),
    .memresp_rdy (cacheresp_rdy[2])
  );

  sys_DownstreamAdapter d3
  (
    .terminal_id (2'd3),
    .netreq_msg  (reqnet_out_msg[3]),
    .netreq_val  (reqnet_out_val[3]),
    .netreq_rdy  (reqnet_out_rdy[3]),
    .netresp_msg (respnet_in_msg[3]),
    .netresp_val (respnet_in_val[3]),
    .netresp_rdy (respnet_in_rdy[3]),
    .memreq_msg  (cachereq_msg[3]),
    .memreq_val  (cachereq_val[3]),
    .memreq_rdy  (cachereq_rdy[3]),
    .memresp_msg (cacheresp_msg[3]),
    .memresp_val (cacheresp_val[3]),
    .memresp_rdy (cacheresp_rdy[3])
  );

endmodule

`endif /* SYS_CACHE_NET_V */
