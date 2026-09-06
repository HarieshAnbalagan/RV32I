"""Run the self-checking RV32I tests available in tb/expected."""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

try:
    from .termination_config import termination_test_names
except ImportError:
    from termination_config import termination_test_names


PASS_RE = re.compile(r"(?m)^\s*#?\s*(\S+) TEST: PASS\s*$")
FAIL_RE = re.compile(r"(?m)^\s*#?\s*(\S+) TEST: FAIL(?:\s|$)")
CYCLE_RE = re.compile(r"completion detected after (\d+) cycles")
DIFFERENTIAL_PASS_RE = re.compile(r"DIFFERENTIAL RESULT: PASS")
DIFFERENTIAL_FAIL_RE = re.compile(r"DIFFERENTIAL RESULT: FAIL")
DIFFERENTIAL_SKIP_RE = re.compile(r"DIFFERENTIAL RESULT: SKIP")
REFERENCE_MODEL_TESTS = {"L_S_type"}


@dataclass
class TestResult:
    name: str
    status: str
    detail: str
    cycles: str = "-"


def tool_path(value: str) -> str:
    path = Path(value)
    if path.exists():
        return str(path)
    resolved = shutil.which(value)
    if resolved:
        return resolved
    raise FileNotFoundError(f"simulator tool not found: {value}")


def discover_tests(tb_dir: Path, expected_dir: Path) -> tuple[list[str], list[TestResult]]:
    eligible: list[str] = []
    skipped: list[TestResult] = []
    instruction_files = sorted(
        path
        for path in tb_dir.glob("*.txt")
        if path.name not in {"Data_Memory_Load.txt", "termination_manifest.txt"}
    )
    instruction_names = {path.stem for path in instruction_files}

    for instruction_file in instruction_files:
        test_name = instruction_file.stem
        expected_file = expected_dir / f"{test_name}_expected.txt"
        if expected_file.is_file():
            eligible.append(test_name)
        else:
            skipped.append(
                TestResult(test_name, "SKIP", "missing expected results")
            )

    for source_file in sorted(tb_dir.glob("*.s")):
        if source_file.stem not in instruction_names:
            skipped.append(
                TestResult(source_file.stem, "SKIP", "missing instruction file")
            )

    return eligible, skipped


def run_command(command: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=cwd,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )


def compile_design(tb_dir: Path, source_dir: Path, vlib: str, vlog: str, work: Path) -> tuple[bool, str]:
    vlib_result = run_command([vlib, str(work)], tb_dir)
    if vlib_result.returncode != 0:
        return False, vlib_result.stdout

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


def run_test(test_name: str, tb_dir: Path, vsim: str, work: Path) -> TestResult:
    command = [
        vsim,
        "-c",
        "-lib",
        str(work),
        "top",
        f"+TEST={test_name}",
        "-do",
        "run -all; quit -f",
    ]
    transcript = tb_dir / "transcript"
    transcript_existed = transcript.exists()
    try:
        result = run_command(command, tb_dir)
    finally:
        if not transcript_existed and transcript.exists():
            transcript.unlink()
    output = result.stdout
    cycle_match = CYCLE_RE.search(output)
    cycles = cycle_match.group(1) if cycle_match else "-"

    if result.returncode == 0 and PASS_RE.search(output):
        return TestResult(test_name, "PASS", "", cycles)
    if "timeout" in output:
        detail = "timeout"
    elif FAIL_RE.search(output):
        detail = "simulation reported FAIL"
    elif result.returncode != 0:
        detail = f"simulator exit code {result.returncode}"
    else:
        detail = "no PASS/FAIL result"

    print(f"\n--- {test_name} output ---")
    print(output.rstrip())
    return TestResult(test_name, "FAIL", detail, cycles)


def run_differential(
    test_name: str,
    tb_dir: Path,
    differential_checker: Path,
    vlib: str,
    vlog: str,
    vsim: str,
) -> TestResult:
    command = [
        sys.executable,
        str(differential_checker),
        "--test",
        test_name,
        "--vlib",
        vlib,
        "--vlog",
        vlog,
        "--vsim",
        vsim,
    ]
    result = run_command(command, tb_dir)
    output = result.stdout
    if result.returncode == 0 and DIFFERENTIAL_PASS_RE.search(output):
        return TestResult(test_name, "PASS", "")

    if result.returncode == 0 and DIFFERENTIAL_SKIP_RE.search(output):
        if "reference model does not support" in output:
            detail = "reference model does not support all instructions"
        else:
            detail = "RTL architectural retirement termination unavailable"
        return TestResult(test_name, "SKIP", detail)
    if DIFFERENTIAL_FAIL_RE.search(output):
        detail = "differential comparison failed"
    elif result.returncode != 0:
        detail = f"differential checker exit code {result.returncode}"
    else:
        detail = "no differential PASS/FAIL result"
    print(f"\n--- {test_name} differential output ---")
    print(output.rstrip())
    return TestResult(test_name, "FAIL", detail)


