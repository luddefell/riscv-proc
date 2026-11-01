//========================================================================
// MultiCoreDataCache: CacheNet -> 4 banks -> MemNet
//========================================================================

`ifndef SYS_MULTI_CORE_DATA_CACHE_V
`define SYS_MULTI_CORE_DATA_CACHE_V

`include "vc/mem-msgs.v"
`include "lab3_mem/CacheAlt.v"
`include "sys/CacheNet.v"
`include "sys/MemNet.v"

module sys_MultiCoreDataCache
(
  input  logic                    clk,
  input  logic                    reset,

  input  mem_req_4B_t   [3:0]     procreq_msg,
  input  logic          [3:0]     procreq_val,
  output logic          [3:0]     procreq_rdy,

  output mem_resp_4B_t  [3:0]     procresp_msg,
  output logic          [3:0]     procresp_val,
  input  logic          [3:0]     procresp_rdy,

  output mem_req_16B_t            mainmemreq_msg,
  output logic                    mainmemreq_val,
  input  logic                    mainmemreq_rdy,

  input  mem_resp_16B_t           mainmemresp_msg,
  input  logic                    mainmemresp_val,
  output logic                    mainmemresp_rdy
);

  //----------------------------------------------------------------------
  // CacheNet <-> banks
  //----------------------------------------------------------------------

  mem_req_4B_t   [3:0]  cachereq_msg;
  logic          [3:0]  cachereq_val,  cachereq_rdy;
  mem_resp_4B_t  [3:0]  cacheresp_msg;
  logic          [3:0]  cacheresp_val, cacheresp_rdy;

  sys_CacheNet cache_net
  (
    .clk           (clk),
    .reset         (reset),
    .procreq_msg   (procreq_msg),
    .procreq_val   (procreq_val),
    .procreq_rdy   (procreq_rdy),
    .procresp_msg  (procresp_msg),
    .procresp_val  (procresp_val),
    .procresp_rdy  (procresp_rdy),
    .cachereq_msg  (cachereq_msg),
    .cachereq_val  (cachereq_val),
    .cachereq_rdy  (cachereq_rdy),
    .cacheresp_msg (cacheresp_msg),
    .cacheresp_val (cacheresp_val),
    .cacheresp_rdy (cacheresp_rdy)
  );

  //----------------------------------------------------------------------
  // Banks <-> MemNet
  //----------------------------------------------------------------------

  mem_req_16B_t  [3:0]  memreq_msg;
  logic          [3:0]  memreq_val,  memreq_rdy;
  mem_resp_16B_t [3:0]  memresp_msg;
  logic          [3:0]  memresp_val, memresp_rdy;

  sys_MemNet mem_net
  (
    .clk             (clk),
    .reset           (reset),
    .memreq_msg      (memreq_msg),
    .memreq_val      (memreq_val),
    .memreq_rdy      (memreq_rdy),
    .memresp_msg     (memresp_msg),
    .memresp_val     (memresp_val),
    .memresp_rdy     (memresp_rdy),
    .mainmemreq_msg  (mainmemreq_msg),
    .mainmemreq_val  (mainmemreq_val),
    .mainmemreq_rdy  (mainmemreq_rdy),
    .mainmemresp_msg (mainmemresp_msg),
    .mainmemresp_val (mainmemresp_val),
    .mainmemresp_rdy (mainmemresp_rdy)
  );

  //----------------------------------------------------------------------
  // Banks  (TODO: Ludvig)
  //----------------------------------------------------------------------
  // Four lab3_mem_CacheAlt instances. Bank i sits between
  // cachereq/cacheresp[i] (its proc2cache side) and memreq/memresp[i]
  // (its cache2mem side).

  lab3_mem_CacheAlt
  #(
    .p_num_banks (4)
  )
  bank0
  (
    .clk                       (clk),
    .reset                     (reset),

    // CacheNet side

    .proc2cache_reqstream_msg  (cachereq_msg[0]),
    .proc2cache_reqstream_val  (cachereq_val[0]),
    .proc2cache_reqstream_rdy  (cachereq_rdy[0]),

    .proc2cache_respstream_msg (cacheresp_msg[0]),
    .proc2cache_respstream_val (cacheresp_val[0]),
    .proc2cache_respstream_rdy (cacheresp_rdy[0]),

    // MemNet side

    .cache2mem_reqstream_msg   (memreq_msg[0]),
    .cache2mem_reqstream_val   (memreq_val[0]),
    .cache2mem_reqstream_rdy   (memreq_rdy[0]),

    .cache2mem_respstream_msg  (memresp_msg[0]),
    .cache2mem_respstream_val  (memresp_val[0]),
    .cache2mem_respstream_rdy  (memresp_rdy[0])
  );

  lab3_mem_CacheAlt
  #(
    .p_num_banks (4)
  )
  bank1
  (
    .clk                       (clk),
    .reset                     (reset),

    // CacheNet side

    .proc2cache_reqstream_msg  (cachereq_msg[1]),
    .proc2cache_reqstream_val  (cachereq_val[1]),
    .proc2cache_reqstream_rdy  (cachereq_rdy[1]),

    .proc2cache_respstream_msg (cacheresp_msg[1]),
    .proc2cache_respstream_val (cacheresp_val[1]),
    .proc2cache_respstream_rdy (cacheresp_rdy[1]),

    // MemNet side

    .cache2mem_reqstream_msg   (memreq_msg[1]),
    .cache2mem_reqstream_val   (memreq_val[1]),
    .cache2mem_reqstream_rdy   (memreq_rdy[1]),

    .cache2mem_respstream_msg  (memresp_msg[1]),
    .cache2mem_respstream_val  (memresp_val[1]),
    .cache2mem_respstream_rdy  (memresp_rdy[1])
  );

  lab3_mem_CacheAlt
  #(
    .p_num_banks (4)
  )
  bank2
  (
    .clk                       (clk),
    .reset                     (reset),

    // CacheNet side

    .proc2cache_reqstream_msg  (cachereq_msg[2]),
    .proc2cache_reqstream_val  (cachereq_val[2]),
    .proc2cache_reqstream_rdy  (cachereq_rdy[2]),

    .proc2cache_respstream_msg (cacheresp_msg[2]),
    .proc2cache_respstream_val (cacheresp_val[2]),
    .proc2cache_respstream_rdy (cacheresp_rdy[2]),

    // MemNet side

    .cache2mem_reqstream_msg   (memreq_msg[2]),
    .cache2mem_reqstream_val   (memreq_val[2]),
    .cache2mem_reqstream_rdy   (memreq_rdy[2]),

    .cache2mem_respstream_msg  (memresp_msg[2]),
    .cache2mem_respstream_val  (memresp_val[2]),
    .cache2mem_respstream_rdy  (memresp_rdy[2])
  );

  lab3_mem_CacheAlt
  #(
    .p_num_banks (4)
  )
  bank3
  (
    .clk                       (clk),
    .reset                     (reset),

    // CacheNet side

    .proc2cache_reqstream_msg  (cachereq_msg[3]),
    .proc2cache_reqstream_val  (cachereq_val[3]),
    .proc2cache_reqstream_rdy  (cachereq_rdy[3]),

    .proc2cache_respstream_msg (cacheresp_msg[3]),
    .proc2cache_respstream_val (cacheresp_val[3]),
    .proc2cache_respstream_rdy (cacheresp_rdy[3]),

    // MemNet side

    .cache2mem_reqstream_msg   (memreq_msg[3]),
    .cache2mem_reqstream_val   (memreq_val[3]),
    .cache2mem_reqstream_rdy   (memreq_rdy[3]),

    .cache2mem_respstream_msg  (memresp_msg[3]),
    .cache2mem_respstream_val  (memresp_val[3]),
    .cache2mem_respstream_rdy  (memresp_rdy[3])
  );




endmodule

`endif /* SYS_MULTI_CORE_DATA_CACHE_V */
