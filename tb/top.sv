/***************************************************************************
* Copyright (c) 2022 Hariesh Anbalagan
* This code is licensed under MIT license (see LICENSE.txt for details)
* 
* Module: top.sv
*
* Description:
*
* Contains the all module instances for testing.
***************************************************************************/
import risc_v_32_i_pkg::*;

module top
(
    input logic clk, reset,
    output logic [31:0] write_data, data_address,
    output logic write_enable
);
    logic [31:0]instruction_address;
    logic [31:0]instruction_data;
    logic [31:0]read_data;
    logic [3:0]write_data_strobe;

    InstructionMemory imem
    (
        .instruction_data_o     (instruction_data),
        .instruction_address_i  (instruction_address)
    );

    ProcessorCore PrCore
    (
        .clk_i                  (clk),
        .reset_i                (reset),

        .instruction_address_o  (instruction_address),
        .instruction_data_i     (instruction_data),

        .read_data_i            (read_data),
        .write_enable_o         (write_enable),
        .write_data_o           (write_data),
        .write_data_strobe_o    (write_data_strobe),
        .address_o              (data_address)
    );

    DataMemory dmem
    (
        .read_data_o    (read_data),
        .clk_i          (clk),
        .write_enable_i (write_enable),
        .write_data_i   (write_data),
        .address_i      (data_address)
    );

endmodule
