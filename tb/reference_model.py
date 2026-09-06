"""Minimal independent architectural model for the repository's L_S_type test."""

from __future__ import annotations

import re
import argparse
import json
import sys
from dataclasses import dataclass
from pathlib import Path

try:
    from .termination_config import TerminationConfig, load_termination_config
except ImportError:
    from termination_config import TerminationConfig, load_termination_config


MASK32 = 0xFFFFFFFF
MEMORY_WORDS = 64
MAX_STEPS = 1000
WORD_RE = re.compile(r"^([0-9a-fA-F]{1,8})$")


class ModelError(RuntimeError):
    """An architectural model input or execution error."""


@dataclass(frozen=True)
class StoreEvent:
    address: int
    data: int


@dataclass(frozen=True)
class ArchitecturalEvent:
    index: int
    pc: int
    instruction: int
    reg_write: bool
    rd: int
    rd_value: int


@dataclass
class ExpectedState:
    registers: dict[int, int]
    memory: dict[int, int]
    completion: StoreEvent | None


def u32(value: int) -> int:
    return value & MASK32


def sign_extend(value: int, width: int) -> int:
    value &= (1 << width) - 1
    sign_bit = 1 << (width - 1)
    if value & sign_bit:
        value -= 1 << width
    return u32(value)


def signed32(value: int) -> int:
    value = u32(value)
    return value - (1 << 32) if value & 0x80000000 else value


def parse_hex_word(text: str, path: Path, line_number: int) -> int:
    match = WORD_RE.fullmatch(text.strip())
    if not match:
        raise ModelError(f"{path}:{line_number}: malformed 32-bit hexadecimal word")
    return int(match.group(1), 16)


def load_hex_words(path: Path) -> list[int]:
    if not path.is_file():
        raise ModelError(f"missing input file: {path}")

    words: list[int] = []
    for line_number, raw_line in enumerate(path.read_text().splitlines(), 1):
        text = raw_line.split("#", 1)[0].strip()
        if not text:
            continue
        words.append(parse_hex_word(text, path, line_number))
    if not words:
        raise ModelError(f"input file is empty: {path}")
    return words


def load_memory(path: Path) -> list[int]:
    words = load_hex_words(path)
    if len(words) > MEMORY_WORDS:
        raise ModelError(
            f"{path}: contains {len(words)} words, memory capacity is {MEMORY_WORDS}"
        )
    memory = [0] * MEMORY_WORDS
    memory[: len(words)] = words
    return memory


def parse_expected(path: Path) -> ExpectedState:
    if not path.is_file():
        raise ModelError(f"missing expected-results file: {path}")

    registers: dict[int, int] = {}
    memory: dict[int, int] = {}
    completion: StoreEvent | None = None
    for line_number, raw_line in enumerate(path.read_text().splitlines(), 1):
        text = raw_line.split("#", 1)[0].strip()
        if not text:
            continue
        fields = text.split()
        if len(fields) != 3:
            raise ModelError(f"{path}:{line_number}: expected three fields")
        record_type, index_text, value_text = fields
        try:
            index = int(index_text, 10)
            value = int(value_text, 16)
        except ValueError as error:
            raise ModelError(f"{path}:{line_number}: malformed expectation") from error
        if not 0 <= index < 64 or not 0 <= value <= MASK32:
            raise ModelError(f"{path}:{line_number}: expectation is out of range")

        if record_type == "REGISTER":
            if index >= 32:
                raise ModelError(f"{path}:{line_number}: register index is out of range")
            registers[index] = value
        elif record_type == "MEMORY":
            memory[index] = value
        elif record_type == "COMPLETE":
            completion = StoreEvent(index, value)
        else:
            raise ModelError(f"{path}:{line_number}: unknown record type {record_type}")

    if completion is None:
        raise ModelError(f"{path}: missing COMPLETE record")
    return ExpectedState(registers, memory, completion)


