"""Deterministic constrained-random differential regression."""

from __future__ import annotations

import argparse
import contextlib
import io
import random
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

try:
    from .reference_model import ReferenceModel, load_memory
    from .termination_config import TerminationConfig
except ImportError:
    from reference_model import ReferenceModel, load_memory
    from termination_config import TerminationConfig


PASS_RE = re.compile(r"DIFFERENTIAL RESULT: PASS")


@dataclass
class GeneratedProgram:
    words: list[int]
    categories: set[str]
    dependency_heavy: bool
    dynamic_count: int


def mask12(value: int) -> int:
    return value & 0xFFF


def enc_i(immediate: int, rs1: int, funct3: int, rd: int, opcode: int = 0x13) -> int:
    return (mask12(immediate) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def enc_r(funct7: int, rs2: int, rs1: int, funct3: int, rd: int) -> int:
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | 0x33


def enc_u(immediate: int, rd: int, opcode: int) -> int:
    return (immediate & 0xFFFFF000) | (rd << 7) | opcode


def enc_s(immediate: int, rs2: int, rs1: int, funct3: int) -> int:
    value = mask12(immediate)
    return ((value >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | ((value & 0x1F) << 7) | 0x23


def enc_b(immediate: int, rs2: int, rs1: int, funct3: int) -> int:
    value = immediate & 0x1FFF
    return (
        (((value >> 12) & 1) << 31)
        | (((value >> 5) & 0x3F) << 25)
        | (rs2 << 20)
        | (rs1 << 15)
        | (funct3 << 12)
        | (((value >> 1) & 0xF) << 8)
        | (((value >> 11) & 1) << 7)
        | 0x63
    )


def enc_j(immediate: int, rd: int) -> int:
    value = immediate & 0x1FFFFF
    return (
        (((value >> 20) & 1) << 31)
        | (((value >> 1) & 0x3FF) << 21)
        | (((value >> 11) & 1) << 20)
        | (((value >> 12) & 0xFF) << 12)
        | (rd << 7)
        | 0x6F
    )


def generate_program(seed: int, random_length: int) -> GeneratedProgram:
    rng = random.Random(seed)
    words: list[int] = []
    categories: set[str] = {"ALU", "I_ALU", "branch", "jump", "memory"}
    dependency_heavy = True

    words.extend([
        enc_i(rng.choice([0, 1, 2, 7, 127, -1, -2048, 2047]), 0, 0, 1),
        enc_i(rng.choice([0, 1, 3, 11, 255, -1]), 0, 0, 2),
        enc_i(rng.choice([0, 1, 2, 5, 127, -1]), 0, 0, 3),
    ])

    # Forward, loop-free branch: either skip one instruction or fall through.
    if rng.randrange(2):
        words.append(enc_b(8, 0, 0, 0))  # BEQ x0, x0, +8, taken
    else:
        words.append(enc_b(8, 0, 0, 1))  # BNE x0, x0, +8, not taken
    words.append(enc_i(1, 0, 0, 3))

    # Forward, loop-free JAL with no link write.
    words.append(enc_j(8, 0))
    words.append(enc_i(2, 0, 0, 4))

    # Forward, loop-free JALR with an even target address.
    jalr_index = len(words) + 1
    target_pc = (jalr_index + 2) * 4
    words.append(enc_i(target_pc, 0, 0, 30))
    words.append(enc_i(0, 30, 0, 0, opcode=0x67))
    words.append(enc_i(3, 0, 0, 5))

    # Repository-compatible direct-indexed memory sequence with a load-use pair.
    memory_address = rng.choice([4, 8, 12, 16])
    memory_value = rng.choice([0, 1, 2, 20, 127, 0x7F00])
    words.extend([
        enc_i(memory_value, 0, 0, 28),
        enc_s(memory_address, 28, 0, 2),
        enc_i(memory_address, 0, 2, 29, opcode=0x03),
        enc_r(0, 1, 29, 0, 27),
    ])

    r_ops = [
        (0, 0b000), (0x20, 0b000), (0, 0b001), (0, 0b010),
        (0, 0b011), (0, 0b100), (0, 0b101), (0x20, 0b101),
        (0, 0b110), (0, 0b111),
    ]
    i_ops = [
        (0b000, 0), (0b010, 0), (0b011, 0), (0b100, 0),
        (0b110, 0), (0b111, 0), (0b001, 0), (0b101, 0),
    ]
    for _ in range(random_length):
        if rng.random() < 0.55:
            funct7, funct3 = rng.choice(r_ops)
            rs1 = rng.choice([1, 2, 3, 27, 28, 29])
            rs2 = rng.choice([1, 2, 27, 28, 29])
            rd = rng.randint(6, 15)
            words.append(enc_r(funct7, rs2, rs1, funct3, rd))
        else:
            funct3, _ = rng.choice(i_ops)
            rs1 = rng.choice([1, 2, 3, 27, 28, 29])
            rd = rng.randint(6, 15)
            if funct3 in (0b001, 0b101):
                immediate = rng.randint(0, 31)
                funct7 = 0x20 if funct3 == 0b101 and rng.randrange(2) else 0
                words.append((funct7 << 25) | (immediate << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | 0x13)
            else:
                words.append(enc_i(rng.choice([-2048, -127, -1, 0, 1, 127, 2047]), rs1, funct3, rd))

    # Exercise upper-immediate operations after the random body.
    words.append(enc_u(rng.choice([0x1000, 0x2000, 0x10000]), 16, 0x37))
    words.append(enc_u(rng.choice([0x1000, 0x2000, 0x10000]), 17, 0x17))
    words.append(enc_i(0, 0, 0, 0))

    memory = load_memory(Path(__file__).resolve().parent / "Data_Memory_Load.txt")
    model = ReferenceModel(words, memory, TerminationConfig("instruction_count", instruction_count=1000))
    output = io.StringIO()
    with contextlib.redirect_stdout(output):
        while model.pc in model.instructions:
            if model.steps >= 1000:
                raise RuntimeError(f"seed {seed}: generated program did not terminate")
            model.step()
    return GeneratedProgram(words, categories, dependency_heavy, model.steps)


def run_one(repo_dir: Path, seed: int, random_length: int, simulator_args: list[str]) -> tuple[bool, GeneratedProgram, str]:
    tb_dir = repo_dir / "tb"
    test_name = f"v7_random_{seed}"
    program_path = tb_dir / f"{test_name}.txt"
    manifest_path = tb_dir / "termination_manifest.txt"
    original_manifest = manifest_path.read_text()
    program = generate_program(seed, random_length)
    program_path.write_text("\n".join(f"{word:08x}" for word in program.words) + "\n")
    manifest_path.write_text(
        original_manifest
        + f"\n[{test_name}]\ntermination = instruction_count\ninstruction_count = {program.dynamic_count}\n"
    )
    try:
        command = [sys.executable, str(tb_dir / "differential_check.py"), "--test", test_name]
        command.extend(simulator_args)
        result = subprocess.run(command, cwd=tb_dir, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, check=False)
        return result.returncode == 0 and PASS_RE.search(result.stdout) is not None, program, result.stdout
    finally:
        manifest_path.write_text(original_manifest)
        if program_path.exists():
            program_path.unlink()


def main() -> int:
    parser = argparse.ArgumentParser(description="Run deterministic constrained-random RV32I differential tests.")
    parser.add_argument("--seed", type=int, default=1, help="first deterministic seed")
    parser.add_argument("--count", type=int, default=4, help="number of generated tests")
    parser.add_argument("--length", type=int, default=8, help="random ALU body length")
    parser.add_argument("--vlib", default="vlib")
    parser.add_argument("--vlog", default="vlog")
    parser.add_argument("--vsim", default="vsim")
    args = parser.parse_args()

    repo_dir = Path(__file__).resolve().parents[1]
    simulator_args = ["--vlib", args.vlib, "--vlog", args.vlog, "--vsim", args.vsim]
    passed = 0
    failed = 0
    category_counts: dict[str, int] = {}
    for offset in range(args.count):
        seed = args.seed + offset
        try:
            ok, program, output = run_one(repo_dir, seed, args.length, simulator_args)
        except Exception as error:
            ok = False
            program = GeneratedProgram([], set(), False, 0)
            output = str(error)
        if ok:
            passed += 1
            for category in program.categories:
                category_counts[category] = category_counts.get(category, 0) + 1
            print(f"PASS seed={seed} instructions={program.dynamic_count}")
        else:
            failed += 1
            print(f"FAIL seed={seed} instructions={program.dynamic_count}")
            print(output.rstrip())

    print("\nRV32I Random Differential Summary")
    print(f"Generated: {args.count}")
    print(f"PASS: {passed}")
    print(f"FAIL: {failed}")
    print(f"Unique seeds: {args.count}")
    print("Category usage:")
    for category in sorted(category_counts):
        print(f"  {category}: {category_counts[category]}")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
