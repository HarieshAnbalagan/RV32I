/***************************************************************************
* Copyright (c) 2022 Hariesh Anbalagan
* This code is licensed under MIT license (see LICENSE.txt for details)
* 
* Module: ImmediateSignExtend.sv
*
* Description:
*
* This sign extends the immediate value from instructions, not applicable
* for R-type instruction as it uses data from RegistreFile instead.
***************************************************************************/
import risc_v_32_i_pkg::*;

module ImmediateSignExtend #(parameter XLEN = 32)
(
    output logic        [XLEN-1:0]  imm_o,
    input  logic        [XLEN-1:7]  imm_i,
    input  imm_select_e             imm_sel_i
);

    always_comb
    begin
        unique case(imm_sel_i)
            IMM_B_TYPE: imm_o = $signed({imm_i[31], imm_i[7], imm_i[30:25], imm_i[11:8], 1'b0});
            IMM_S_TYPE: imm_o = $signed({imm_i[31:25], imm_i[11:7]});
            IMM_U_TYPE: imm_o = {imm_i[31:12], 12'b0};
            IMM_I_TYPE: imm_o = $signed({imm_i[31:20]});
            IMM_J_TYPE: imm_o = $signed({imm_i[31], imm_i[19:12], imm_i[20], imm_i[30:21], 1'b0});
            IMM_UNKNOWN_TYPE: imm_o = 0;
        endcase
    end

endmodule
