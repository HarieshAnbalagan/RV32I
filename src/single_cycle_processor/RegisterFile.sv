/***************************************************************************
* Copyright (c) 2022 Hariesh Anbalagan
* This code is licensed under MIT license (see LICENSE.txt for details)
* 
* Module: RegisterFile.sv
*
* Description:
*
* This holds the architectural register file, which contains the registers
* associated with processor to store data
***************************************************************************/

module RegisterFile #(parameter XLEN = 32, parameter REG_ADDR_WIDTH = 5)
(
    output logic [XLEN-1:0]             read_data_1_o,
    output logic [XLEN-1:0]             read_data_2_o,
    input  logic                        clk_i,
    input  logic                        write_enable_i,
    input  logic [XLEN-1:0]             write_data_i,
    input  logic [REG_ADDR_WIDTH-1:0]   write_address_i,
    input  logic [REG_ADDR_WIDTH-1:0]   read_address_1_i,
    input  logic [REG_ADDR_WIDTH-1:0]   read_address_2_i
);

    logic [XLEN-1:0]register [XLEN-1:0];

    always_comb
    begin
        assign read_data_1_o = (read_address_1_i == 0) ? 0 : register[read_address_1_i];
        assign read_data_2_o = (read_address_2_i == 0) ? 0 : register[read_address_2_i];
    end

    always_ff @(negedge clk_i)
    begin
        if (write_enable_i == 1 && write_address_i != 0)
        begin
            register[write_address_i] <= write_data_i;
        end
    end

endmodule
