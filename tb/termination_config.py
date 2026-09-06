"""Shared parser for per-test architectural termination configuration."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class TerminationConfig:
    mode: str
    instruction_count: int | None = None
    completion_address: int | None = None
    completion_value: int | None = None


def load_termination_config(path: Path, test_name: str) -> TerminationConfig:
    if not path.is_file():
        raise ValueError(f"missing termination manifest: {path}")

    sections: dict[str, dict[str, str]] = {}
    section_name: str | None = None
    for line_number, raw_line in enumerate(path.read_text().splitlines(), 1):
        line = raw_line.split("#", 1)[0].strip()
        if not line:
            continue
        if line.startswith("[") and line.endswith("]"):
            section_name = line[1:-1].strip()
            if not section_name:
                raise ValueError(f"{path}:{line_number}: empty section name")
            sections[section_name] = {}
            continue
        if section_name is None or "=" not in line:
            raise ValueError(f"{path}:{line_number}: expected section or key = value")
        key, value = (field.strip() for field in line.split("=", 1))
        sections[section_name][key] = value

    values = sections.get(test_name)
    if values is None:
        raise ValueError(f"{path}: no termination entry for {test_name}")

    mode = values.get("termination")
    if mode == "instruction_count":
        try:
            count = int(values["instruction_count"], 10)
        except (KeyError, ValueError) as error:
            raise ValueError(f"{path}: invalid instruction_count for {test_name}") from error
        if count <= 0:
            raise ValueError(f"{path}: instruction_count must be positive for {test_name}")
        return TerminationConfig(mode, instruction_count=count)

    if mode == "completion_store":
        try:
            address = int(values["completion_address"], 10)
            data = int(values["completion_value"], 16)
        except (KeyError, ValueError) as error:
            raise ValueError(f"{path}: invalid completion store for {test_name}") from error
        if not 0 <= address < 64 or not 0 <= data <= 0xFFFFFFFF:
            raise ValueError(f"{path}: completion store is out of range for {test_name}")
        return TerminationConfig(mode, completion_address=address, completion_value=data)

    raise ValueError(f"{path}: unsupported termination mode for {test_name}: {mode}")


def termination_test_names(path: Path) -> list[str]:
    if not path.is_file():
        raise ValueError(f"missing termination manifest: {path}")
    names = []
    for raw_line in path.read_text().splitlines():
        line = raw_line.split("#", 1)[0].strip()
        if line.startswith("[") and line.endswith("]"):
            names.append(line[1:-1].strip())
    return names
