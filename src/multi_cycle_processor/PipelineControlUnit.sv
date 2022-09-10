/***************************************************************************
* Copyright (c) 2022 Hariesh Anbalagan
* This code is licensed under MIT license (see LICENSE.txt for details)
* 
* Module: PipelineControlUnit.sv
*
* Description:
*
* This does control of the processor pipeline
***************************************************************************/
import risc_v_32_i_pkg::*;

module PipelineControlUnit #(parameter REG_ADDR_WIDTH = 5)
(
    output logic                        stall_pc_if_o,
    output logic                        stall_if_id_o,
    output logic                        clear_if_id_o,
    output logic                        clear_id_ex_o,
    output logic [1:0]                  reg_source_1_data_sel_o,
    output logic [1:0]                  reg_source_2_data_sel_o,
     input logic [REG_ADDR_WIDTH-1:0]   reg_source_1_addr_id_i,
     input logic [REG_ADDR_WIDTH-1:0]   reg_source_2_addr_id_i,
     input logic [REG_ADDR_WIDTH-1:0]   reg_source_1_addr_ex_i,
     input logic [REG_ADDR_WIDTH-1:0]   reg_source_2_addr_ex_i,
     input logic [REG_ADDR_WIDTH-1:0]   reg_destination_addr_ex_i,
     input logic [REG_ADDR_WIDTH-1:0]   reg_destination_addr_dm_i,
     input logic [REG_ADDR_WIDTH-1:0]   reg_destination_addr_wb_i,
     input logic                        reg_write_enable_dm_i,
     input logic                        reg_write_enable_wb_i,
     input write_data_select_e          reg_write_data_sel_ex_i,
     input logic                        branch_enable_i
);

    logic load_stall;

    assign reg_source_1_data_sel_o[0] = ((reg_source_1_addr_ex_i != 32'd0) && (reg_source_1_addr_ex_i == reg_destination_addr_dm_i) && (reg_write_enable_dm_i));
    assign reg_source_1_data_sel_o[1] = ((reg_source_1_addr_ex_i != 32'd0) && (reg_source_1_addr_ex_i == reg_destination_addr_wb_i) && (reg_write_enable_wb_i));
    assign reg_source_2_data_sel_o[0] = ((reg_source_2_addr_ex_i != 32'd0) && (reg_source_2_addr_ex_i == reg_destination_addr_dm_i) && (reg_write_enable_dm_i));
    assign reg_source_2_data_sel_o[1] = ((reg_source_2_addr_ex_i != 32'd0) && (reg_source_2_addr_ex_i == reg_destination_addr_wb_i) && (reg_write_enable_wb_i));
    assign load_stall = ((reg_write_data_sel_ex_i == RD_MUX_DMEM) && ((reg_source_1_addr_id_i == reg_destination_addr_ex_i) || (reg_source_2_addr_id_i == reg_destination_addr_ex_i)));
    assign stall_if_id_o = load_stall;
    assign stall_pc_if_o = load_stall;
    assign clear_if_id_o = branch_enable_i;
    assign clear_id_ex_o = (branch_enable_i | load_stall);

endmodule
