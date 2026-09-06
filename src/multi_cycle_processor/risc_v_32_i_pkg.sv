/***************************************************************************
* Copyright (c) 2022 Hariesh Anbalagan
* This code is licensed under MIT license (see LICENSE.txt for details)
* 
* Package: risc_v_32_i_pkg.sv
*
* Description:
*
* Contains the parameters and enums required.
***************************************************************************/
package risc_v_32_i_pkg;

parameter XLEN = 32;
parameter ADDR_WIDTH = 32;
parameter REG_ADDR_WIDTH = 5;

localparam logic [6:0] OP_B_TYPE       = 7'b1100011;
localparam logic [6:0] OP_I_JALR_TYPE  = 7'b1100111;
localparam logic [6:0] OP_I_LOAD_TYPE  = 7'b0000011;
localparam logic [6:0] OP_I_ALU_TYPE   = 7'b0010011;
localparam logic [6:0] OP_S_TYPE       = 7'b0100011;
localparam logic [6:0] OP_U_LUI_TYPE   = 7'b0110111;
localparam logic [6:0] OP_U_AUIPC_TYPE = 7'b0010111;
localparam logic [6:0] OP_J_TYPE       = 7'b1101111;
localparam logic [6:0] OP_R_TYPE       = 7'b0110011;

parameter IMM_SEL_LEN = 3;

typedef enum logic[IMM_SEL_LEN-1:0] {
    IMM_B_TYPE,
    IMM_S_TYPE,
    IMM_U_TYPE,
    IMM_I_TYPE,
    IMM_J_TYPE,
    IMM_UNKNOWN_TYPE
} imm_select_e;

parameter ALU_SEL_LEN = 4;

typedef enum logic [ALU_SEL_LEN-1:0] {
    OP_ADD,
    OP_SUB,
    OP_AND,
    OP_OR,
    OP_XOR,
    OP_SLL,
    OP_SRL,
    OP_SRA,
    OP_UNKNOWN
} alu_select_e;

parameter COMP_SEL_LEN = 3;

typedef enum logic [COMP_SEL_LEN-1:0] {
    OP_BEQ,
    OP_BNE,
    OP_BLT,
    OP_BGE,
    OP_BLTU,
    OP_BGEU,
    OP_BUNKNOWN
} comp_select_e;

parameter RD_MUX_SEL_LEN = 3;

typedef enum logic [RD_MUX_SEL_LEN-1:0] {
    RD_MUX_DMEM,
    RD_MUX_ALU,
    RD_MUX_BCU,
    RD_MUX_IMM,
    RD_MUX_PC_N,
    RD_MUX_N_A
}write_data_select_e;

parameter LOAD_STORE_TYPE_LEN = 4;

typedef enum logic [LOAD_STORE_TYPE_LEN-1:0]
{
    L_W,
    L_H,
    L_HU,
    L_B,
    L_BU,
    S_W,
    S_H,
    S_B,
    LS_N_A
}load_store_type_e;

endpackage