def main() -> int:
    parser = argparse.ArgumentParser(description="Run the RV32I self-checking test regression.")
    parser.add_argument("--vlib", default="vlib", help="ModelSim vlib command")
    parser.add_argument("--vlog", default="vlog", help="ModelSim vlog command")
    parser.add_argument("--vsim", default="vsim", help="ModelSim vsim command")
    args = parser.parse_args()

    repo_dir = Path(__file__).resolve().parents[1]
    tb_dir = repo_dir / "tb"
    source_dir = repo_dir / "src" / "multi_cycle_processor"
    expected_dir = tb_dir / "expected"
    differential_checker = tb_dir / "differential_check.py"

    try:
        vlib = tool_path(args.vlib)
        vlog = tool_path(args.vlog)
        vsim = tool_path(args.vsim)
    except FileNotFoundError as error:
        print(f"ERROR: {error}", file=sys.stderr)
        return 2

    eligible, skipped = discover_tests(tb_dir, expected_dir)
    manifest_tests = termination_test_names(tb_dir / "termination_manifest.txt")
    print("RV32I Regression")
    print("----------------")
    print(f"Compiler: {vlog}")
    print(f"Simulator: {vsim}")

    if not eligible:
        for result in skipped:
            print(f"{result.status:<6} {result.name:<14} {result.detail}")
        print("\nERROR: no tests have both instruction and expected-results files")
        return 2

    failures: list[TestResult] = []
    passes: list[TestResult] = []
    differential_failures: list[TestResult] = []
    differential_passes: list[TestResult] = []
    differential_skips = [result for result in skipped if result.name not in manifest_tests]
    with tempfile.TemporaryDirectory(prefix="rv32i_regression_") as work_dir:
        work = Path(work_dir) / "work"
        compiled, compile_output = compile_design(tb_dir, source_dir, vlib, vlog, work)
        if not compiled:
            print("FAIL   compilation   simulator compilation failed")
            print(compile_output.rstrip())
            return 1

        for test_name in eligible:
            result = run_test(test_name, tb_dir, vsim, work)
            print(f"V3 legacy {result.status:<6} {result.name:<14} {result.cycles} cycles")
            (passes if result.status == "PASS" else failures).append(result)

            if test_name in REFERENCE_MODEL_TESTS:
                differential_result = run_differential(
                    test_name,
                    tb_dir,
                    differential_checker,
                    vlib,
                    vlog,
                    vsim,
                )
                print(
                    f"V4 differential {differential_result.status:<6} "
                    f"{differential_result.name:<14}"
                )
                if differential_result.status == "PASS":
                    differential_passes.append(differential_result)
                elif differential_result.status == "FAIL":
                    differential_failures.append(differential_result)
                else:
                    differential_skips.append(differential_result)
            else:
                differential_skips.append(
                    TestResult(test_name, "SKIP", "reference model does not support test")
                )

        for test_name in manifest_tests:
            if test_name not in eligible and (tb_dir / f"{test_name}.txt").is_file():
                differential_result = run_differential(
                    test_name,
                    tb_dir,
                    differential_checker,
                    vlib,
                    vlog,
                    vsim,
                )
                print(
                    f"V4 differential {differential_result.status:<6} "
                    f"{differential_result.name:<14} {differential_result.detail}"
                )
                if differential_result.status == "PASS":
                    differential_passes.append(differential_result)
                elif differential_result.status == "FAIL":
                    differential_failures.append(differential_result)
                else:
                    differential_skips.append(differential_result)

    for result in skipped:
        print(f"{result.status:<6} {result.name:<14} {result.detail}")

    print("\n----------------")
    print(f"PASS: {len(passes)}")
    print(f"FAIL: {len(failures)}")
    print(f"SKIP: {len(skipped)}")
    print("\nDIFFERENTIAL REGRESSION SUMMARY")
    print(f"PASS: {len(differential_passes)}")
    print(f"FAIL: {len(differential_failures)}")
    print(f"SKIP: {len(differential_skips)}")
    for result in differential_skips:
        print(f"SKIP   {result.name:<14} {result.detail}")
    return 1 if failures or differential_failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
