//========================================================================
// MultiCoreSys: 4 cores, private I$, shared 4-bank D$
//========================================================================

`ifndef SYS_MULTI_CORE_SYS_V
`define SYS_MULTI_CORE_SYS_V

`include "vc/mem-msgs.v"
`include "lab2_proc/ProcAlt.v"
`include "lab3_mem/CacheAlt.v"
`include "sys/MemNet.v"
`include "sys/MultiCoreDataCache.v"

module sys_MultiCoreSys
(
  input  logic                    clk,
  input  logic                    reset,

  input  logic          [3:0][31:0] mngr2proc_msg,
  input  logic          [3:0]     mngr2proc_val,
  output logic          [3:0]     mngr2proc_rdy,

  output logic          [3:0][31:0] proc2mngr_msg,
  output logic          [3:0]     proc2mngr_val,
  input  logic          [3:0]     proc2mngr_rdy,

  // Main memory port 1: I$ refills

  output mem_req_16B_t            imemreq_msg,
  output logic                    imemreq_val,
  input  logic                    imemreq_rdy,

  input  mem_resp_16B_t           imemresp_msg,
  input  logic                    imemresp_val,
  output logic                    imemresp_rdy,

  // Main memory port 0: D$ refills and evictions

  output mem_req_16B_t            dmemreq_msg,
  output logic                    dmemreq_val,
  input  logic                    dmemreq_rdy,

  input  mem_resp_16B_t           dmemresp_msg,
  input  logic                    dmemresp_val,
  output logic                    dmemresp_rdy,

  output logic          [3:0]     commit_inst,
  output logic          [3:0]     stats_en
);

  //----------------------------------------------------------------------
  // Signals between cores and caches
  //----------------------------------------------------------------------

  mem_req_4B_t   [3:0]  proc_imemreq_msg;
  logic          [3:0]  proc_imemreq_val,  proc_imemreq_rdy;
  mem_resp_4B_t  [3:0]  proc_imemresp_msg;
  logic          [3:0]  proc_imemresp_val, proc_imemresp_rdy;

  mem_req_4B_t   [3:0]  proc_dmemreq_msg;
  logic          [3:0]  proc_dmemreq_val,  proc_dmemreq_rdy;
  mem_resp_4B_t  [3:0]  proc_dmemresp_msg;
  logic          [3:0]  proc_dmemresp_val, proc_dmemresp_rdy;


  //----------------------------------------------------------------------
  // Private I$ (one per core, not banked)
  //----------------------------------------------------------------------

  mem_req_16B_t  [3:0]  icache_memreq_msg;
  logic          [3:0]  icache_memreq_val,  icache_memreq_rdy;
  mem_resp_16B_t [3:0]  icache_memresp_msg;
  logic          [3:0]  icache_memresp_val, icache_memresp_rdy;

  genvar i;
  generate
    for ( i = 0; i < 4; i = i + 1 ) begin : icache

      lab3_mem_CacheAlt#(1) cache
      (
        .clk                       (clk),
        .reset                     (reset),

        .proc2cache_reqstream_msg  (proc_imemreq_msg[i]),
        .proc2cache_reqstream_val  (proc_imemreq_val[i]),
        .proc2cache_reqstream_rdy  (proc_imemreq_rdy[i]),

        .proc2cache_respstream_msg (proc_imemresp_msg[i]),
        .proc2cache_respstream_val (proc_imemresp_val[i]),
        .proc2cache_respstream_rdy (proc_imemresp_rdy[i]),

        .cache2mem_reqstream_msg   (icache_memreq_msg[i]),
        .cache2mem_reqstream_val   (icache_memreq_val[i]),
        .cache2mem_reqstream_rdy   (icache_memreq_rdy[i]),

        .cache2mem_respstream_msg  (icache_memresp_msg[i]),
        .cache2mem_respstream_val  (icache_memresp_val[i]),
        .cache2mem_respstream_rdy  (icache_memresp_rdy[i])
      );

    end
  endgenerate


  sys_MemNet icache_net
  (
    .clk             (clk),
    .reset           (reset),
    .memreq_msg      (icache_memreq_msg),
    .memreq_val      (icache_memreq_val),
    .memreq_rdy      (icache_memreq_rdy),
    .memresp_msg     (icache_memresp_msg),
    .memresp_val     (icache_memresp_val),
    .memresp_rdy     (icache_memresp_rdy),
    .mainmemreq_msg  (imemreq_msg),
    .mainmemreq_val  (imemreq_val),
    .mainmemreq_rdy  (imemreq_rdy),
    .mainmemresp_msg (imemresp_msg),
    .mainmemresp_val (imemresp_val),
    .mainmemresp_rdy (imemresp_rdy)
  );

  //----------------------------------------------------------------------
  // Shared D$
  //----------------------------------------------------------------------

  sys_MultiCoreDataCache dcache
  (
    .clk             (clk),
    .reset           (reset),
    .procreq_msg     (proc_dmemreq_msg),
    .procreq_val     (proc_dmemreq_val),
    .procreq_rdy     (proc_dmemreq_rdy),
    .procresp_msg    (proc_dmemresp_msg),
    .procresp_val    (proc_dmemresp_val),
    .procresp_rdy    (proc_dmemresp_rdy),
    .mainmemreq_msg  (dmemreq_msg),
    .mainmemreq_val  (dmemreq_val),
    .mainmemreq_rdy  (dmemreq_rdy),
    .mainmemresp_msg (dmemresp_msg),
    .mainmemresp_val (dmemresp_val),
    .mainmemresp_rdy (dmemresp_rdy)
  );

  //----------------------------------------------------------------------
  // The cores
  //----------------------------------------------------------------------

  generate
    for ( i = 0; i < 4; i = i + 1 ) begin : core

        lab2_proc_ProcAlt
        #(
          .p_num_cores (4)
        )
        proc
        (
          .clk                 (clk),
          .reset               (reset),

          .mngr2proc_msg       (mngr2proc_msg[i]),
          .mngr2proc_val       (mngr2proc_val[i]),
          .mngr2proc_rdy       (mngr2proc_rdy[i]),

          .proc2mngr_msg       (proc2mngr_msg[i]),
          .proc2mngr_val       (proc2mngr_val[i]),
          .proc2mngr_rdy       (proc2mngr_rdy[i]),

          .imem_reqstream_msg  (proc_imemreq_msg[i]),
          .imem_reqstream_val  (proc_imemreq_val[i]),
          .imem_reqstream_rdy  (proc_imemreq_rdy[i]),

          .imem_respstream_msg (proc_imemresp_msg[i]),
          .imem_respstream_val (proc_imemresp_val[i]),
          .imem_respstream_rdy (proc_imemresp_rdy[i]),

          .dmem_reqstream_msg  (proc_dmemreq_msg[i]),
          .dmem_reqstream_val  (proc_dmemreq_val[i]),
          .dmem_reqstream_rdy  (proc_dmemreq_rdy[i]),

          .dmem_respstream_msg (proc_dmemresp_msg[i]),
          .dmem_respstream_val (proc_dmemresp_val[i]),
          .dmem_respstream_rdy (proc_dmemresp_rdy[i]),

          .core_id             (i),
          .commit_inst         (commit_inst[i]),
          .stats_en            (stats_en[i])
        );

    end
  endgenerate

endmodule

`endif /* SYS_MULTI_CORE_SYS_V */
