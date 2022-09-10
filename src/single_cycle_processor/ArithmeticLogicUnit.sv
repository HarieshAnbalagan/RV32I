/***************************************************************************
* Copyright (c) 2022 Hariesh Anbalagan
* This code is licensed under MIT license (see LICENSE.txt for details)
* 
* Module: ArithmeticLogicUnit.sv
*
* Description:
*
* This does computation over the data related to arithmetic and logic
* instructions. This does not holds the comparison which is done by
* ComparatorUnit.
***************************************************************************/
import risc_v_32_i_pkg::*;

module ArithmeticLogicUnit #(parameter XLEN = 32, parameter REG_ADDR_WIDTH = 5)
(
    output logic        [XLEN-1:0]  alu_o,
    input  logic        [XLEN-1:0]  alu_port_a_i,
    input  logic        [XLEN-1:0]  alu_port_b_i,
    input  alu_select_e             alu_op_sel_i
);

    always_comb
    begin
        unique case(alu_op_sel_i)
            OP_ADD:     alu_o =         alu_port_a_i  +   alu_port_b_i;
            OP_SUB:     alu_o =         alu_port_a_i  -   alu_port_b_i;
            OP_AND:     alu_o =         alu_port_a_i  &   alu_port_b_i;
             OP_OR:     alu_o =         alu_port_a_i  |   alu_port_b_i;
            OP_XOR:     alu_o =         alu_port_a_i  ^   alu_port_b_i;
            OP_SLL:     alu_o =         alu_port_a_i  <<  alu_port_b_i[REG_ADDR_WIDTH-1:0];
            OP_SRL:     alu_o =         alu_port_a_i  >>  alu_port_b_i[REG_ADDR_WIDTH-1:0];
            OP_SRA:     alu_o = $signed(alu_port_a_i) >>> alu_port_b_i[REG_ADDR_WIDTH-1:0];
        OP_UNKNOWN:     alu_o = {XLEN{1'b0}};
        endcase
    end

endmodule
