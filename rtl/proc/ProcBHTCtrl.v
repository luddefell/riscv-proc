//=========================================================================
// 5-Stage Simple Pipelined Processor Control
//=========================================================================

`ifndef PROC_PROC_BHT_CTRL_V
`define PROC_PROC_BHT_CTRL_V

`include "vc/trace.v"

`include "lab2_proc/tinyrv2_encoding.v"

module proc_ProcBHTCtrl
(
  input  logic        clk,
  input  logic        reset,

  // Instruction Memory Port

  output logic        imem_reqstream_val,
  input  logic        imem_reqstream_rdy,
  input  logic        imem_respstream_val,
  output logic        imem_respstream_rdy,
  output logic        imem_respstream_drop,

  // Data Memory Port

  output logic        dmem_reqstream_val,
  input  logic        dmem_reqstream_rdy,
  input  logic        dmem_respstream_val,
  output logic        dmem_respstream_rdy,

  output logic [1:0]  dmem_type_X,

  // mngr communication port

  input  logic        mngr2proc_val,
  output logic        mngr2proc_rdy,
  output logic        proc2mngr_val,
  input  logic        proc2mngr_rdy,

  // control signals (ctrl->dpath)

  output logic        reg_en_F,
  output logic [2:0]  pc_sel_F,

  output logic        reg_en_D,
  output logic [2:0]  op1_sel_D,
  output logic [2:0]  op2_sel_D,
  output logic [1:0]  csrr_sel_D,
  output logic [2:0]  imm_type_D,

  output logic [1:0]  sw_data_sel_D,

  output logic        reg_en_X,
  output logic [3:0]  alu_fn_X,

  output logic        reg_en_M,
  output logic        wb_result_sel_M,

  output logic        reg_en_W,
  output logic [4:0]  rf_waddr_W,
  output logic        rf_wen_W,
  output logic        stats_en_wen_W,

  output logic        imul_req_val_D, // for imul
  output logic        imul_resp_rdy_X,  
  output logic [1:0]  ex_result_sel_X,

  output logic        bht_update_en_X,
  output logic        bht_update_taken_X,

  // status signals (dpath->ctrl)

  input  logic [31:0] inst_D,
  input  logic        br_cond_eq_X,
  input  logic        br_cond_lt_X,
  input  logic        br_cond_ltu_X,

  input               logic imul_req_rdy_D,
  input               logic imul_resp_val_X,

  input  logic        bht_pred_taken_D,

  // extra ports

  output logic        commit_inst
);

  //----------------------------------------------------------------------
  // Notes
  //----------------------------------------------------------------------
  // We follow this principle to organize code for each pipeline stage in
  // the control unit.  Register enable logics should always at the
  // beginning. It followed by pipeline registers. Then logic that is not
  // dependent on stall or squash signals. Then logic that is dependent
  // on stall or squash signals. At the end there should be signals meant
  // to be passed to the next stage in the pipeline.

  //----------------------------------------------------------------------
  // Valid, stall, and squash signals
  //----------------------------------------------------------------------
  // We use valid signal to indicate if the instruction is valid.  An
  // instruction can become invalid because of being squashed or
  // stalled. Notice that invalid instructions are microarchitectural
  // events, they are different from archtectural no-ops. We must be
  // careful about control signals that might change the state of the
  // processor. We should always AND outgoing control signals with valid
  // signal.

  logic val_F;
  logic val_D;
  logic val_X;
  logic val_M;
  logic val_W;

  // Managing the stall and squash signals is one of the most important,
  // yet also one of the most complex, aspects of designing a pipelined
  // processor. We will carefully use four signals per stage to manage
  // stalling and squashing: ostall_A, osquash_A, stall_A, and squash_A.
  //
  // We denote the stall signals _originating_ from stage A as
  // ostall_A. For example, if stage A can stall due to a pipeline
  // harzard, then ostall_A would need to factor in the stalling
  // condition for this pipeline harzard.

  logic ostall_F;  // can ostall due to imem_respstream_val
  logic ostall_D;  // can ostall due to mngr2proc_val or other hazards
  logic ostall_X;  // can ostall due to dmem_reqstream_rdy
  logic ostall_M;  // can ostall due to dmem_respstream_val
  logic ostall_W;  // can ostall due to proc2mngr_rdy

  // The stall_A signal should be used to indicate when stage A is indeed
  // stalling. stall_A will be a function of ostall_A and all the ostall
  // signals of stages in front of it in the pipeline.

  logic stall_F;
  logic stall_D;
  logic stall_X;
  logic stall_M;
  logic stall_W;

  // We denote the squash signals _originating_ from stage A as
  // osquash_A. For example, if stage A needs to squash the stages behind
  // A in the pipeline, then osquash_A would need to factor in this
  // squash condition.

  logic osquash_D; // can osquash due to unconditional jumps
  logic osquash_X; // can osquash due to taken branches

  // The squash_A signal should be used to indicate when stage A is being
  // squashed. squash_A will _not_ be a function of osquash_A, since
  // osquash_A means to squash the stages _behind_ A in the pipeline, but
  // not to squash A itself.

  logic squash_F;
  logic squash_D;

  //----------------------------------------------------------------------
  // F stage
  //----------------------------------------------------------------------

  // Register enable logic

  assign reg_en_F = !stall_F || squash_F;

  // Pipeline registers

  always_ff @( posedge clk ) begin
    if ( reset )
      val_F <= 1'b0;
    else if ( reg_en_F )
      val_F <= 1'b1;
  end

  // forward declaration for PC sel

  logic       pc_redirect_X;
  logic       pc_redirect_D;
  logic [2:0] pc_sel_X;
  logic [2:0] pc_sel_D;

  // PC select logic

  always_comb begin
    if ( pc_redirect_X )   // If a branch is taken in X stage
      pc_sel_F = pc_sel_X; // Use pc from X
    else if ( pc_redirect_D )
      pc_sel_F = pc_sel_D; 
    else
      pc_sel_F = 2'b0;     // Use pc+4
  end

  // ostall due to the imem response not valid.

  assign ostall_F = val_F && !imem_respstream_val;

  // stall and squash in F

  assign stall_F  = val_F && ( ostall_F  || ostall_D || ostall_X || ostall_M || ostall_W );
  assign squash_F = val_F && ( osquash_D || osquash_X );

  // We drop the mem response when we are getting squashed

  assign imem_respstream_drop = squash_F;

  // imem is very special. Actually imem requests are sent before the F
  // stage. Note that we need to factor in reset to the imem_reqstream_val
  // signal because we don't want to send out imem request when we are
  // resetting.

  assign imem_reqstream_val  = ( !stall_F || squash_F ) && !reset;
  assign imem_respstream_rdy = !stall_F || squash_F;

  // Valid signal for the next stage (stage D)

  logic  next_val_F;
  assign next_val_F = val_F && !stall_F && !squash_F;

  //----------------------------------------------------------------------
  // D stage
  //----------------------------------------------------------------------

  // Register enable logic

  assign reg_en_D = !stall_D || squash_D;

  // Pipline registers

  always_ff @( posedge clk ) begin
    if ( reset )
      val_D <= 1'b0;
    else if ( reg_en_D )
      val_D <= next_val_F;
  end

  // Parse instruction fields

  logic   [4:0]  inst_rd_D;
  logic   [4:0]  inst_rs1_D;
  logic   [4:0]  inst_rs2_D;
  logic   [11:0] inst_csr_D;

  lab2_proc_tinyrv2_encoding_InstUnpack inst_unpack
  (
    .inst     (inst_D),
    .opcode   (),
    .rd       (inst_rd_D),
    .rs1      (inst_rs1_D),
    .rs2      (inst_rs2_D),
    .funct3   (),
    .funct7   (),
    .csr      (inst_csr_D)
  );

  // branch logic, redirect PC in F if branch is taken in D

  logic is_cond_br_D;
  assign is_cond_br_D = ( br_type_D == br_bne ) || ( br_type_D == br_beq )
                     || ( br_type_D == br_lt  ) || ( br_type_D == br_ltu );

  always_comb begin
    if ( val_D && ( br_type_D == br_j) ) begin
      pc_redirect_D = 1'b1;
      pc_sel_D      = 3'd2; // use branch target
    end
    else if ( val_D && is_cond_br_D && bht_pred_taken_D ) begin
      pc_redirect_D = 1'b1;
      pc_sel_D      = 3'd2; // predicted taken: jal_target_D holds pc_D + imm_b
    end
    else begin
      pc_redirect_D = 1'b0;
      pc_sel_D      = 3'b0; // use pc+4
    end
  end

  // Generic Parameters -- yes or no

  localparam n = 1'd0;
  localparam y = 1'd1;

  // Register specifiers

  localparam rx = 5'bx;   // don't care
  localparam r0 = 5'd0;   // zero
  localparam rL = 5'd31;  // for jal

  // Branch type

  localparam br_x     = 3'bx; // Don't care
  localparam br_na    = 3'b0; // No branch
  localparam br_bne   = 3'b1; // bne
  localparam br_j     = 3'd2;
  localparam br_jalr  = 3'd3;
  localparam br_beq   = 3'd4;
  localparam br_lt    = 3'd5;
  localparam br_ltu   = 3'd6;

  // Operand 1 Mux Select
  localparam am_x        = 3'bx;
  localparam am_pc       = 3'd0;
  localparam am_rf       = 3'd1;
  localparam am_bypass_W = 3'd2; // W->D bypass
  localparam am_bypass_M = 3'd3; // M->D
  localparam am_bypass_X = 3'd4; // X->D

  // Operand 2 Mux Select
  localparam bm_x        = 3'bx; // Don't care
  localparam bm_rf       = 3'd0; // Use data from register file
  localparam bm_imm      = 3'd1; // Use sign-extended immediate
  localparam bm_csr      = 3'd2; // Use from mngr data
  localparam bm_bypass_W = 3'd3; // W->D bypass
  localparam bm_bypass_M = 3'd4; // M->D
  localparam bm_bypass_X = 3'd5; // X->D

  // ALU Function

  localparam alu_x    = 4'bx;
  localparam alu_add  = 4'd0;
  localparam alu_sub  = 4'd1;

  // more alu function signals for cs 
  localparam alu_and  = 4'd2; 
  localparam alu_or   = 4'd3;
  localparam alu_xor  = 4'd4;
  localparam alu_slt  = 4'd5;
  localparam alu_sra  = 4'd6; 
  localparam alu_srl  = 4'd7;
  localparam alu_sll  = 4'd8; 

  localparam alu_cp0  = 4'd11;
  localparam alu_cp1  = 4'd12;

  // Immediate Type
  localparam imm_x    = 3'bx;
  localparam imm_i    = 3'd0;
  localparam imm_s    = 3'd1;
  localparam imm_b    = 3'd2;
  localparam imm_u    = 3'd3;
  localparam imm_j    = 3'd4;

  // Memory Request Type

  localparam nr       = 2'd0; // No request
  localparam ld       = 2'd1; // Load
  localparam st       = 2'd2; // Store

  // Execute Result Mux Select
  localparam ex_pc4   = 2'd0;
  localparam ex_alu   = 2'd1;
  localparam ex_mul   = 2'd2;   

  // Writeback Mux Select

  localparam wm_x     = 1'bx; // Don't care
  localparam wm_a     = 1'b0; // Use ALU output
  localparam wm_m     = 1'b1; // Use data memory response

  // Instruction Decode

  logic       inst_val_D;
  logic [2:0] br_type_D;
  logic       rs1_en_D;
  logic       rs2_en_D;
  logic [3:0] alu_fn_D;
  logic [1:0] dmem_type_D;
  logic       wb_result_sel_D;
  logic       rf_wen_D;
  logic       csrr_D;
  logic       csrw_D;
  logic       proc2mngr_val_D;
  logic       mngr2proc_rdy_D;
  logic       stats_en_wen_D;
  logic       is_mul_D;
  logic [1:0] ex_result_sel_D;

  logic [2:0] op1_sel_default_D;
  logic [2:0] op2_sel_default_D;


  task cs
  (
    input logic       cs_inst_val,
    input logic [2:0] cs_br_type,
    input logic [2:0] cs_imm_type,
    input logic [2:0] cs_op1_sel,
    input logic       cs_rs1_en,
    input logic [2:0] cs_op2_sel,
    input logic       cs_rs2_en,
    input logic [3:0] cs_alu_fn,
    input logic [1:0] cs_dmem_type,
    input logic       cs_wb_result_sel,
    input logic       cs_rf_wen,
    input logic       cs_csrr,
    input logic       cs_csrw,
    input logic       cs_is_mul,
    input logic [1:0] cs_ex_result_sel
  );
  begin
    inst_val_D        = cs_inst_val;
    br_type_D         = cs_br_type;
    imm_type_D        = cs_imm_type;
    op1_sel_default_D = cs_op1_sel;
    rs1_en_D          = cs_rs1_en;
    op2_sel_default_D = cs_op2_sel;
    rs2_en_D          = cs_rs2_en;
    alu_fn_D          = cs_alu_fn;
    dmem_type_D       = cs_dmem_type;
    wb_result_sel_D   = cs_wb_result_sel;
    rf_wen_D          = cs_rf_wen;
    csrr_D            = cs_csrr;
    csrw_D            = cs_csrw;
    is_mul_D          = cs_is_mul;
    ex_result_sel_D   = cs_ex_result_sel;
  end
  endtask

  // Control signals table

  always_comb begin

    casez ( inst_D )

      //                            br      imm   op1    rs1 op2    rs2 alu      dmm wbmux rf
      //                       val  type    type  muxsel en  muxsel  en fn       typ sel  wen csrr csrw is_mul execute_mux input
      `TINYRV2_INST_NOP     :cs( y, br_na,  imm_x, am_x,  n, bm_x,   n, alu_x,   nr, wm_a, n,  n,   n,   n, ex_alu );
      `TINYRV2_INST_ADD     :cs( y, br_na,  imm_x, am_rf, y, bm_rf,  y, alu_add, nr, wm_a, y,  n,   n,   n, ex_alu );
      `TINYRV2_INST_LW      :cs( y, br_na,  imm_i, am_rf, y, bm_imm, n, alu_add, ld, wm_m, y,  n,   n,   n, ex_alu );
      `TINYRV2_INST_BNE     :cs( y, br_bne, imm_b, am_rf, y, bm_rf,  y, alu_x,   nr, wm_a, n,  n,   n,   n, ex_alu );
      `TINYRV2_INST_CSRR    :cs( y, br_na,  imm_i, am_rf, n, bm_csr, n, alu_cp1, nr, wm_a, y,  y,   n,   n, ex_alu );
      `TINYRV2_INST_CSRW    :cs( y, br_na,  imm_i, am_rf, y, bm_rf,  n, alu_cp0, nr, wm_a, n,  n,   y,   n, ex_alu );

      // we added 

      // R-R 
      `TINYRV2_INST_AND     :cs( y, br_na,  imm_x, am_rf, y, bm_rf,  y, alu_and, nr, wm_a, y,   n,  n,   n, ex_alu );
      `TINYRV2_INST_OR      :cs( y, br_na,  imm_x, am_rf, y, bm_rf,  y, alu_or,  nr, wm_a, y,   n,  n,   n, ex_alu );
      `TINYRV2_INST_XOR     :cs( y, br_na,  imm_x, am_rf, y, bm_rf,  y, alu_xor, nr, wm_a, y,   n,  n,   n, ex_alu );
      `TINYRV2_INST_SLT     :cs( y, br_na,  imm_x, am_rf, y, bm_rf,  y, alu_slt, nr, wm_a, y,   n,  n,   n, ex_alu );
      `TINYRV2_INST_SRA     :cs( y, br_na,  imm_x, am_rf, y, bm_rf,  y, alu_sra, nr, wm_a, y,   n,  n,   n, ex_alu );
      `TINYRV2_INST_SRL     :cs( y, br_na,  imm_x, am_rf, y, bm_rf,  y, alu_srl, nr, wm_a, y,   n,  n,   n, ex_alu );
      `TINYRV2_INST_SLL     :cs( y, br_na,  imm_x, am_rf, y, bm_rf,  y, alu_sll, nr, wm_a, y,   n,  n,   n, ex_alu );
      `TINYRV2_INST_SUB     :cs( y, br_na,  imm_x, am_rf, y, bm_rf,  y, alu_sub, nr, wm_a, y,   n,  n,   n, ex_alu );
      `TINYRV2_INST_MUL     :cs( y, br_na,  imm_x, am_rf, y, bm_rf,  y, alu_x,   nr, wm_a, y,   n,  n,   y, ex_mul );

      // R-I
      `TINYRV2_INST_ADDI    :cs( y, br_na,  imm_i, am_rf, y, bm_imm, n, alu_add, nr, wm_a, y,  n,   n,   n, ex_alu );    
      `TINYRV2_INST_ORI     :cs( y, br_na,  imm_i, am_rf, y, bm_imm, n, alu_or,  nr, wm_a, y,  n,   n,   n, ex_alu ); 
      `TINYRV2_INST_SLTI    :cs( y, br_na,  imm_i, am_rf, y, bm_imm, n, alu_slt, nr, wm_a, y,  n,   n,   n, ex_alu );
      `TINYRV2_INST_SLLI    :cs( y, br_na,  imm_i, am_rf, y, bm_imm, n, alu_sll, nr, wm_a, y,  n,   n,   n, ex_alu );
      `TINYRV2_INST_SRAI    :cs( y, br_na,  imm_i, am_rf, y, bm_imm, n, alu_sra, nr, wm_a, y,  n,   n,   n, ex_alu );
      
      `TINYRV2_INST_JAL     :cs( y, br_j,   imm_j, am_x,  n, bm_x,   n, alu_add, nr, wm_a, y,  n,   n,   n, ex_pc4 );    
      `TINYRV2_INST_JALR    :cs( y, br_jalr,imm_i, am_rf, y, bm_imm, n, alu_add, nr, wm_a, y,  n,   n,   n, ex_pc4 );
      `TINYRV2_INST_SW      :cs( y, br_na,  imm_s, am_rf, y, bm_imm, y, alu_add, st, wm_x, n,  n,   n,   n, ex_alu ); 
      `TINYRV2_INST_LUI     :cs( y, br_na,  imm_u, am_rf, n, bm_imm, n, alu_cp1, nr, wm_a, y,  n,   n,   n, ex_alu );     
      `TINYRV2_INST_AUIPC   :cs( y, br_na,  imm_u, am_pc, n, bm_imm, n, alu_add, nr, wm_a, y,  n,   n,   n, ex_alu );
      
      `TINYRV2_INST_BLT     :cs( y, br_lt,  imm_b, am_rf, y, bm_rf,  y, alu_x,   nr, wm_a, n,  n,   n,   n, ex_alu );
      `TINYRV2_INST_BLTU    :cs( y, br_ltu, imm_b, am_rf, y, bm_rf,  y, alu_x,   nr, wm_a, n,  n,   n,   n, ex_alu );    
      // untested 


      `TINYRV2_INST_BEQ     :cs( y, br_beq, imm_b, am_rf, y, bm_rf,  y, alu_x,   nr, wm_a, n,  n,   n,   n, ex_alu );

      default               :cs( n, br_x,  imm_x, am_x, n, bm_x,    n, alu_x,   nr, wm_x, n,    n,  n,  n, ex_alu );

    endcase
  end // always_comb

  logic [4:0] rf_waddr_D;
  assign rf_waddr_D = inst_rd_D;

  // csrr and csrw logic

  always_comb begin
    proc2mngr_val_D  = 1'b0;
    mngr2proc_rdy_D  = 1'b0;
    csrr_sel_D       = 2'h0;
    stats_en_wen_D   = 1'b0;

    if ( csrw_D && inst_csr_D == `TINYRV2_CPR_PROC2MNGR )
      proc2mngr_val_D  = 1'b1;
    if ( csrr_D && inst_csr_D == `TINYRV2_CPR_MNGR2PROC )
      mngr2proc_rdy_D  = 1'b1;
    if ( csrw_D && inst_csr_D == `TINYRV2_CPR_STATS_EN )
      stats_en_wen_D   = 1'b1;
    if ( csrr_D && inst_csr_D == `TINYRV2_CPR_NUMCORES )
      csrr_sel_D       = 2'h1;
    if ( csrr_D && inst_csr_D == `TINYRV2_CPR_COREID )
      csrr_sel_D       = 2'h2;
  end

  // mngr2proc_rdy signal for csrr instruction

  assign mngr2proc_rdy = val_D && !stall_D && mngr2proc_rdy_D;

  logic  ostall_mngr2proc_D;
  assign ostall_mngr2proc_D = val_D && mngr2proc_rdy_D && !mngr2proc_val;

  // X->D bypass logic rs1
  logic bypass_waddr_X_rs1_D;
  assign bypass_waddr_X_rs1_D
    = rs1_en_D && val_X && rf_wen_X
      && ( inst_rs1_D == rf_waddr_X ) && ( rf_waddr_X != 5'd0 );

  // load-use hazard cant bypass must stall
  logic ostall_load_use_rs1_D;
  assign ostall_load_use_rs1_D
    = rs1_en_D && val_X && rf_wen_X && ( dmem_type_X == ld )
      && ( inst_rs1_D == rf_waddr_X ) && ( rf_waddr_X != 5'd0 );

  // M->D bypass logic rs1
  logic bypass_waddr_M_rs1_D;
  assign bypass_waddr_M_rs1_D
    = rs1_en_D && val_M && rf_wen_M
      && ( inst_rs1_D == rf_waddr_M ) && ( rf_waddr_M != 5'd0 );

  // W->D bypass logic rs1
  logic bypass_waddr_W_rs1_D;
  assign bypass_waddr_W_rs1_D 
    = rs1_en_D && val_W && rf_wen_W
      && ( inst_rs1_D == rf_waddr_W ) && ( rf_waddr_W != 5'd0 );

  // X->D bypass logic rs2
  logic bypass_waddr_X_rs2_D;
  assign bypass_waddr_X_rs2_D
    = rs2_en_D && val_X && rf_wen_X
      && ( inst_rs2_D == rf_waddr_X ) && ( rf_waddr_X != 5'd0 );

  // load-use hazard cant bypass must stall
  logic ostall_load_use_rs2_D;
  assign ostall_load_use_rs2_D
    = rs2_en_D && val_X && rf_wen_X && ( dmem_type_X == ld )
      && ( inst_rs2_D == rf_waddr_X ) && ( rf_waddr_X != 5'd0 );

  // M->D bypass logic rs2
  logic bypass_waddr_M_rs2_D;
  assign bypass_waddr_M_rs2_D
    = rs2_en_D && val_M && rf_wen_M
      && ( inst_rs2_D == rf_waddr_M ) && ( rf_waddr_M != 5'd0 );

  // W->D bypass logic
  logic bypass_waddr_W_rs2_D;
  assign bypass_waddr_W_rs2_D
    = rs2_en_D && val_W && rf_wen_W
      && ( inst_rs2_D == rf_waddr_W ) && ( rf_waddr_W != 5'd0 );

  // Final ostall signal

  logic oimul_stall_D;
  assign oimul_stall_D = is_mul_D && !imul_req_rdy_D;

  assign ostall_D = val_D && ( ostall_mngr2proc_D ||  oimul_stall_D || ostall_load_use_rs1_D || ostall_load_use_rs2_D ) ; // removed hazard stall 

  // osquash due to jump or predicted-taken branch in D stage

  assign osquash_D = val_D && !stall_D
                  && ( (br_type_D == br_j) || (is_cond_br_D && bht_pred_taken_D) );

  // stall and squash in D

  assign stall_D  = val_D && ( ostall_D || ostall_X || ostall_M || ostall_W );
  assign squash_D = val_D && osquash_X;

  // imul control
  assign imul_req_val_D = val_D && is_mul_D && !stall_D && !squash_D;

  // Valid signal for the next stage

  logic  next_val_D;
  assign next_val_D = val_D && !stall_D && !squash_D;

  always_comb begin

    // rs1
    if ( bypass_waddr_X_rs1_D ) begin
      op1_sel_D = am_bypass_X; // X->D bypass
    end
    else if ( bypass_waddr_M_rs1_D ) begin
      op1_sel_D = am_bypass_M; // M->D bypass
    end
    else if ( bypass_waddr_W_rs1_D ) begin
      op1_sel_D = am_bypass_W; // W->D bypass
    end
    else begin
      op1_sel_D = op1_sel_default_D;
    end

    // rs2
    if ( bypass_waddr_X_rs2_D && ( op2_sel_default_D == bm_rf ) ) begin
      op2_sel_D = bm_bypass_X; // X->D bypass
    end
    else if ( bypass_waddr_M_rs2_D && ( op2_sel_default_D == bm_rf ) ) begin
      op2_sel_D = bm_bypass_M; // M->D bypass
    end
    else if ( bypass_waddr_W_rs2_D && ( op2_sel_default_D == bm_rf ) ) begin
      op2_sel_D = bm_bypass_W; // W->D bypass
    end
    else begin
      op2_sel_D = op2_sel_default_D;
    end
  end
  
  // always block for sw hazard
  always_comb begin 
    if      ( bypass_waddr_X_rs2_D ) sw_data_sel_D = 2'd1; // X->D bypass
    else if ( bypass_waddr_M_rs2_D ) sw_data_sel_D = 2'd2; // M->D bypass
    else if ( bypass_waddr_W_rs2_D ) sw_data_sel_D = 2'd3; // W->D bypass
    else                             sw_data_sel_D = 2'd0; // no bypass 
  end

  //----------------------------------------------------------------------
  // X stage
  //----------------------------------------------------------------------

  // Register enable logic

  assign reg_en_X = !stall_X;

  logic [31:0] inst_X;
  //logic [1:0]  dmem_type_X; // decleration moved to port list
  logic        wb_result_sel_X;
  logic        rf_wen_X;
  logic [4:0]  rf_waddr_X;
  logic        proc2mngr_val_X;
  logic        stats_en_wen_X;
  logic [2:0]  br_type_X;
  logic        pred_taken_X;
  logic        is_mul_X;

  // Pipeline registers

  always_ff @( posedge clk )
    if ( reset ) begin
      val_X                 <= 1'b0;
    end
    else if ( reg_en_X ) begin
      val_X           <= next_val_D;
      rf_wen_X        <= rf_wen_D;
      inst_X          <= inst_D;
      alu_fn_X        <= alu_fn_D;
      rf_waddr_X      <= rf_waddr_D;
      proc2mngr_val_X <= proc2mngr_val_D;
      dmem_type_X     <= dmem_type_D;
      wb_result_sel_X <= wb_result_sel_D;
      stats_en_wen_X  <= stats_en_wen_D;
      br_type_X       <= br_type_D;
      pred_taken_X    <= bht_pred_taken_D;
      is_mul_X        <= is_mul_D;
      ex_result_sel_X <= ex_result_sel_D;
    end

  // branch logic, redirect PC in F on a mispredicted branch or a jalr

  logic is_cond_br_X;
  logic taken_X;

  always_comb begin
    is_cond_br_X = 1'b1;
    case ( br_type_X )
      br_bne:  taken_X = !br_cond_eq_X;
      br_beq:  taken_X =  br_cond_eq_X;
      br_lt:   taken_X =  br_cond_lt_X;
      br_ltu:  taken_X =  br_cond_ltu_X;
      default: begin
        taken_X      = 1'b0;
        is_cond_br_X = 1'b0;
      end
    endcase
  end

  always_comb begin
    if ( val_X && is_cond_br_X ) begin
      pc_redirect_X = ( taken_X != pred_taken_X );
      pc_sel_X      = taken_X ? 3'd1 : 3'd4; // br_target_X : pc_plus4_X
    end
    else if ( val_X && ( br_type_X == br_jalr ) ) begin
      pc_redirect_X = 1'b1;
      pc_sel_X      = 3'd3;
    end
    else begin
      pc_redirect_X = 1'b0;
      pc_sel_X      = 3'b0;
    end
  end

  // train the BHT once per resolved branch

  assign bht_update_en_X    = val_X && is_cond_br_X && !stall_X;
  assign bht_update_taken_X = taken_X;

  // ostall due to dmem_reqstream not ready.
  logic oimul_stall_X;
  assign oimul_stall_X = is_mul_X && !imul_resp_val_X; 

  logic odmem_stall_X;
  assign odmem_stall_X = (dmem_type_X != nr) && !dmem_reqstream_rdy;

  assign ostall_X = val_X && (odmem_stall_X || oimul_stall_X);

  // osquash due to taken branch, notice we can't osquash if current
  // stage stalls, otherwise we will send osquash twice.

  assign osquash_X = val_X && !stall_X && pc_redirect_X;

  // mul control signals
  assign imul_resp_rdy_X = val_X && is_mul_X && !stall_X;

  // stall and squash used in X stage

  assign stall_X = val_X && ( ostall_X || ostall_M || ostall_W );

  // set dmem_reqstream_val only if not stalling

  assign dmem_reqstream_val = val_X && !stall_X && ( dmem_type_X != nr );

  // Valid signal for the next stage

  logic  next_val_X;
  assign next_val_X = val_X && !stall_X;

  //----------------------------------------------------------------------
  // M stage
  //----------------------------------------------------------------------

  // Register enable logic

  assign reg_en_M  = !stall_M;

  logic [31:0] inst_M;
  logic [1:0]  dmem_type_M;
  logic        rf_wen_M;
  logic [4:0]  rf_waddr_M;
  logic        proc2mngr_val_M;
  logic        stats_en_wen_M;

  // Pipeline register

  always_ff @( posedge clk )
    if ( reset ) begin
      val_M                 <= 1'b0;
    end
    else if ( reg_en_M ) begin
      val_M           <= next_val_X;
      rf_wen_M        <= rf_wen_X;
      inst_M          <= inst_X;
      rf_waddr_M      <= rf_waddr_X;
      proc2mngr_val_M <= proc2mngr_val_X;
      dmem_type_M     <= dmem_type_X;
      wb_result_sel_M <= wb_result_sel_X;
      stats_en_wen_M  <= stats_en_wen_X;
    end

  // ostall due to dmem_respstream not valid

  assign ostall_M = val_M && ( dmem_type_M != nr ) && !dmem_respstream_val;

  // stall M

  assign stall_M = val_M && ( ostall_M || ostall_W );

  // Set dmem_respstream_rdy if valid and not stalling and this is a lw/sw

  assign dmem_respstream_rdy = val_M && !stall_M && ( dmem_type_M != nr );

  // Valid signal for the next stage

  logic  next_val_M;
  assign next_val_M = val_M && !stall_M;

  //----------------------------------------------------------------------
  // W stage
  //----------------------------------------------------------------------

  // Register enable logic

  assign reg_en_W = !stall_W;

  logic [31:0] inst_W;
  logic        proc2mngr_val_W;
  logic        rf_wen_pending_W;
  logic        stats_en_wen_pending_W;

  // Pipeline registers

  always_ff @( posedge clk ) begin
    if ( reset ) begin
      val_W                  <= 1'b0;
    end
    else if ( reg_en_W ) begin
      val_W                  <= next_val_M;
      rf_wen_pending_W       <= rf_wen_M;
      inst_W                 <= inst_M;
      rf_waddr_W             <= rf_waddr_M;
      proc2mngr_val_W        <= proc2mngr_val_M;
      stats_en_wen_pending_W <= stats_en_wen_M;
    end
  end

  // write enable

  assign rf_wen_W       = val_W && rf_wen_pending_W;
  assign stats_en_wen_W = val_W && stats_en_wen_pending_W;

  // ostall due to proc2mngr

  assign ostall_W = val_W && proc2mngr_val_W && !proc2mngr_rdy;

  // stall and squash signal used in W stage

  assign stall_W = val_W && ostall_W;

  // proc2mngr port

  assign proc2mngr_val = val_W && !stall_W && proc2mngr_val_W;

  assign commit_inst = val_W && !stall_W;

endmodule

`endif /* PROC_PROC_BHT_CTRL_V */
