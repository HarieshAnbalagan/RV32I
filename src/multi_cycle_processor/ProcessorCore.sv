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

///////////////////////////////////////////////////////////////
//                 INSTRUCTION FETCH SIGNALS                 //
///////////////////////////////////////////////////////////////

    logic [ADDR_WIDTH-1:0]PC_if;
    logic [ADDR_WIDTH-1:0]pc_next_if;
    logic [ADDR_WIDTH-1:0]pc_update_if;
    logic [XLEN-1:0]instruction_if;

///////////////////////////////////////////////////////////////
//                 INSTRUCTION DECODE SIGNALS                //
///////////////////////////////////////////////////////////////

    logic [ADDR_WIDTH-1:0]PC_id;
    logic [ADDR_WIDTH-1:0]pc_next_id;
    logic [XLEN-1:0]instruction_id;
    logic [REG_ADDR_WIDTH-1:0]reg_source_1_addr_id;
    logic [REG_ADDR_WIDTH-1:0]reg_source_2_addr_id;
    logic [REG_ADDR_WIDTH-1:0]reg_destination_addr_id;
    logic [XLEN-1:0]immediate_id;
    logic [XLEN-1:0]reg_source_1_data_id;
    logic [XLEN-1:0]reg_source_2_data_id;
    load_store_type_e load_store_type_id;
    logic [1:0]pc_mux_sel_id;
    logic reg_write_enable_id;
    imm_select_e imm_select_id;
    logic execute_port_a_sel_id;
    logic execute_port_b_sel_id;
    alu_select_e alu_op_sel_id;
    comp_select_e comp_op_sel_id;
    logic data_memory_write_enable_id;
    write_data_select_e reg_write_data_sel_id;

///////////////////////////////////////////////////////////////
//                      EXECUTE SIGNALS                      //
///////////////////////////////////////////////////////////////

    logic [ADDR_WIDTH-1:0]PC_ex;
    logic [ADDR_WIDTH-1:0]pc_next_ex;
    logic [REG_ADDR_WIDTH-1:0]reg_source_1_addr_ex;
    logic [REG_ADDR_WIDTH-1:0]reg_source_2_addr_ex;
    logic [REG_ADDR_WIDTH-1:0]reg_destination_addr_ex;
    logic [XLEN-1:0]immediate_ex;
    logic [XLEN-1:0]reg_source_1_data_ex;
    logic [XLEN-1:0]reg_source_2_data_ex;
    logic [XLEN-1:0]alu_port_a_ex;
    logic [XLEN-1:0]alu_port_b_ex;
    logic [XLEN-1:0]comp_port_a_ex;
    logic [XLEN-1:0]comp_port_b_ex;
    logic [XLEN-1:0]alu_output_ex;
    logic comp_output_ex;
    load_store_type_e load_store_type_ex;
    logic [1:0]pc_mux_sel_ex;
    logic reg_write_enable_ex;
    imm_select_e imm_select_ex;
    logic execute_port_a_sel_ex;
    logic execute_port_b_sel_ex;
    alu_select_e alu_op_sel_ex;
    comp_select_e comp_op_sel_ex;
    logic data_memory_write_enable_ex;
    write_data_select_e reg_write_data_sel_ex;

///////////////////////////////////////////////////////////////
//                 DATA MEMORY SIGNALS                       //
///////////////////////////////////////////////////////////////

    logic [ADDR_WIDTH-1:0]pc_next_dm;
    logic [REG_ADDR_WIDTH-1:0]reg_destination_addr_dm;
    logic [XLEN-1:0]immediate_dm;
    logic [XLEN-1:0]reg_source_2_data_dm;
    logic [XLEN-1:0]alu_output_dm;
    logic comp_output_dm;
    logic [XLEN-1:0]read_data_aligned_dm;
    logic [XLEN-1:0]write_data_unaligned_dm;
    load_store_type_e load_store_type_dm;
    logic [XLEN-1:0]dmem_data_dm;
    logic [XLEN-1:0]reg_data_dm;
    logic reg_write_enable_dm;
    imm_select_e imm_select_dm;
    logic data_memory_write_enable_dm;
    write_data_select_e reg_write_data_sel_dm;

///////////////////////////////////////////////////////////////
//                 WRITE BACK SIGNALS                        //
///////////////////////////////////////////////////////////////

    logic [ADDR_WIDTH-1:0]pc_next_wb;
    logic [REG_ADDR_WIDTH-1:0]reg_destination_addr_wb;
    logic [XLEN-1:0]immediate_wb;
    logic [XLEN-1:0]alu_output_wb;
    logic comp_output_wb;
    logic [XLEN-1:0]dmem_data_wb;
    logic reg_write_enable_wb;
    imm_select_e imm_select_wb;
    write_data_select_e reg_write_data_sel_wb;
    logic [XLEN-1:0]reg_data_wb;