class ReferenceModel:
    """Sequential architectural model using the repository-compatible memory contract."""

    def __init__(
        self,
        instructions: list[int],
        memory: list[int],
        termination: TerminationConfig,
    ):
        self.instructions = {index * 4: word for index, word in enumerate(instructions)}
        self.regs = [0] * 32
        self.memory = memory[:]
        self.pc = 0
        self.termination = termination
        self.completion = (
            StoreEvent(termination.completion_address, termination.completion_value)
            if termination.mode == "completion_store"
            else None
        )
        self.steps = 0
        self.completion_detected = False
        self.instruction_count_reached = False
        self.changed_registers: set[int] = set()
        self.memory_writes: list[StoreEvent] = []
        self.events: list[ArchitecturalEvent] = []

    def read_register(self, index: int) -> int:
        if not 0 <= index < 32:
            raise ModelError(f"invalid register index: {index}")
        return 0 if index == 0 else self.regs[index]

    def write_register(self, index: int, value: int) -> None:
        if not 0 <= index < 32:
            raise ModelError(f"invalid register index: {index}")
        if index != 0:
            self.regs[index] = u32(value)
            self.changed_registers.add(index)
        self.regs[0] = 0

    def read_memory(self, address: int) -> int:
        if not 0 <= address < MEMORY_WORDS:
            raise ModelError(f"memory read address out of range: {address}")
        return self.memory[address]

    def write_memory(self, address: int, value: int) -> StoreEvent:
        if not 0 <= address < MEMORY_WORDS:
            raise ModelError(f"memory write address out of range: {address}")
        event = StoreEvent(address, u32(value))
        self.memory[address] = event.data
        self.memory_writes.append(event)
        if self.completion is not None and event == self.completion:
            self.completion_detected = True
        return event

    @staticmethod
    def i_immediate(instruction: int) -> int:
        return sign_extend(instruction >> 20, 12)

    @staticmethod
    def s_immediate(instruction: int) -> int:
        value = ((instruction >> 25) << 5) | ((instruction >> 7) & 0x1F)
        return sign_extend(value, 12)

    @staticmethod
    def b_immediate(instruction: int) -> int:
        value = (
            ((instruction >> 31) & 0x1) << 12
            | ((instruction >> 7) & 0x1) << 11
            | ((instruction >> 25) & 0x3F) << 5
            | ((instruction >> 8) & 0xF) << 1
        )
        return sign_extend(value, 13)

    @staticmethod
    def j_immediate(instruction: int) -> int:
        value = (
            ((instruction >> 31) & 0x1) << 20
            | ((instruction >> 12) & 0xFF) << 12
            | ((instruction >> 20) & 0x1) << 11
            | ((instruction >> 21) & 0x3FF) << 1
        )
        return sign_extend(value, 21)

    def step(self) -> None:
        if self.steps >= MAX_STEPS:
            raise ModelError(f"step limit exceeded ({MAX_STEPS})")
        if self.pc not in self.instructions:
            raise ModelError(f"PC 0x{self.pc:08x} is outside the instruction image")

        pc = self.pc
        instruction = self.instructions[pc]
        opcode = instruction & 0x7F
        rd = (instruction >> 7) & 0x1F
        funct3 = (instruction >> 12) & 0x7
        rs1 = (instruction >> 15) & 0x1F
        rs2 = (instruction >> 20) & 0x1F
        funct7 = (instruction >> 25) & 0x7F
        next_pc = u32(pc + 4)
        register_write: str | None = None
        memory_write: StoreEvent | None = None

        if opcode == 0x13:
            immediate = self.i_immediate(instruction)
            left = self.read_register(rs1)
            if funct3 == 0b000:
                mnemonic = "ADDI"
                result = u32(left + immediate)
            elif funct3 == 0b010:
                mnemonic = "SLTI"
                result = int(signed32(left) < signed32(immediate))
            elif funct3 == 0b011:
                mnemonic = "SLTIU"
                result = int(left < immediate)
            elif funct3 == 0b100:
                mnemonic = "XORI"
                result = left ^ immediate
            elif funct3 == 0b110:
                mnemonic = "ORI"
                result = left | immediate
            elif funct3 == 0b111:
                mnemonic = "ANDI"
                result = left & immediate
            elif funct3 == 0b001 and funct7 == 0b0000000:
                mnemonic = "SLLI"
                result = left << (instruction >> 20 & 0x1F)
            elif funct3 == 0b101 and funct7 == 0b0000000:
                mnemonic = "SRLI"
                result = left >> (instruction >> 20 & 0x1F)
            elif funct3 == 0b101 and funct7 == 0b0100000:
                mnemonic = "SRAI"
                result = signed32(left) >> (instruction >> 20 & 0x1F)
            else:
                raise ModelError(
                    f"unsupported I-type encoding at PC 0x{pc:08x}: "
                    f"funct3={funct3:03b} funct7={funct7:07b}"
                )
            self.write_register(rd, result)
            register_write = f"x{rd}=0x{self.read_register(rd):08x}"
        elif opcode == 0x63:
            left = self.read_register(rs1)
            right = self.read_register(rs2)
            branch_operations = {
                0b000: ("BEQ", left == right),
                0b001: ("BNE", left != right),
                0b100: ("BLT", signed32(left) < signed32(right)),
                0b101: ("BGE", signed32(left) >= signed32(right)),
                0b110: ("BLTU", left < right),
                0b111: ("BGEU", left >= right),
            }
            if funct3 not in branch_operations:
                raise ModelError(f"unsupported B-type funct3: {funct3:03b}")
            mnemonic, taken = branch_operations[funct3]
            if taken:
                next_pc = u32(pc + self.b_immediate(instruction))
        elif opcode == 0x6F:
            mnemonic = "JAL"
            self.write_register(rd, pc + 4)
            register_write = f"x{rd}=0x{self.read_register(rd):08x}"
            next_pc = u32(pc + self.j_immediate(instruction))
        elif opcode == 0x67:
            if funct3 != 0b000:
                raise ModelError(f"unsupported JALR funct3: {funct3:03b}")
            mnemonic = "JALR"
            target = u32(self.read_register(rs1) + self.i_immediate(instruction))
            self.write_register(rd, pc + 4)
            register_write = f"x{rd}=0x{self.read_register(rd):08x}"
            next_pc = target & 0xFFFFFFFE
        elif opcode == 0x33:
            operations = {
                (0b000, 0b0000000): ("ADD", lambda left, right: left + right),
                (0b000, 0b0100000): ("SUB", lambda left, right: left - right),
                (0b001, 0b0000000): ("SLL", lambda left, right: left << (right & 0x1F)),
                (0b010, 0b0000000): (
                    "SLT",
                    lambda left, right: int(signed32(left) < signed32(right)),
                ),
                (0b011, 0b0000000): ("SLTU", lambda left, right: int(left < right)),
                (0b100, 0b0000000): ("XOR", lambda left, right: left ^ right),
                (0b101, 0b0000000): ("SRL", lambda left, right: left >> (right & 0x1F)),
                (0b101, 0b0100000): (
                    "SRA",
                    lambda left, right: signed32(left) >> (right & 0x1F),
                ),
                (0b110, 0b0000000): ("OR", lambda left, right: left | right),
                (0b111, 0b0000000): ("AND", lambda left, right: left & right),
            }
            operation = operations.get((funct3, funct7))
            if operation is None:
                raise ModelError(
                    f"unsupported R-type encoding at PC 0x{pc:08x}: "
                    f"funct3={funct3:03b} funct7={funct7:07b}"
                )
            mnemonic, execute = operation
            result = u32(execute(self.read_register(rs1), self.read_register(rs2)))
            self.write_register(rd, result)
            register_write = f"x{rd}=0x{self.read_register(rd):08x}"
        elif opcode == 0x03:
            address = u32(self.read_register(rs1) + self.i_immediate(instruction))
            value = self.read_memory(address)
            load_operations = {
                0b000: ("LB", lambda word: sign_extend(word & 0xFF, 8)),
                0b001: ("LH", lambda word: sign_extend(word & 0xFFFF, 16)),
                0b010: ("LW", lambda word: word),
                0b100: ("LBU", lambda word: word & 0xFF),
                0b101: ("LHU", lambda word: word & 0xFFFF),
            }
            if funct3 not in load_operations:
                raise ModelError(f"unsupported load funct3: {funct3:03b}")
            mnemonic, transform = load_operations[funct3]
            result = transform(value)
            self.write_register(rd, result)
            register_write = f"x{rd}=0x{self.read_register(rd):08x}"
        elif opcode == 0x23:
            address = u32(self.read_register(rs1) + self.s_immediate(instruction))
            store_operations = {
                0b000: ("SB", lambda value: value & 0xFF),
                0b001: ("SH", lambda value: value & 0xFFFF),
                0b010: ("SW", lambda value: value),
            }
            if funct3 not in store_operations:
                raise ModelError(f"unsupported store funct3: {funct3:03b}")
            mnemonic, transform = store_operations[funct3]
            memory_write = self.write_memory(address, transform(self.read_register(rs2)))
        elif opcode == 0x37:
            mnemonic = "LUI"
            self.write_register(rd, instruction & 0xFFFFF000)
            register_write = f"x{rd}=0x{self.read_register(rd):08x}"
        elif opcode == 0x17:
            mnemonic = "AUIPC"
            self.write_register(rd, pc + (instruction & 0xFFFFF000))
            register_write = f"x{rd}=0x{self.read_register(rd):08x}"
        else:
            raise ModelError(
                f"unsupported instruction at PC 0x{pc:08x}: 0x{instruction:08x}"
            )

        self.pc = next_pc
        self.regs[0] = 0
        self.steps += 1
        self.events.append(
            ArchitecturalEvent(
                index=self.steps,
                pc=pc,
                instruction=instruction,
                reg_write=register_write is not None and rd != 0,
                rd=rd,
                rd_value=self.read_register(rd) if rd != 0 else 0,
            )
        )
        details = []
        if register_write is not None:
            details.append(register_write)
        if memory_write is not None:
            details.append(f"mem[{memory_write.address}]=0x{memory_write.data:08x}")
        suffix = " -> " + ", ".join(details) if details else ""
        print(f"STEP {self.steps:02d}: PC=0x{pc:08x} INSN=0x{instruction:08x} {mnemonic}{suffix}")

    def run(self) -> None:
        while not self.completion_detected and not self.instruction_count_reached:
            if (
                self.termination.mode == "instruction_count"
                and self.steps >= self.termination.instruction_count
            ):
                self.instruction_count_reached = True
                break
            self.step()
        if self.termination.mode == "completion_store" and not self.completion_detected:
            raise ModelError("completion was not detected")
        if self.termination.mode == "instruction_count" and not self.instruction_count_reached:
            raise ModelError("instruction count termination was not reached")


