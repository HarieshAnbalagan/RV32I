/***************************************************************************
* Copyright (c) 2022 Hariesh Anbalagan
* This code is licensed under MIT license (see LICENSE.txt for details)
* 
* Module: InstructionMemory.sv
*
* Description:
*
* Temporiraly added module to test the instruction memory.
***************************************************************************/

module InstructionMemory
(
    output logic [31:0]   instruction_data_o,
    input  logic [31:0]   instruction_address_i
);

    logic [31:0]instruction [63:0];

    initial
    begin
        $readmemh("L_S_type.txt",instruction); // use the right txt file for testing
    end

    always_comb
    begin
        assign instruction_data_o = instruction[instruction_address_i[31:2]];
    end

endmodule
