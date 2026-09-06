/***************************************************************************
* Module: InstructionMemory.sv
*
* Description:
*
* Temporiraly adaed module to test the instruction memory.
***************************************************************************/

module InstructionMemory
(
    output logic [31:0]   instruction_data_o,
    input  logic [31:0]   instruction_address_i
);

    logic [31:0]instruction [63:0];
    string test_name;
    string instruction_file;

    initial
    begin
        if (!$value$plusargs("TEST=%s", test_name))
            test_name = "L_S_type";
        instruction_file = {test_name, ".txt"};
        $display("InstructionMemory: loading %s", instruction_file);
        $readmemh(instruction_file, instruction);
    end

    always_comb
    begin
        assign instruction_data_o = instruction[instruction_address_i[31:2]];
    end

endmodule