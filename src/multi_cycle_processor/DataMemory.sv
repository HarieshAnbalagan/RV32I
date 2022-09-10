/***************************************************************************
* Copyright (c) 2022 Hariesh Anbalagan
* This code is licensed under MIT license (see LICENSE.txt for details)
* 
* Module: DataMemory.sv
*
* Description:
*
* Temporiraly added module to test the data memory.
***************************************************************************/

module DataMemory
(
    output logic [31:0]     read_data_o,
    input  logic            clk_i,
    input  logic            write_enable_i,
    input  logic [31:0]     write_data_i,
    input  logic [31:0]     address_i
);
    logic [31:0]data [63:0];

    initial
    begin
        $readmemh("Data_Memory_Load.txt",data);
    end

    always_comb
    begin
        assign read_data_o = data[address_i[31:0]];
    end

    always_ff @(posedge clk_i)
    begin
        if (write_enable_i == 1)
        begin
            data[address_i[31:0]] <= write_data_i;
        end
    end

endmodule
