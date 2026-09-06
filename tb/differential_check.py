"""Compare the independent L_S_type model state with the RTL state."""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

try:
    from .termination_config import load_termination_config
except ImportError:
    from termination_config import load_termination_config


@dataclass
class RtlState:
    pc_if: int | None
    completion: bool
    registers: dict[int, int | None]
    memory: dict[int, int | None]


@dataclass
class RetirementEvent:
    index: int
    pc: int
    instruction: int
    reg_write: bool
    rd: int
    rd_value: int | None


RETIRE_RE = re.compile(
    r"#?\s*RETIRE #(\d+) PC ([0-9a-fA-FxXzZ]+) "
    r"INSTRUCTION ([0-9a-fA-FxXzZ]+) REG_WRITE ([01]) "
    r"RD (\d+) VALUE ([0-9a-fA-FxXzZ]+)"
)


def resolve_tool(value: str) -> str:
    path = Path(value)
    if path.exists():
        return str(path)
    resolved = shutil.which(value)
    if resolved:
        return resolved
    raise FileNotFoundError(f"simulator tool not found: {value}")


def run_command(command: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )


def parse_value(text: str) -> int | None:
    if any(character in text for character in "xXzZ"):
        return None
    return int(text, 16)


def parse_retirement_events(output: str) -> list[RetirementEvent]:
    events = []
    for line in output.splitlines():
        match = RETIRE_RE.search(line)
        if match is None:
            continue
        events.append(
            RetirementEvent(
                index=int(match.group(1), 10),
                pc=int(match.group(2), 16),
                instruction=int(match.group(3), 16),
                reg_write=match.group(4) == "1",
                rd=int(match.group(5), 10),
                rd_value=parse_value(match.group(6)),
            )
        )
    return events


def compare_retirement_events(reference: list[dict], rtl: list[RetirementEvent]) -> bool:
    if len(reference) != len(rtl):
        print(
            "RETIREMENT COUNT MISMATCH\n"
            f"Reference events = {len(reference)}\n"
            f"RTL events       = {len(rtl)}"
        )
        return False

    fields = ("index", "pc", "instruction", "reg_write")
    for reference_event, rtl_event in zip(reference, rtl):
        rtl_values = {
            "index": rtl_event.index,
            "pc": rtl_event.pc,
            "instruction": rtl_event.instruction,
            "reg_write": rtl_event.reg_write,
        }
        for field in fields:
            if reference_event[field] != rtl_values[field]:
                print(
                    f"RETIREMENT MISMATCH #{reference_event['index']}\n"
                    f"Reference: {reference_event}\n"
                    f"RTL:       {rtl_event}\n"
                    f"Mismatch: {field}"
                )
                return False
        if reference_event["reg_write"]:
            if reference_event["rd"] != rtl_event.rd:
                print(
                    f"RETIREMENT MISMATCH #{reference_event['index']}\n"
                    f"Reference: {reference_event}\n"
                    f"RTL:       {rtl_event}\n"
                    "Mismatch: rd"
                )
                return False
            if reference_event["rd_value"] != rtl_event.rd_value:
                print(
                    f"RETIREMENT MISMATCH #{reference_event['index']}\n"
                    f"Reference: {reference_event}\n"
                    f"RTL:       {rtl_event}\n"
                    "Mismatch: rd_value"
                )
                return False
    print(f"Retirement comparison: PASS ({len(reference)} events)")
    return True


def parse_rtl_state(path: Path) -> RtlState:
    if not path.is_file():
        raise RuntimeError(f"RTL state file was not produced: {path}")

    pc_if: int | None = None
    completion = False
    registers: dict[int, int | None] = {}
    memory: dict[int, int | None] = {}
    for line_number, raw_line in enumerate(path.read_text().splitlines(), 1):
        fields = raw_line.split()
        if not fields:
            continue
        try:
            if fields[0] == "PC_IF" and len(fields) == 2:
                pc_if = parse_value(fields[1])
            elif fields[0] == "COMPLETION" and len(fields) == 2:
                completion = fields[1] == "1"
            elif fields[0] == "REG" and len(fields) == 3:
                registers[int(fields[1], 10)] = parse_value(fields[2])
            elif fields[0] == "MEM" and len(fields) == 3:
                memory[int(fields[1], 10)] = parse_value(fields[2])
            else:
                raise ValueError("malformed state record")
        except ValueError as error:
            raise RuntimeError(f"{path}:{line_number}: malformed RTL state") from error
    return RtlState(pc_if, completion, registers, memory)


