/***************************************************************
* Copyright (c) 2022 Hariesh Anbalagan
* This code is licensed under MIT license (see LICENSE.txt for details)
* 
* Module: ProcessorCore.sv
*
* Description:
*
* This does contains to processor core datapath.
* (Load and store are yet to developed fully)
***************************************************************/
import risc_v_32_i_pkg::*;

module ProcessorCore
(
    input logic             clk_i,
    input logic             reset_i,

    output logic [31:0]     instruction_address_o,
     input logic [31:0]     instruction_data_i,

     input logic [31:0]     read_data_i,
    output logic            write_enable_o,
    output logic [31:0]     write_data_o,
    output logic [3:0]      write_data_strobe_o,
    output logic [31:0]     address_o
);
    logic [31:0]PC;
    logic [31:0]pc_next,pc_update;

    logic [31:0] instruction;

    logic [31:0]immediate;
    logic [31:0]reg_source_1;
    logic [31:0]reg_source_2;

    logic [31:0]alu_port_a;
    logic [31:0]alu_port_b;
    logic [31:0]comp_port_a;
    logic [31:0]comp_port_b;

    logic [31:0]alu_output;
    logic branch_enable;

    logic [31:0]read_data_aligned;
    logic [31:0]write_data_unaligned;
    load_store_type_e load_store_type;

    logic [31:0]dmem_data;

    logic pc_mux_sel;
    logic reg_write_enable;
    imm_select_e imm_select;
    logic execute_port_a_sel;
    logic execute_port_b_sel;
    alu_select_e alu_op_sel;
    comp_select_e comp_op_sel;
    logic data_memory_write_enable;
    write_data_select_e reg_write_data_sel;

    logic [31:0]reg_data;

    assign pc_next = PC + 32'd4;
    assign pc_update = pc_mux_sel ? alu_output : pc_next;

    always_ff @(posedge clk_i, posedge reset_i)
    begin
        if (reset_i)
        begin
            PC <= 32'd0;
        end
        else
        begin
            PC <= pc_update;
        end
    end

    assign instruction_address_o = PC;
    assign instruction = instruction_data_i;

    RegisterFile #(.XLEN(XLEN), .REG_ADDR_WIDTH(REG_ADDR_WIDTH)) regfile
    (
        .read_data_1_o      (reg_source_1),
        .read_data_2_o      (reg_source_2),
        .clk_i              (clk_i),
        .write_enable_i     (reg_write_enable),
        .write_data_i       (reg_data),
        .write_address_i    (instruction[11:7]),
        .read_address_1_i   (instruction[19:15]),
        .read_address_2_i   (instruction[24:20])
    );

    ImmediateSignExtend #(.XLEN(XLEN)) ise
    (
        .imm_o      (immediate),
        .imm_i      (instruction[31:7]),
        .imm_sel_i  (imm_select)
    );

    CoreControlUnit ccu
    (
        .pc_mux_sel_o                     (pc_mux_sel),
        .reg_write_enable_o               (reg_write_enable),
        .imm_select_o                     (imm_select),
        .execute_port_a_sel_o             (execute_port_a_sel),
        .execute_port_b_sel_o             (execute_port_b_sel),
        .alu_op_sel_o                     (alu_op_sel),
        .comp_op_sel_o                    (comp_op_sel),
        .load_store_type_o                (load_store_type),
        .data_memory_write_enable_o       (data_memory_write_enable),
        .reg_write_data_sel_o             (reg_write_data_sel),
        .op_code_i                        (instruction[6:0]),
        .funct3_i                         (instruction[14:12]),
        .funct7_bit5_i                    (instruction[30]),
        .branch_enable_i                  (branch_enable)
    );

    assign alu_port_a = execute_port_a_sel ? reg_source_1 : PC;
    assign alu_port_b = execute_port_b_sel ? reg_source_2 : immediate;
    assign comp_port_a = reg_source_1;
    assign comp_port_b = execute_port_b_sel ? immediate : reg_source_2;

    ArithmeticLogicUnit #(.XLEN(XLEN), .REG_ADDR_WIDTH(REG_ADDR_WIDTH)) alu
    (
        .alu_o          (alu_output),
        .alu_port_a_i   (alu_port_a),
        .alu_port_b_i   (alu_port_b),
        .alu_op_sel_i   (alu_op_sel)
    );

    ComparatorUnit #(.XLEN(XLEN)) bcu
    (
        .branch_o         (branch_enable),
        .comp_port_a_i    (comp_port_a),
        .comp_port_b_i    (comp_port_b),
        .comp_op_sel_i    (comp_op_sel)
    );

    LoadAndStoreUnit #(.XLEN(XLEN)) lsu
    (
        .read_data_o         (read_data_aligned),
        .read_data_i         (read_data_i),
        .write_data_o        (write_data_o),
        .write_data_i        (write_data_unaligned),
        .load_store_type_i   (load_store_type),
        .write_data_strobe_o (write_data_strobe_o)
    );

    assign address_o = alu_output;
    assign dmem_data = read_data_aligned;
    assign write_enable_o = data_memory_write_enable;
    assign write_data_unaligned = reg_source_2;

    always_comb
    begin
        unique case(reg_write_data_sel)
            RD_MUX_DMEM:    reg_data = dmem_data;
             RD_MUX_ALU:    reg_data = alu_output;
             RD_MUX_BCU:    reg_data = {31'b0, branch_enable};
             RD_MUX_IMM:    reg_data = immediate;
            RD_MUX_PC_N:    reg_data = pc_next;
                default:    reg_data = {XLEN{1'bz}};
        endcase
    end

endmodule
