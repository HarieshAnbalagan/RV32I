/***************************************************************************
* Copyright (c) 2022 Hariesh Anbalagan
* This code is licensed under MIT license (see LICENSE.txt for details)
* 
* Module: LoadAndStoreUnit.sv
*
* Description:
*
* This module handles the load and store opertaion between processor
* and memeory elements. This is not complete yet to be developed fully.
***************************************************************************/
import risc_v_32_i_pkg::*;

module LoadAndStoreUnit #(parameter XLEN = 32)
(
    output logic [XLEN-1:0]     read_data_o,
    input  logic [XLEN-1:0]     read_data_i,
    output logic [XLEN-1:0]     write_data_o,
    input  logic [XLEN-1:0]     write_data_i,
    input load_store_type_e     load_store_type_i,
    output logic [3:0]          write_data_strobe_o
);

    always_comb
    begin
        unique case(load_store_type_i)
               L_B: read_data_o =               $signed(read_data_i[(XLEN/4)-1:0]);
              L_BU: read_data_o = {{((3*XLEN)/4){1'b0}},read_data_i[(XLEN/4)-1:0]};
               L_H: read_data_o =               $signed(read_data_i[(XLEN/2)-1:0]);
              L_HU: read_data_o = {{(( XLEN /2)){1'b0}},read_data_i[(XLEN/2)-1:0]};
               L_W: read_data_o =                       read_data_i[XLEN-1:0];
           default: read_data_o =                       read_data_i[XLEN-1:0];
        endcase
    end

    always_comb
    begin
        unique case(load_store_type_i)
               S_B:
                   begin
                   write_data_o = {{((3*XLEN)/4){1'b0}},write_data_i[(XLEN/4)-1:0]};
                   write_data_strobe_o = 4'b0001;
                   end
               S_H:
                   begin
                   write_data_o = {{(( XLEN /2)){1'b0}},write_data_i[(XLEN/2)-1:0]};
                   write_data_strobe_o = 4'b0011;
                   end
               S_W:
                   begin
                   write_data_o = write_data_i[XLEN-1:0];
                   write_data_strobe_o = 4'b1111;
                   end
           default:
                   begin
                   write_data_o = write_data_i[XLEN-1:0];
                   write_data_strobe_o = 4'b0000;
                   end
        endcase
    end

endmodule
