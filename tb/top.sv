`timescale 1ns/1ps

/***************************************************************************
* Copyright (c) 2022 Hariesh Anbalagan
* SPDX-License-Identifier: GPL-3.0-only
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
    output logic [31:0] write_data, data_address,
    output logic write_enable
);
    logic clk;
    logic reset;
    logic [31:0]instruction_address;
    logic [31:0]instruction_data;
    logic [31:0]read_data;
    logic [3:0]write_data_strobe;
    integer cycle_count;
    integer mismatch_count;
    integer completion_cycle;
    logic completion_detected;
    logic expectations_loaded;
    logic [31:0] expected_registers [0:31];
    logic [31:0] expected_memory [0:63];
    logic expected_register_valid [0:31];
    logic expected_memory_valid [0:63];
    logic [31:0] expected_completion_address;
    logic [31:0] expected_completion_write_data;
    logic expected_completion_valid;
    integer expected_file;
    integer parse_status;
    integer expected_index;
    logic [31:0] expected_value;
    string record_type;
    string test_name;
    string expected_file_name;
    string state_file_name;
    logic state_output_enabled;
    logic retire_valid;
    logic [31:0] retire_pc;
    logic [31:0] retire_instruction;
    logic retire_reg_write;
    logic [4:0] retire_rd;
    logic [31:0] retire_rd_value;
    string termination_mode;
    integer instruction_count_target;
    integer retire_count;

    always #5 clk = ~clk;

    task automatic check_value
    (
        input string name,
        input logic [31:0] expected,
        input logic [31:0] actual
    );
        begin
            if (actual !== expected)
            begin
                mismatch_count = mismatch_count + 1;
                $display("MISMATCH: %s expected %h actual %h", name, expected, actual);
            end
        end
    endtask

    task automatic write_state_file;
        integer state_file;
        integer state_index;
        begin
            if (state_output_enabled)
            begin
                state_file = $fopen(state_file_name, "w");
                if (state_file == 0)
                begin
                    $display("%s TEST: FAIL - unable to open state output %s", test_name, state_file_name);
                    mismatch_count = mismatch_count + 1;
                end
                else
                begin
                    $fwrite(state_file, "PC_IF %h\n", PrCore.PC_if);
                    $fwrite(state_file, "COMPLETION 1\n");
                    $fwrite(state_file, "REG 0 00000000\n");
                    for (state_index = 1; state_index < 32; state_index = state_index + 1)
                        $fwrite(state_file, "REG %0d %h\n", state_index, PrCore.regfile.register[state_index]);
                    for (state_index = 0; state_index < 64; state_index = state_index + 1)
                        $fwrite(state_file, "MEM %0d %h\n", state_index, dmem.data[state_index]);
                    $fclose(state_file);
                end
            end
        end
    endtask

    initial
    begin
        expectations_loaded = 1'b0;
        expected_completion_valid = 1'b0;
        if (!$value$plusargs("TERMINATION=%s", termination_mode))
            termination_mode = "completion_store";
        instruction_count_target = 0;
        void'($value$plusargs("INSTRUCTION_COUNT=%d", instruction_count_target));
        if (!$value$plusargs("TEST=%s", test_name))
            test_name = "L_S_type";
        expected_file_name = {"expected/", test_name, "_expected.txt"};
        state_output_enabled = $value$plusargs("STATE_OUT=%s", state_file_name);

        for (expected_index = 0; expected_index < 32; expected_index = expected_index + 1)
        begin
            expected_register_valid[expected_index] = 1'b0;
        end
        for (expected_index = 0; expected_index < 64; expected_index = expected_index + 1)
        begin
            expected_memory_valid[expected_index] = 1'b0;
        end

        expected_file = $fopen(expected_file_name, "r");
        if (expected_file == 0 && termination_mode == "completion_store")
        begin
            $display("%s TEST: FAIL - unable to open %s", test_name, expected_file_name);
            $finish(1);
        end

        while (expected_file != 0 && !$feof(expected_file))
        begin
            record_type = "";
            parse_status = $fscanf(expected_file, "%s %d %h\n", record_type,
                                   expected_index, expected_value);
            if (parse_status == 3)
            begin
                if (record_type == "REGISTER")
                begin
                    expected_registers[expected_index] = expected_value;
                    expected_register_valid[expected_index] = 1'b1;
                end
                else if (record_type == "MEMORY")
                begin
                    expected_memory[expected_index] = expected_value;
                    expected_memory_valid[expected_index] = 1'b1;
                end
                else if (record_type == "COMPLETE")
                begin
                    expected_completion_address = expected_index;
                    expected_completion_write_data = expected_value;
                    expected_completion_valid = 1'b1;
                end
            end
        end
        if (expected_file != 0)
            $fclose(expected_file);
        expectations_loaded = 1'b1;
    end

    initial
    begin
        wait (expectations_loaded);
        clk = 1'b0;
        reset = 1'b1;
        cycle_count = 0;
        mismatch_count = 0;
        completion_cycle = 0;
        completion_detected = 1'b0;
        retire_count = 0;

        repeat (2) @(posedge clk);
        reset = 1'b0;

        while (!completion_detected && cycle_count < 50)
        begin
            @(negedge clk);
            cycle_count = cycle_count + 1;
            if (termination_mode == "instruction_count" && retire_valid)
            begin
                retire_count = retire_count + 1;
                $display("RETIRE #%0d PC %h INSTRUCTION %h REG_WRITE %0d RD %0d VALUE %h",
                         retire_count, retire_pc, retire_instruction,
                         retire_reg_write, retire_rd, retire_rd_value);
                if (retire_count >= instruction_count_target)
                    completion_detected = 1'b1;
            end
            else if (termination_mode == "completion_store" && write_enable && expected_completion_valid &&
                (data_address == expected_completion_address) &&
                (write_data == expected_completion_write_data))
            begin
                completion_detected = 1'b1;
                completion_cycle = cycle_count;
            end
        end

        if (!completion_detected)
        begin
            $display("%s TEST: FAIL - timeout after %0d cycles", test_name, cycle_count);
            $finish(1);
        end

        @(posedge clk);
        #1;

        for (expected_index = 0; expected_index < 32; expected_index = expected_index + 1)
        begin
            if (expected_register_valid[expected_index])
            begin
                if (expected_index == 0)
                begin
                    force PrCore.regfile.read_address_1_i = 5'd0;
                    #1;
                    check_value($sformatf("x%0d", expected_index),
                                expected_registers[expected_index],
                                PrCore.regfile.read_data_1_o);
                    release PrCore.regfile.read_address_1_i;
                end
                else
                begin
                    check_value($sformatf("x%0d", expected_index),
                                expected_registers[expected_index],
                                PrCore.regfile.register[expected_index]);
                end
            end
        end

        for (expected_index = 0; expected_index < 64; expected_index = expected_index + 1)
        begin
            if (expected_memory_valid[expected_index])
            begin
                check_value($sformatf("data[%0d]", expected_index),
                            expected_memory[expected_index],
                            dmem.data[expected_index]);
            end
        end

        write_state_file();

        $display("%s TEST: completion detected after %0d cycles", test_name, completion_cycle);
        if (mismatch_count == 0)
            $display("%s TEST: PASS", test_name);
        else
            $display("%s TEST: FAIL - %0d mismatches", test_name, mismatch_count);

        $finish(mismatch_count != 0);
    end

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
        .address_o              (data_address),
        .retire_valid_o         (retire_valid),
        .retire_pc_o            (retire_pc),
        .retire_instruction_o   (retire_instruction),
        .retire_reg_write_o     (retire_reg_write),
        .retire_rd_o            (retire_rd),
        .retire_rd_value_o      (retire_rd_value)
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
