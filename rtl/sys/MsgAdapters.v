//========================================================================
// Memory <-> Network Message Adapters
//========================================================================

`ifndef SYS_MSG_ADAPTERS_V
`define SYS_MSG_ADAPTERS_V

`include "vc/mem-msgs.v"
`include "vc/net-msgs.v"

//------------------------------------------------------------------------
// Upstream adapter (U)
//------------------------------------------------------------------------

module sys_UpstreamAdapter
#(
  parameter type req_t  = mem_req_4B_t,
  parameter type resp_t = mem_resp_4B_t,

  // 1: CacheNet, dest comes from the address
  // 0: MemNet, every request goes to the single memory terminal
  parameter p_route_by_bank = 1
)
(
  input  logic [1:0]                 terminal_id,

  // Requester side

  input  req_t                       memreq_msg,
  input  logic                       memreq_val,
  output logic                       memreq_rdy,

  output resp_t                      memresp_msg,
  output logic                       memresp_val,
  input  logic                       memresp_rdy,

  // Network side (netreq -> req net in[i], netresp <- resp net out[i])

  output logic [$bits(req_t)+11:0]   netreq_msg,
  output logic                       netreq_val,
  input  logic                       netreq_rdy,

  input  logic [$bits(resp_t)+11:0]  netresp_msg,
  input  logic                       netresp_val,
  output logic                       netresp_rdy
);


  // Request: mem req -> net msg
  assign netreq_msg = {terminal_id, p_route_by_bank ? memreq_msg.addr[5:4] : 2'd0, 8'b0, memreq_msg};


  // Response: net msg -> mem resp

  localparam W_resp  = $bits(resp_t) + 12;
  assign memresp_msg = netresp_msg[W_resp-13:0];

  // val/rdy
  assign netreq_val = memreq_val;
  assign memreq_rdy = netreq_rdy;

  assign memresp_val =  netresp_val;
  assign netresp_rdy = memresp_rdy;

endmodule

//------------------------------------------------------------------------
// Downstream adapter (D)
//------------------------------------------------------------------------

module sys_DownstreamAdapter
#(
  parameter type req_t  = mem_req_4B_t,
  parameter type resp_t = mem_resp_4B_t
)
(
  input  logic [1:0]                 terminal_id,

  // Network side (netreq <- req net out[i], netresp -> resp net in[i])

  input  logic [$bits(req_t)+11:0]   netreq_msg,
  input  logic                       netreq_val,
  output logic                       netreq_rdy,

  output logic [$bits(resp_t)+11:0]  netresp_msg,
  output logic                       netresp_val,
  input  logic                       netresp_rdy,

  // Responder side

  output req_t                       memreq_msg,
  output logic                       memreq_val,
  input  logic                       memreq_rdy,

  input  resp_t                      memresp_msg,
  input  logic                       memresp_val,
  output logic                       memresp_rdy
);

  // Request: net msg -> mem req
  localparam W_req = $bits(req_t) + 12;
  always_comb begin
    memreq_msg = netreq_msg[W_req-13:0];
    memreq_msg.opaque = { 6'b0, netreq_msg[W_req-1:W_req-2] };
  end


  // Response: mem resp -> net msg
  assign netresp_msg = {terminal_id, memresp_msg.opaque[1:0], 8'b0, memresp_msg};

  
  // val/rdy
  assign memreq_val = netreq_val;
  assign netreq_rdy = memreq_rdy;

  assign netresp_val =  memresp_val;
  assign  memresp_rdy  = netresp_rdy;

endmodule

`endif /* SYS_MSG_ADAPTERS_V */
