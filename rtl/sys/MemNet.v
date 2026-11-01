//========================================================================
// MemNet: 4 caches <-> 1 main memory port
//========================================================================

`ifndef SYS_MEM_NET_V
`define SYS_MEM_NET_V

`include "vc/mem-msgs.v"
`include "net/Mesh.v"
`include "sys/MsgAdapters.v"

module sys_MemNet
(
  input  logic                    clk,
  input  logic                    reset,

  input  mem_req_16B_t  [3:0]     memreq_msg,
  input  logic          [3:0]     memreq_val,
  output logic          [3:0]     memreq_rdy,

  output mem_resp_16B_t [3:0]     memresp_msg,
  output logic          [3:0]     memresp_val,
  input  logic          [3:0]     memresp_rdy,

  output mem_req_16B_t            mainmemreq_msg,
  output logic                    mainmemreq_val,
  input  logic                    mainmemreq_rdy,

  input  mem_resp_16B_t           mainmemresp_msg,
  input  logic                    mainmemresp_val,
  output logic                    mainmemresp_rdy
);

  localparam W_req  = $bits(mem_req_16B_t)  + 12;
  localparam W_resp = $bits(mem_resp_16B_t) + 12;

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
  // Cache side: upstream adapters
  //----------------------------------------------------------------------

  sys_UpstreamAdapter#(mem_req_16B_t, mem_resp_16B_t, 0) u0
  (
    .terminal_id (2'd0),
    .memreq_msg  (memreq_msg[0]),
    .memreq_val  (memreq_val[0]),
    .memreq_rdy  (memreq_rdy[0]),
    .memresp_msg (memresp_msg[0]),
    .memresp_val (memresp_val[0]),
    .memresp_rdy (memresp_rdy[0]),
    .netreq_msg  (reqnet_in_msg[0]),
    .netreq_val  (reqnet_in_val[0]),
    .netreq_rdy  (reqnet_in_rdy[0]),
    .netresp_msg (respnet_out_msg[0]),
    .netresp_val (respnet_out_val[0]),
    .netresp_rdy (respnet_out_rdy[0])
  );

  sys_UpstreamAdapter#(mem_req_16B_t, mem_resp_16B_t, 0) u1
  (
    .terminal_id (2'd1),
    .memreq_msg  (memreq_msg[1]),
    .memreq_val  (memreq_val[1]),
    .memreq_rdy  (memreq_rdy[1]),
    .memresp_msg (memresp_msg[1]),
    .memresp_val (memresp_val[1]),
    .memresp_rdy (memresp_rdy[1]),
    .netreq_msg  (reqnet_in_msg[1]),
    .netreq_val  (reqnet_in_val[1]),
    .netreq_rdy  (reqnet_in_rdy[1]),
    .netresp_msg (respnet_out_msg[1]),
    .netresp_val (respnet_out_val[1]),
    .netresp_rdy (respnet_out_rdy[1])
  );

  sys_UpstreamAdapter#(mem_req_16B_t, mem_resp_16B_t, 0) u2
  (
    .terminal_id (2'd2),
    .memreq_msg  (memreq_msg[2]),
    .memreq_val  (memreq_val[2]),
    .memreq_rdy  (memreq_rdy[2]),
    .memresp_msg (memresp_msg[2]),
    .memresp_val (memresp_val[2]),
    .memresp_rdy (memresp_rdy[2]),
    .netreq_msg  (reqnet_in_msg[2]),
    .netreq_val  (reqnet_in_val[2]),
    .netreq_rdy  (reqnet_in_rdy[2]),
    .netresp_msg (respnet_out_msg[2]),
    .netresp_val (respnet_out_val[2]),
    .netresp_rdy (respnet_out_rdy[2])
  );

  sys_UpstreamAdapter#(mem_req_16B_t, mem_resp_16B_t, 0) u3
  (
    .terminal_id (2'd3),
    .memreq_msg  (memreq_msg[3]),
    .memreq_val  (memreq_val[3]),
    .memreq_rdy  (memreq_rdy[3]),
    .memresp_msg (memresp_msg[3]),
    .memresp_val (memresp_val[3]),
    .memresp_rdy (memresp_rdy[3]),
    .netreq_msg  (reqnet_in_msg[3]),
    .netreq_val  (reqnet_in_val[3]),
    .netreq_rdy  (reqnet_in_rdy[3]),
    .netresp_msg (respnet_out_msg[3]),
    .netresp_val (respnet_out_val[3]),
    .netresp_rdy (respnet_out_rdy[3])
  );

  //----------------------------------------------------------------------
  // Memory side: one downstream adapter on terminal 0
  //----------------------------------------------------------------------

  sys_DownstreamAdapter#(mem_req_16B_t, mem_resp_16B_t) d0
  (
    .terminal_id (2'd0),
    .netreq_msg  (reqnet_out_msg[0]),
    .netreq_val  (reqnet_out_val[0]),
    .netreq_rdy  (reqnet_out_rdy[0]),
    .netresp_msg (respnet_in_msg[0]),
    .netresp_val (respnet_in_val[0]),
    .netresp_rdy (respnet_in_rdy[0]),
    .memreq_msg  (mainmemreq_msg),
    .memreq_val  (mainmemreq_val),
    .memreq_rdy  (mainmemreq_rdy),
    .memresp_msg (mainmemresp_msg),
    .memresp_val (mainmemresp_val),
    .memresp_rdy (mainmemresp_rdy)
  );

  // Terminals 1-3 have no memory behind them. Nothing should ever be
  // routed out of them, so they never accept; nothing is injected either.

  assign reqnet_out_rdy[3:1] = 3'b0;
  assign respnet_in_val[3:1] = 3'b0;
  assign respnet_in_msg[3:1] = '0;

endmodule

`endif /* SYS_MEM_NET_V */