def compare_state(model: ReferenceModel, expected: ExpectedState) -> tuple[int, int]:
    register_mismatches = 0
    memory_mismatches = 0
    for index, expected_value in sorted(expected.registers.items()):
        actual = model.read_register(index)
        if actual != expected_value:
            register_mismatches += 1
            print(
                f"MISMATCH register x{index}: expected 0x{expected_value:08x}, "
                f"actual 0x{actual:08x}"
            )
    for index, expected_value in sorted(expected.memory.items()):
        actual = model.read_memory(index)
        if actual != expected_value:
            memory_mismatches += 1
            print(
                f"MISMATCH memory[{index}]: expected 0x{expected_value:08x}, "
                f"actual 0x{actual:08x}"
            )
    return register_mismatches, memory_mismatches


def write_state(path: Path, model: ReferenceModel) -> None:
    state = {
        "pc": model.pc,
        "regs": model.regs,
        "memory": model.memory,
        "completion_detected": model.completion_detected,
        "instruction_count_reached": model.instruction_count_reached,
        "steps": model.steps,
        "changed_registers": sorted(model.changed_registers),
        "events": [
            {
                "index": event.index,
                "pc": event.pc,
                "instruction": event.instruction,
                "reg_write": event.reg_write,
                "rd": event.rd,
                "rd_value": event.rd_value,
            }
            for event in model.events
        ],
    }
    path.write_text(json.dumps(state, indent=2) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description="Run the L_S_type architectural reference model.")
    parser.add_argument("--test", default="L_S_type", help="test name from the termination manifest")
    parser.add_argument("--state-out", type=Path, help="write the calculated state as JSON")
    args = parser.parse_args()

    root = Path(__file__).resolve().parents[1]
    program_path = root / "tb" / f"{args.test}.txt"
    memory_path = root / "tb" / "Data_Memory_Load.txt"
    expected_path = root / "tb" / "expected" / f"{args.test}_expected.txt"
    termination_path = root / "tb" / "termination_manifest.txt"

    print("RV32I Reference Model")
    print("---------------------")
    try:
        instructions = load_hex_words(program_path)
        initial_memory = load_memory(memory_path)
        termination = load_termination_config(termination_path, args.test)
        expected = parse_expected(expected_path) if expected_path.is_file() else None
        if termination.mode == "completion_store":
            if expected is None:
                raise ModelError(f"missing expected-results file: {expected_path}")
            expected_completion = StoreEvent(
                termination.completion_address,
                termination.completion_value,
            )
            if expected.completion != expected_completion:
                raise ModelError("termination manifest disagrees with expected completion record")
        model = ReferenceModel(instructions, initial_memory, termination)
        model.run()
        if args.state_out is not None:
            write_state(args.state_out, model)
        if expected is not None:
            register_mismatches, memory_mismatches = compare_state(model, expected)
        else:
            register_mismatches = memory_mismatches = 0
    except ModelError as error:
        print(f"REFERENCE MODEL: FAIL - {error}")
        return 1

    print(f"Final PC: 0x{model.pc:08x}")
    print("Changed registers:")
    for index in sorted(model.changed_registers):
        print(f"  x{index}=0x{model.read_register(index):08x}")
    print("Relevant memory contents:")
    if expected is not None:
        for index in sorted(expected.memory):
            print(f"  memory[{index}]=0x{model.read_memory(index):08x}")
    print(f"Completion detected: {model.completion_detected}")
    print(f"Executed instructions: {model.steps}")
    print(f"Register comparison: {'PASS' if register_mismatches == 0 else 'FAIL'}")
    print(f"Memory comparison: {'PASS' if memory_mismatches == 0 else 'FAIL'}")

    if register_mismatches or memory_mismatches:
        print("REFERENCE MODEL: FAIL")
        return 1
    print("REFERENCE MODEL: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
