/***************************************************************************
* Copyright (c) 2022 Hariesh Anbalagan
* This code is licensed under MIT license (see LICENSE.txt for details)
* 
* Module: CoreControlUnit.sv
*
* Description:
*
* This does control of the processor core datapath. This does not cover
* the pipeline control which is hanleded by PipelineControlUnit.
***************************************************************************/
import risc_v_32_i_pkg::*;

module CoreControlUnit #(parameter XLEN = 32)
(
    output logic [1:0]              pc_mux_sel_o,
    output logic                    reg_write_enable_o,
    output imm_select_e             imm_select_o,
    output logic                    execute_port_a_sel_o,
    output logic                    execute_port_b_sel_o,
    output alu_select_e             alu_op_sel_o,
    output comp_select_e            comp_op_sel_o,
    output load_store_type_e        load_store_type_o,
    output logic                    data_memory_write_enable_o,
    output write_data_select_e      reg_write_data_sel_o,
    input logic [6:0]               op_code_i,
    input logic [2:0]               funct3_i,
    input logic                     funct7_bit5_i
);

    localparam OP_R_TYPE        = 7'b0110011;
    localparam OP_B_TYPE        = 7'b1100011;
    localparam OP_S_TYPE        = 7'b0100011;
    localparam OP_I_JALR_TYPE   = 7'b1100111;
    localparam OP_I_LOAD_TYPE   = 7'b0000011;
    localparam OP_I_ALU_TYPE    = 7'b0010011;
    localparam OP_I_FENCE_TYPE  = 7'b0001111;
    localparam OP_I_ECALL_TYPE  = 7'b1110011;
    localparam OP_U_LUI_TYPE    = 7'b0110111;
    localparam OP_U_AUIPC_TYPE  = 7'b0010111;
    localparam OP_J_TYPE        = 7'b1101111;

    always_comb
    begin

        unique case(op_code_i)
            OP_R_TYPE:
            begin
                pc_mux_sel_o = 2'b00;
                reg_write_enable_o = 1'b1;
                imm_select_o = IMM_UNKNOWN_TYPE;
                execute_port_a_sel_o = 1'b1;

                unique case({funct7_bit5_i,funct3_i})
                    4'b0000:
                            begin
                            alu_op_sel_o = OP_ADD;
                            comp_op_sel_o = OP_BUNKNOWN;
                            execute_port_b_sel_o = 1'b1;
                            reg_write_data_sel_o = RD_MUX_ALU;
                            end
                    4'b1000:
                            begin
                            alu_op_sel_o = OP_SUB;
                            comp_op_sel_o = OP_BUNKNOWN;
                            execute_port_b_sel_o = 1'b1;
                            reg_write_data_sel_o = RD_MUX_ALU;
                            end
                    4'b0001:
                            begin
                            alu_op_sel_o = OP_SLL;
                            comp_op_sel_o = OP_BUNKNOWN;
                            execute_port_b_sel_o = 1'b1;
                            reg_write_data_sel_o = RD_MUX_ALU;
                            end
                    4'b0010:
                            begin
                            alu_op_sel_o = OP_UNKNOWN;
                            comp_op_sel_o = OP_BLT;
                            execute_port_b_sel_o = 1'b0;
                            reg_write_data_sel_o = RD_MUX_BCU;
                            end
                    4'b0011:
                            begin
                            alu_op_sel_o = OP_UNKNOWN;
                            comp_op_sel_o = OP_BLTU;
                            execute_port_b_sel_o = 1'b0;
                            reg_write_data_sel_o = RD_MUX_BCU;
                            end
                    4'b0100:
                            begin
                            alu_op_sel_o = OP_XOR;
                            comp_op_sel_o = OP_BUNKNOWN;
                            execute_port_b_sel_o = 1'b1;
                            reg_write_data_sel_o = RD_MUX_ALU;
                            end
                    4'b0101:
                            begin
                            alu_op_sel_o = OP_SRL;
                            comp_op_sel_o = OP_BUNKNOWN;
                            execute_port_b_sel_o = 1'b1;
                            reg_write_data_sel_o = RD_MUX_ALU;
                            end
                    4'b1101:
                            begin
                            alu_op_sel_o = OP_SRA;
                            comp_op_sel_o = OP_BUNKNOWN;
                            execute_port_b_sel_o = 1'b1;
                            reg_write_data_sel_o = RD_MUX_ALU;
                            end
                    4'b0110:
                            begin
                            alu_op_sel_o = OP_OR;
                            comp_op_sel_o = OP_BUNKNOWN;
                            execute_port_b_sel_o = 1'b1;
                            reg_write_data_sel_o = RD_MUX_ALU;
                            end
                    4'b0111:
                            begin
                            alu_op_sel_o = OP_AND;
                            comp_op_sel_o = OP_BUNKNOWN;
                            execute_port_b_sel_o = 1'b1;
                            reg_write_data_sel_o = RD_MUX_ALU;
                            end
                    default:
                            begin
                            alu_op_sel_o = OP_UNKNOWN;
                            comp_op_sel_o = OP_BUNKNOWN;
                            execute_port_b_sel_o = 1'b1;
                            reg_write_data_sel_o = RD_MUX_ALU;
                            end
                endcase

                load_store_type_o = LS_N_A;
                data_memory_write_enable_o = 1'b0;
            end
            OP_B_TYPE:
            begin
                pc_mux_sel_o = 2'b10;
                reg_write_enable_o = 1'b0;
                imm_select_o = IMM_B_TYPE;
                execute_port_a_sel_o = 1'b0;
                execute_port_b_sel_o = 1'b0;
                alu_op_sel_o = OP_ADD;

                unique case(funct3_i)
                    3'b000: comp_op_sel_o = OP_BEQ;
                    3'b001: comp_op_sel_o = OP_BNE;
                    3'b100: comp_op_sel_o = OP_BLT;
                    3'b101: comp_op_sel_o = OP_BGE;
                    3'b110: comp_op_sel_o = OP_BLTU;
                    3'b111: comp_op_sel_o = OP_BGEU;
                   default: comp_op_sel_o = OP_BUNKNOWN;
                endcase

                load_store_type_o = LS_N_A;
                data_memory_write_enable_o = 1'b0;
                reg_write_data_sel_o = RD_MUX_N_A;
            end
            OP_S_TYPE:
            begin
                pc_mux_sel_o = 2'b00;
                reg_write_enable_o = 1'b0;
                imm_select_o = IMM_S_TYPE;
                execute_port_a_sel_o = 1'b1;
                execute_port_b_sel_o = 1'b0;
                alu_op_sel_o = OP_ADD;
                comp_op_sel_o = OP_BUNKNOWN;

                unique case(funct3_i)
                    3'b000:  load_store_type_o = S_B;
                    3'b001:  load_store_type_o = S_H;
                    3'b010:  load_store_type_o = S_W;
                endcase

                data_memory_write_enable_o = 1'b1;
                reg_write_data_sel_o = RD_MUX_N_A;
            end
            OP_I_JALR_TYPE:
            begin
                pc_mux_sel_o = 2'b01;
                reg_write_enable_o = 1'b1;
                imm_select_o = IMM_I_TYPE;
                execute_port_a_sel_o = 1'b1;
                execute_port_b_sel_o = 1'b0;
                alu_op_sel_o = OP_ADD;
                comp_op_sel_o = OP_BUNKNOWN;
                load_store_type_o = LS_N_A;
                data_memory_write_enable_o = 1'b0;
                reg_write_data_sel_o = RD_MUX_PC_N;
            end
            OP_I_LOAD_TYPE:
            begin
                pc_mux_sel_o = 2'b00;
                reg_write_enable_o = 1'b1;
                imm_select_o = IMM_I_TYPE;
                execute_port_a_sel_o = 1'b1;
                execute_port_b_sel_o = 1'b0;
                alu_op_sel_o = OP_ADD;
                comp_op_sel_o = OP_BUNKNOWN;

                unique case(funct3_i)
                    3'b000:  load_store_type_o = L_B;
                    3'b001:  load_store_type_o = L_H;
                    3'b010:  load_store_type_o = L_W;
                    3'b100:  load_store_type_o = L_BU;
                    3'b101:  load_store_type_o = L_HU;
                    default: load_store_type_o = L_W;
                endcase

                data_memory_write_enable_o = 1'b0;
                reg_write_data_sel_o = RD_MUX_DMEM;
            end
            OP_I_ALU_TYPE:
            begin
                pc_mux_sel_o = 2'b00;
                reg_write_enable_o = 1'b1;
                imm_select_o = IMM_I_TYPE;
                execute_port_a_sel_o = 1'b1;

                unique case(funct3_i)
                    3'b000:
                           begin
                           alu_op_sel_o = OP_ADD;
                           comp_op_sel_o = OP_BUNKNOWN;
                           execute_port_b_sel_o = 1'b0;
                           reg_write_data_sel_o = RD_MUX_ALU;
                           end
                    3'b010:
                           begin
                           alu_op_sel_o = OP_UNKNOWN;
                           comp_op_sel_o = OP_BLT;
                           execute_port_b_sel_o = 1'b1;
                           reg_write_data_sel_o = RD_MUX_BCU;
                           end
                    3'b011:
                           begin
                           alu_op_sel_o = OP_UNKNOWN;
                           comp_op_sel_o = OP_BLTU;
                           execute_port_b_sel_o = 1'b1;
                           reg_write_data_sel_o = RD_MUX_BCU;
                           end
                    3'b100:
                           begin
                           alu_op_sel_o = OP_XOR;
                           comp_op_sel_o = OP_BUNKNOWN;
                           execute_port_b_sel_o = 1'b0;
                           reg_write_data_sel_o = RD_MUX_ALU;
                           end
                    3'b110:
                           begin
                           alu_op_sel_o = OP_OR;
                           comp_op_sel_o = OP_BUNKNOWN;
                           execute_port_b_sel_o = 1'b0;
                           reg_write_data_sel_o = RD_MUX_ALU;
                           end
                    3'b111:
                           begin
                           alu_op_sel_o = OP_AND;
                           comp_op_sel_o = OP_BUNKNOWN;
                           execute_port_b_sel_o = 1'b0;
                           reg_write_data_sel_o = RD_MUX_ALU;
                           end
                    3'b001:
                           begin
                           alu_op_sel_o = OP_SLL;
                           comp_op_sel_o = OP_BUNKNOWN;
                           execute_port_b_sel_o = 1'b0;
                           reg_write_data_sel_o = RD_MUX_ALU;
                           end
                    3'b101:
                           begin
                           alu_op_sel_o = ((funct7_bit5_i)? OP_SRA : OP_SRL);
                           comp_op_sel_o = OP_BUNKNOWN;
                           execute_port_b_sel_o = 1'b0;
                           reg_write_data_sel_o = RD_MUX_ALU;
                           end
                   default:
                           begin
                           alu_op_sel_o = OP_UNKNOWN;
                           comp_op_sel_o = OP_BUNKNOWN;
                           execute_port_b_sel_o = 1'b0;
                           reg_write_data_sel_o = RD_MUX_ALU;
                           end
                endcase

                load_store_type_o = LS_N_A;
                data_memory_write_enable_o = 1'b0;
            end
            OP_I_FENCE_TYPE:
            begin
                pc_mux_sel_o = 2'b00;
                reg_write_enable_o = 1'b0;
                imm_select_o = IMM_I_TYPE;
                execute_port_a_sel_o = 1'b1;
                execute_port_b_sel_o = 1'b0;
                alu_op_sel_o = OP_UNKNOWN;
                comp_op_sel_o = OP_BUNKNOWN;
                load_store_type_o = LS_N_A;
                data_memory_write_enable_o = 1'b0;
                reg_write_data_sel_o = RD_MUX_N_A;
            end
            OP_I_ECALL_TYPE:
            begin
                pc_mux_sel_o = 2'b00;
                reg_write_enable_o = 1'b0;
                imm_select_o = IMM_I_TYPE;
                execute_port_a_sel_o = 1'b1;
                execute_port_b_sel_o = 1'b0;
                alu_op_sel_o = OP_UNKNOWN;
                comp_op_sel_o = OP_BUNKNOWN;
                load_store_type_o = LS_N_A;
                data_memory_write_enable_o = 1'b0;
                reg_write_data_sel_o = RD_MUX_N_A;
            end
            OP_U_LUI_TYPE:
            begin
                pc_mux_sel_o = 2'b00;
                reg_write_enable_o = 1'b1;
                imm_select_o = IMM_U_TYPE;
                execute_port_a_sel_o = 1'b0;
                execute_port_b_sel_o = 1'b0;
                alu_op_sel_o = OP_UNKNOWN;
                comp_op_sel_o = OP_BUNKNOWN;
                load_store_type_o = LS_N_A;
                data_memory_write_enable_o = 1'b0;
                reg_write_data_sel_o = RD_MUX_IMM;
            end
            OP_U_AUIPC_TYPE:
            begin
                pc_mux_sel_o = 2'b00;
                reg_write_enable_o = 1'b1;
                imm_select_o = IMM_U_TYPE;
                execute_port_a_sel_o = 1'b0;
                execute_port_b_sel_o = 1'b0;
                alu_op_sel_o = OP_ADD;
                comp_op_sel_o = OP_BUNKNOWN;
                load_store_type_o = LS_N_A;
                data_memory_write_enable_o = 1'b0;
                reg_write_data_sel_o = RD_MUX_ALU;
            end
            OP_J_TYPE:
            begin
                pc_mux_sel_o = 2'b01;
                reg_write_enable_o = 1'b1;
                imm_select_o = IMM_J_TYPE;
                execute_port_a_sel_o = 1'b0;
                execute_port_b_sel_o = 1'b0;
                alu_op_sel_o = OP_ADD;
                comp_op_sel_o = OP_BUNKNOWN;
                load_store_type_o = LS_N_A;
                data_memory_write_enable_o = 1'b0;
                reg_write_data_sel_o = RD_MUX_PC_N;
            end
            default:
            begin
                pc_mux_sel_o = 2'b00;
                reg_write_enable_o = 1'b0;
                imm_select_o = IMM_UNKNOWN_TYPE;
                execute_port_a_sel_o = 1'b0;
                execute_port_b_sel_o = 1'b0;
                alu_op_sel_o = OP_UNKNOWN;
                comp_op_sel_o = OP_BUNKNOWN;
                load_store_type_o = LS_N_A;
                data_memory_write_enable_o = 1'b0;
                reg_write_data_sel_o = RD_MUX_N_A;
            end
        endcase

    end
endmodule
