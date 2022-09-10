/***************************************************************************
* Copyright (c) 2022 Hariesh Anbalagan
* This code is licensed under MIT license (see LICENSE.txt for details)
* 
* Module: ComparatorUnit.sv
*
* Description:
*
* This does computation over the data related to comparison operations.
* The final output is a singe bit. This is kept seperatly from ALU such that
* ALU does addition and this unit does comparision at same time to avoid 
* seperate adder for branch operation.
***************************************************************************/
import risc_v_32_i_pkg::*;

module ComparatorUnit #(parameter XLEN = 32)
(
    output logic                        comp_o,
    input  logic           [XLEN-1:0]   comp_port_a_i,
    input  logic           [XLEN-1:0]   comp_port_b_i,
    input  comp_select_e                comp_op_sel_i
);

    always_comb
    begin
        unique case(comp_op_sel_i)
            OP_BEQ:     comp_o =         comp_port_a_i  ==  comp_port_b_i;
            OP_BNE:     comp_o =         comp_port_a_i  !=  comp_port_b_i;
           OP_BLTU:     comp_o =         comp_port_a_i  <   comp_port_b_i;
           OP_BGEU:     comp_o =         comp_port_a_i  >=  comp_port_b_i;
            OP_BLT:     comp_o = $signed(comp_port_a_i) <   $signed(comp_port_b_i);
            OP_BGE:     comp_o = $signed(comp_port_a_i) >=  $signed(comp_port_b_i);
       OP_BUNKNOWN:     comp_o = 1'b0;
          default:      comp_o = 1'b0;
        endcase
    end
endmodule