def compile_rtl(repo_dir: Path, vlib: str, vlog: str, work: Path) -> tuple[bool, str]:
    tb_dir = repo_dir / "tb"
    source_dir = repo_dir / "src" / "multi_cycle_processor"
    library_result = run_command([vlib, str(work)], tb_dir)
    if library_result.returncode != 0:
        return False, library_result.stdout

    package = source_dir / "risc_v_32_i_pkg.sv"
    source_files = [
        package,
        *sorted(
            path
            for path in source_dir.glob("*.sv")
            if path.name not in {"risc_v_32_i_pkg.sv", "DataMemory.sv", "InstructionMemory.sv"}
        ),
        tb_dir / "DataMemory.sv",
        tb_dir / "InstructionMemory.sv",
        tb_dir / "top.sv",
    ]
    command = [vlog, "-sv", "-work", str(work), *(str(path) for path in source_files)]
    result = run_command(command, tb_dir)
    return result.returncode == 0, result.stdout


def compare_states(reference: dict, rtl: RtlState) -> bool:
    register_mismatches = 0
    memory_mismatches = 0
    unknown_registers = 0
    reference_registers = reference["regs"]
    reference_memory = reference["memory"]
    changed_registers = set(reference["changed_registers"])

    for index in range(32):
        expected = reference_registers[index]
        actual = rtl.registers.get(index)
        if actual is None:
            if index == 0 or index in changed_registers:
                register_mismatches += 1
                print(
                    f"MISMATCH register x{index}:\n"
                    f"    reference = 0x{expected:08x}\n"
                    "    rtl       = unknown"
                )
            else:
                unknown_registers += 1
                print(
                    f"UNINITIALIZED register x{index}: rtl is unknown; "
                    f"reference = 0x{expected:08x}; untouched by L_S_type"
                )
        elif actual != expected:
            register_mismatches += 1
            print(
                f"MISMATCH register x{index}:\n"
                f"    reference = 0x{expected:08x}\n"
                f"    rtl       = 0x{actual:08x}"
            )

    for index, expected in enumerate(reference_memory):
        actual = rtl.memory.get(index)
        if actual is None or actual != expected:
            memory_mismatches += 1
            actual_text = "unknown" if actual is None else f"0x{actual:08x}"
            print(
                f"MISMATCH memory[{index}]:\n"
                f"    reference = 0x{expected:08x}\n"
                f"    rtl       = {actual_text}"
            )

    print(
        f"Register comparison: {'PASS' if register_mismatches == 0 else 'FAIL'} "
        f"({32 - unknown_registers} compared, {unknown_registers} untouched unknown)"
    )
    print(f"Memory comparison: {'PASS' if memory_mismatches == 0 else 'FAIL'}")
    return register_mismatches == 0 and memory_mismatches == 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Run the L_S_type differential comparison.")
    parser.add_argument("--test", default="L_S_type", help="test name from the termination manifest")
    parser.add_argument("--vlib", default="vlib", help="ModelSim vlib command")
    parser.add_argument("--vlog", default="vlog", help="ModelSim vlog command")
    parser.add_argument("--vsim", default="vsim", help="ModelSim vsim command")
    args = parser.parse_args()

    repo_dir = Path(__file__).resolve().parents[1]
    tb_dir = repo_dir / "tb"
    try:
        vlib = resolve_tool(args.vlib)
        vlog = resolve_tool(args.vlog)
        vsim = resolve_tool(args.vsim)
        termination = load_termination_config(tb_dir / "termination_manifest.txt", args.test)
    except FileNotFoundError as error:
        print(f"DIFFERENTIAL RESULT: FAIL - {error}")
        return 2
    except ValueError as error:
        print(f"DIFFERENTIAL RESULT: FAIL - {error}")
        return 2

    print("RV32I Differential Test")
    print("-----------------------")
    print(f"Test: {args.test}")
    print(f"Compiler: {vlog}")
    print(f"Simulator: {vsim}")
    print(f"Termination: {termination.mode}")

    with tempfile.TemporaryDirectory(prefix="rv32i_differential_") as temp_dir:
        temp_path = Path(temp_dir)
        reference_state_path = temp_path / "reference_state.json"
        rtl_state_path = temp_path / "rtl_state.txt"

        reference_command = [
            sys.executable,
            str(tb_dir / "reference_model.py"),
            "--test",
            args.test,
            "--state-out",
            str(reference_state_path),
        ]
        reference_result = run_command(reference_command, tb_dir)
        if reference_result.returncode != 0:
            print(reference_result.stdout.rstrip())
            if "unsupported instruction" in reference_result.stdout:
                print(
                    "DIFFERENTIAL RESULT: SKIP - "
                    "reference model does not support all instructions in the test"
                )
                return 0
            print("DIFFERENTIAL RESULT: FAIL")
            return 1
        reference = json.loads(reference_state_path.read_text())
        print(f"Reference instructions: {reference['steps']}")
        reference_termination = reference["completion_detected"] or reference.get(
            "instruction_count_reached", False
        )
        print(f"Reference termination: {'PASS' if reference_termination else 'FAIL'}")
        print(f"Reference final PC: 0x{reference['pc']:08x}")

        work = temp_path / "work"
        compiled, compile_output = compile_rtl(repo_dir, vlib, vlog, work)
        if not compiled:
            print("RTL compile: FAIL")
            print(compile_output.rstrip())
            print("DIFFERENTIAL RESULT: FAIL")
            return 1
        print("RTL compile: PASS")

        rtl_command = [
            vsim,
            "-c",
            "-lib",
            str(work),
            "top",
            f"+TEST={args.test}",
            f"+TERMINATION={termination.mode}",
            f"+STATE_OUT={rtl_state_path.as_posix()}",
            "-do",
            "run -all; quit -f",
        ]
        if termination.mode == "instruction_count":
            rtl_command.insert(-2, f"+INSTRUCTION_COUNT={termination.instruction_count}")
        transcript = tb_dir / "transcript"
        transcript_existed = transcript.exists()
        try:
            rtl_result = run_command(rtl_command, tb_dir)
        finally:
            if not transcript_existed and transcript.exists():
                transcript.unlink()
        if rtl_result.returncode != 0:
            print(rtl_result.stdout.rstrip())
            print("DIFFERENTIAL RESULT: FAIL")
            return 1

        for line in rtl_result.stdout.splitlines():
            if "RETIRE #" in line:
                print(line.lstrip("# "))

        retirement_match = True
        if termination.mode == "instruction_count":
            retirement_match = compare_retirement_events(
                reference["events"],
                parse_retirement_events(rtl_result.stdout),
            )

        try:
            rtl = parse_rtl_state(rtl_state_path)
        except (OSError, RuntimeError) as error:
            print(f"RTL state capture: FAIL - {error}")
            print("DIFFERENTIAL RESULT: FAIL")
            return 1

        print(f"RTL completion: {'PASS' if rtl.completion else 'FAIL'}")
        rtl_pc = "unknown" if rtl.pc_if is None else f"0x{rtl.pc_if:08x}"
        print(f"RTL observed PC_IF: {rtl_pc}")
        print("PC comparison: NOT COMPARABLE (PC_IF is the pipeline fetch PC)")
        state_match = retirement_match and rtl.completion and compare_states(reference, rtl)

        if state_match:
            print("DIFFERENTIAL RESULT: PASS")
            return 0
        print("DIFFERENTIAL RESULT: FAIL")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