///////////////////////////////////////////////////////////////
//           PIPELINE DATA / CONTROL SIGNALS                 //
///////////////////////////////////////////////////////////////

    logic stall_pc_if;
    logic stall_if_id;
    logic clear_if_id;
    logic clear_id_ex;
    logic branch_enable;
    logic [XLEN-1:0] reg_source_1_data;
    logic [XLEN-1:0] reg_source_2_data;
    logic [1:0]reg_source_1_data_sel;
    logic [1:0]reg_source_2_data_sel;
    logic [XLEN-1:0]reg_data;

///////////////////////////////////////////////////////////////
//                 INSTRUCTION FETCH STAGE                   //
///////////////////////////////////////////////////////////////

    assign pc_next_if = PC_if + {{XLEN-3{1'b0}},3'b100};
    always_comb
    begin
        if((pc_mux_sel_ex[0] == 1'b1) || ((pc_mux_sel_ex[1] == 1'b1) && (comp_output_ex == 1'b1)))
        begin
            branch_enable = 1'b1;
        end
        else
        begin
            branch_enable = 1'b0;
        end
    end
    
    assign pc_update_if = branch_enable ? alu_output_ex : pc_next_if;
    
    always_ff @(posedge clk_i, posedge reset_i)
    begin
        if (reset_i)
        begin
            PC_if <= 32'd0;
        end
        else if(~stall_pc_if)
        begin
            PC_if <= pc_update_if;
        end
    end

    assign instruction_address_o = PC_if;
    assign instruction_if = instruction_data_i;

///////////////////////////////////////////////////////////////
//    INSTRUCTION FETCH / INSTRUCTION DECODE INTERFACE       //
///////////////////////////////////////////////////////////////

    always_ff @(posedge clk_i, posedge reset_i)
    begin
        if (clear_if_id | reset_i)
        begin
            PC_id <= {ADDR_WIDTH{1'b0}};
            pc_next_id <= {ADDR_WIDTH{1'b0}};
            instruction_id <= {XLEN{1'b0}};
            reg_source_1_addr_id <= {REG_ADDR_WIDTH{1'b0}};
            reg_source_2_addr_id <= {REG_ADDR_WIDTH{1'b0}};
            reg_destination_addr_id <= {REG_ADDR_WIDTH{1'b0}};
        end
        else if(~stall_if_id)
        begin
            PC_id <= PC_if;
            pc_next_id <= pc_next_if;
            instruction_id <= instruction_if;
            reg_source_1_addr_id <= instruction_if[19:15];
            reg_source_2_addr_id <= instruction_if[24:20];
            reg_destination_addr_id <= instruction_if[11:7];
        end
    end

///////////////////////////////////////////////////////////////
//                INSTRUCTION DECODE STAGE                   //
///////////////////////////////////////////////////////////////

    RegisterFile #(.XLEN(XLEN), .REG_ADDR_WIDTH(REG_ADDR_WIDTH)) regfile
    (
        .read_data_1_o      (reg_source_1_data_id),
        .read_data_2_o      (reg_source_2_data_id),
        .clk_i              (clk_i),
        .write_enable_i     (reg_write_enable_wb),
        .write_data_i       (reg_data_wb),
        .write_address_i    (reg_destination_addr_wb),
        .read_address_1_i   (reg_source_1_addr_id),
        .read_address_2_i   (reg_source_2_addr_id)
    );

    ImmediateSignExtend #(.XLEN(XLEN)) ise
    (
        .imm_o      (immediate_id),
        .imm_i      (instruction_id[31:7]),
        .imm_sel_i  (imm_select_id)
    );

    CoreControlUnit ccu
    (
        .pc_mux_sel_o                     (pc_mux_sel_id),
        .reg_write_enable_o               (reg_write_enable_id),
        .imm_select_o                     (imm_select_id),
        .execute_port_a_sel_o             (execute_port_a_sel_id),
        .execute_port_b_sel_o             (execute_port_b_sel_id),
        .alu_op_sel_o                     (alu_op_sel_id),
        .comp_op_sel_o                    (comp_op_sel_id),
        .load_store_type_o                (load_store_type_id),
        .data_memory_write_enable_o       (data_memory_write_enable_id),
        .reg_write_data_sel_o             (reg_write_data_sel_id),
        .op_code_i                        (instruction_id[6:0]),
        .funct3_i                         (instruction_id[14:12]),
        .funct7_bit5_i                    (instruction_id[30])
    );

///////////////////////////////////////////////////////////////
//         INSTRUCTION DECODE / EXECUTE INTERFACE            //
///////////////////////////////////////////////////////////////

    always_ff @(posedge clk_i, posedge reset_i)
    begin
        if (clear_id_ex | reset_i)
        begin
            PC_ex <= {ADDR_WIDTH{1'b0}};
            pc_next_ex <= {ADDR_WIDTH{1'b0}};
            reg_source_1_addr_ex <= {REG_ADDR_WIDTH{1'b0}};
            reg_source_2_addr_ex <= {REG_ADDR_WIDTH{1'b0}};
            reg_destination_addr_ex <= {REG_ADDR_WIDTH{1'b0}};
            immediate_ex <= {XLEN{1'b0}};
            reg_source_1_data_ex <= {XLEN{1'b0}};
            reg_source_2_data_ex <= {XLEN{1'b0}};
            load_store_type_ex <= LS_N_A;
            pc_mux_sel_ex <= 2'b00;
            reg_write_enable_ex <= 1'b0;
            imm_select_ex <= IMM_UNKNOWN_TYPE;
            execute_port_a_sel_ex <= 1'b1;
            execute_port_b_sel_ex <= 1'b1;
            alu_op_sel_ex <= OP_UNKNOWN;
            comp_op_sel_ex <= OP_BUNKNOWN;
            data_memory_write_enable_ex <= {1'b0};
            reg_write_data_sel_ex <= RD_MUX_ALU;
        end
        else if(~stall_if_id)
        begin
            PC_ex <= PC_id;
            pc_next_ex <= pc_next_id;
            reg_source_1_addr_ex <= reg_source_1_addr_id;
            reg_source_2_addr_ex <= reg_source_2_addr_id;
            reg_destination_addr_ex <= reg_destination_addr_id;
            immediate_ex <= immediate_id;
            reg_source_1_data_ex <= reg_source_1_data_id;
            reg_source_2_data_ex <= reg_source_2_data_id;
            load_store_type_ex <= load_store_type_id;
            pc_mux_sel_ex <= pc_mux_sel_id;
            reg_write_enable_ex <= reg_write_enable_id;
            imm_select_ex <= imm_select_id;
            execute_port_a_sel_ex <= execute_port_a_sel_id;
            execute_port_b_sel_ex <= execute_port_b_sel_id;
            alu_op_sel_ex <= alu_op_sel_id;
            comp_op_sel_ex <= comp_op_sel_id;
            data_memory_write_enable_ex <= data_memory_write_enable_id;
            reg_write_data_sel_ex <= reg_write_data_sel_id;
        end
    end

///////////////////////////////////////////////////////////////
//                     EXECUTE STAGE                         //
///////////////////////////////////////////////////////////////
    always_comb
    begin
        case(reg_source_1_data_sel)
            2'b10: reg_source_1_data = reg_data_wb;
            2'b01: reg_source_1_data = reg_data_dm;
            2'b00: reg_source_1_data = reg_source_1_data_ex;
            default: reg_source_1_data = reg_source_1_data_ex;
        endcase
        case(reg_source_2_data_sel)
            2'b10: reg_source_2_data = reg_data_wb;
            2'b01: reg_source_2_data = reg_data_dm;
            2'b00: reg_source_2_data = reg_source_2_data_ex;
            default: reg_source_2_data = reg_source_2_data_ex;
        endcase
    end

    assign alu_port_a_ex = execute_port_a_sel_ex ? reg_source_1_data : PC_ex;
    assign alu_port_b_ex = execute_port_b_sel_ex ? reg_source_2_data : immediate_ex;
    assign comp_port_a_ex = reg_source_1_data;
    assign comp_port_b_ex = execute_port_b_sel_ex ? immediate_ex : reg_source_2_data;

    ArithmeticLogicUnit #(.XLEN(XLEN), .REG_ADDR_WIDTH(REG_ADDR_WIDTH)) alu
    (
        .alu_o          (alu_output_ex),
        .alu_port_a_i   (alu_port_a_ex),
        .alu_port_b_i   (alu_port_b_ex),
        .alu_op_sel_i   (alu_op_sel_ex)
    );

    ComparatorUnit #(.XLEN(XLEN)) bcu
    (
        .comp_o           (comp_output_ex),
        .comp_port_a_i    (comp_port_a_ex),
        .comp_port_b_i    (comp_port_b_ex),
        .comp_op_sel_i    (comp_op_sel_ex)
    );

///////////////////////////////////////////////////////////////
//             EXECUTE / DATA MEMORY INTERFACE               //
///////////////////////////////////////////////////////////////

    always_ff @(posedge clk_i)
    begin
        pc_next_dm <= pc_next_ex;
        reg_destination_addr_dm <= reg_destination_addr_ex;
        immediate_dm <= immediate_ex;
        reg_source_2_data_dm <= reg_source_2_data;
        write_data_unaligned_dm <= reg_source_2_data;
        alu_output_dm <= alu_output_ex;
        comp_output_dm <= comp_output_ex;
        load_store_type_dm <= load_store_type_ex;
        reg_write_enable_dm <= reg_write_enable_ex;
        data_memory_write_enable_dm <= data_memory_write_enable_ex;
        reg_write_data_sel_dm <= reg_write_data_sel_ex;
    end

///////////////////////////////////////////////////////////////
//                   DATA MEMORY STAGE                       //
///////////////////////////////////////////////////////////////

    LoadAndStoreUnit #(.XLEN(XLEN)) lsu
    (
        .read_data_o         (read_data_aligned_dm),
        .read_data_i         (read_data_i),
        .write_data_o        (write_data_o),
        .write_data_i        (write_data_unaligned_dm),
        .load_store_type_i   (load_store_type_dm),
        .write_data_strobe_o (write_data_strobe_o)
    );

    assign address_o = alu_output_dm;
    assign dmem_data_dm = read_data_aligned_dm;
    assign write_enable_o = data_memory_write_enable_dm;
    assign write_data_unaligned = reg_source_2_data_dm;

    always_comb
    begin
        unique case(reg_write_data_sel_dm)
             RD_MUX_ALU:    reg_data_dm = alu_output_dm;
             RD_MUX_BCU:    reg_data_dm = {31'b0, comp_output_dm};
             RD_MUX_IMM:    reg_data_dm = immediate_dm;
            RD_MUX_PC_N:    reg_data_dm = pc_next_dm;
                default:    reg_data_dm = {XLEN{1'bz}};
        endcase
    end

///////////////////////////////////////////////////////////////
//             DATA MEMORY / WRITE BACK INTERFACE            //
///////////////////////////////////////////////////////////////

    always_ff @(posedge clk_i)
    begin
        reg_destination_addr_wb <= reg_destination_addr_dm;
        reg_write_enable_wb <= reg_write_enable_dm;
        reg_write_data_sel_wb <= reg_write_data_sel_dm;
        dmem_data_wb <= dmem_data_dm;
        reg_data <= reg_data_dm;
    end

///////////////////////////////////////////////////////////////
//                    WRITE BACK STAGE                       //
///////////////////////////////////////////////////////////////

    assign reg_data_wb = (reg_write_data_sel_wb == RD_MUX_DMEM) ? dmem_data_wb : reg_data;

///////////////////////////////////////////////////////////////
//               PIPELINE DATA / CONTROL                     //
///////////////////////////////////////////////////////////////

PipelineControlUnit #(.REG_ADDR_WIDTH(REG_ADDR_WIDTH)) pcu
(
    .stall_pc_if_o                  (stall_pc_if),
    .stall_if_id_o                  (stall_if_id),
    .clear_if_id_o                  (clear_if_id),
    .clear_id_ex_o                  (clear_id_ex),
    .reg_source_1_data_sel_o        (reg_source_1_data_sel),
    .reg_source_2_data_sel_o        (reg_source_2_data_sel),
    .reg_source_1_addr_id_i         (reg_source_1_addr_id),
    .reg_source_2_addr_id_i         (reg_source_2_addr_id),
    .reg_source_1_addr_ex_i         (reg_source_1_addr_ex),
    .reg_source_2_addr_ex_i         (reg_source_2_addr_ex),
    .reg_destination_addr_ex_i      (reg_destination_addr_ex),
    .reg_destination_addr_dm_i      (reg_destination_addr_dm),
    .reg_destination_addr_wb_i      (reg_destination_addr_wb),
    .reg_write_enable_dm_i          (reg_write_enable_dm),
    .reg_write_enable_wb_i          (reg_write_enable_wb),
    .reg_write_data_sel_ex_i        (reg_write_data_sel_ex),
    .branch_enable_i                (branch_enable)
);

endmodule
