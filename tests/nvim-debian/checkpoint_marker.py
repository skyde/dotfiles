#!/usr/bin/env python3
"""Crash-safe, stable-inode checkpoint markers for the Debian soak harness."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import stat
import sys
from pathlib import Path


SCHEMA = "1"
COMMIT_PREFIX = b"complete="
COMMIT_OFFSET = len(COMMIT_PREFIX)
MAX_RECORD_BYTES = 4096
PAYLOAD_KEYS = (
    "schema",
    "generation",
    "batch",
    "startup_attempts",
    "startup_failures",
    "workload_attempts",
    "workload_failures",
    "soak_elapsed_seconds",
    "checkpointed_utc",
)
RECORD_KEYS = ("complete", *PAYLOAD_KEYS, "payload_sha256")
NUMERIC_KEYS = (
    "generation",
    "batch",
    "startup_attempts",
    "startup_failures",
    "workload_attempts",
    "workload_failures",
    "soak_elapsed_seconds",
)
UTC_PATTERN = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
FAULT_CODES = {
    "after_invalidate": 90,
    "mid_payload": 91,
    "after_payload_fsync": 92,
    "after_commit_write": 93,
}
SAFE_OPEN_FLAGS = os.O_CLOEXEC | os.O_NOFOLLOW


class MarkerError(RuntimeError):
    """The marker is incomplete, malformed, or internally inconsistent."""


class InjectedFault(RuntimeError):
    """A deterministic publication fault used by the regression suite."""

    def __init__(self, point: str) -> None:
        super().__init__(point)
        self.point = point


def _pwrite_all(fd: int, data: bytes, offset: int) -> None:
    view = memoryview(data)
    while view:
        written = os.pwrite(fd, view, offset)
        if written <= 0:
            raise OSError("checkpoint marker pwrite made no progress")
        view = view[written:]
        offset += written


def _fsync_parent(path: Path) -> None:
    flags = os.O_RDONLY
    if hasattr(os, "O_DIRECTORY"):
        flags |= os.O_DIRECTORY
    parent_fd = os.open(path.parent, flags)
    try:
        os.fsync(parent_fd)
    finally:
        os.close(parent_fd)


def _require_marker_identity(fd: int, path: Path) -> os.stat_result:
    opened = os.fstat(fd)
    if not stat.S_ISREG(opened.st_mode):
        raise MarkerError("checkpoint marker is not a regular file")
    if opened.st_nlink != 1:
        raise MarkerError("checkpoint marker must have exactly one link")
    try:
        linked = os.stat(path, follow_symlinks=False)
    except FileNotFoundError as error:
        raise MarkerError("checkpoint marker path disappeared") from error
    if not stat.S_ISREG(linked.st_mode):
        raise MarkerError("checkpoint marker path is not a regular file")
    if (linked.st_dev, linked.st_ino) != (opened.st_dev, opened.st_ino):
        raise MarkerError("checkpoint marker path changed during access")
    return opened


def _open_stable(path: Path) -> tuple[int, bool]:
    path.parent.mkdir(parents=True, exist_ok=True)
    created = False
    try:
        fd = os.open(
            path,
            os.O_RDWR | os.O_CREAT | os.O_EXCL | SAFE_OPEN_FLAGS,
            0o600,
        )
        created = True
    except FileExistsError:
        fd = os.open(path, os.O_RDWR | SAFE_OPEN_FLAGS)
    try:
        _require_marker_identity(fd, path)
        os.fchmod(fd, 0o600)
        _require_marker_identity(fd, path)
    except BaseException:
        os.close(fd)
        raise
    return fd, created


def _open_existing(path: Path, access: int) -> int:
    fd = os.open(path, access | SAFE_OPEN_FLAGS)
    try:
        _require_marker_identity(fd, path)
    except BaseException:
        os.close(fd)
        raise
    return fd


def _invalidate_fd(fd: int) -> None:
    prefix = os.pread(fd, len(COMMIT_PREFIX), 0)
    if prefix != COMMIT_PREFIX or os.fstat(fd).st_size <= COMMIT_OFFSET:
        os.ftruncate(fd, 0)
        _pwrite_all(fd, b"complete=0\n", 0)
    else:
        _pwrite_all(fd, b"0", COMMIT_OFFSET)
    os.fsync(fd)


def _fault(point: str | None, expected: str) -> None:
    if point == expected:
        raise InjectedFault(point)


def invalidate(path: Path, fault: str | None = None) -> None:
    """Durably invalidate a marker without changing its inode."""

    fd, created = _open_stable(path)
    try:
        _invalidate_fd(fd)
        _fault(fault, "after_invalidate")
        _require_marker_identity(fd, path)
    finally:
        os.close(fd)
        if created:
            _fsync_parent(path)


def retire(path: Path) -> None:
    """Invalidate, unlink once after final export, and sync the directory."""

    try:
        fd = _open_existing(path, os.O_RDWR)
    except FileNotFoundError:
        _fsync_parent(path)
        return
    try:
        _invalidate_fd(fd)
        _require_marker_identity(fd, path)
    finally:
        os.close(fd)
    path.unlink()
    _fsync_parent(path)


def _parse_exact_lines(data: bytes, expected_keys: tuple[str, ...]) -> dict[str, str]:
    if not data or len(data) > MAX_RECORD_BYTES or not data.endswith(b"\n"):
        raise MarkerError("marker is empty, oversized, or lacks its final newline")
    try:
        text = data.decode("ascii")
    except UnicodeDecodeError as error:
        raise MarkerError("marker is not ASCII") from error
    values: dict[str, str] = {}
    keys: list[str] = []
    for line in text[:-1].split("\n"):
        if "=" not in line:
            raise MarkerError("marker contains a line without '='")
        key, value = line.split("=", 1)
        if not key or key in values:
            raise MarkerError("marker contains an empty or duplicate key")
        keys.append(key)
        values[key] = value
    if tuple(keys) != expected_keys:
        raise MarkerError("marker schema or field order is invalid")
    return values


def validate_payload(payload: bytes) -> dict[str, str]:
    values = _parse_exact_lines(payload, PAYLOAD_KEYS)
    if values["schema"] != SCHEMA:
        raise MarkerError("unsupported checkpoint marker schema")
    for key in NUMERIC_KEYS:
        value = values[key]
        if not value.isascii() or not value.isdigit():
            raise MarkerError(f"{key} is not a non-negative integer")
    if int(values["generation"]) != int(values["batch"]):
        raise MarkerError("generation and batch must match")
    if int(values["startup_failures"]) > int(values["startup_attempts"]):
        raise MarkerError("startup failures exceed attempts")
    if int(values["workload_failures"]) > int(values["workload_attempts"]):
        raise MarkerError("workload failures exceed attempts")
    if not UTC_PATTERN.fullmatch(values["checkpointed_utc"]):
        raise MarkerError("checkpointed_utc is not canonical UTC")
    return values


def publish_payload(
    payload: bytes,
    destination: Path,
    fault: str | None = None,
) -> None:
    """Publish a checksummed record and commit it on a stable inode."""

    validate_payload(payload)
    digest = hashlib.sha256(payload).hexdigest().encode("ascii")
    record = b"complete=0\n" + payload + b"payload_sha256=" + digest + b"\n"
    if len(record) > MAX_RECORD_BYTES:
        raise MarkerError("assembled checkpoint marker is oversized")

    fd, created = _open_stable(destination)
    try:
        _invalidate_fd(fd)
        _fault(fault, "after_invalidate")

        os.ftruncate(fd, 0)
        if fault == "mid_payload":
            _pwrite_all(fd, record[: max(1, len(record) // 2)], 0)
            os.fsync(fd)
            raise InjectedFault("mid_payload")
        _pwrite_all(fd, record, 0)
        os.fsync(fd)
        _fault(fault, "after_payload_fsync")

        _pwrite_all(fd, b"1", COMMIT_OFFSET)
        _fault(fault, "after_commit_write")
        os.fsync(fd)
        _require_marker_identity(fd, destination)
    finally:
        os.close(fd)
        if created:
            _fsync_parent(destination)


def publish(source: Path, destination: Path, fault: str | None = None) -> None:
    publish_payload(source.read_bytes(), destination, fault=fault)


def atomic_publish(source: Path, destination: Path) -> None:
    """Durably replace a one-time marker with a private regular file."""

    data = source.read_bytes()
    if not data or len(data) > MAX_RECORD_BYTES:
        raise MarkerError("atomic marker source is empty or oversized")
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_name(f".{destination.name}.tmp")
    try:
        temporary.unlink()
    except FileNotFoundError:
        pass

    fd = os.open(
        temporary,
        os.O_WRONLY | os.O_CREAT | os.O_EXCL | SAFE_OPEN_FLAGS,
        0o600,
    )
    try:
        _require_marker_identity(fd, temporary)
        _pwrite_all(fd, data, 0)
        os.ftruncate(fd, len(data))
        os.fsync(fd)
        _require_marker_identity(fd, temporary)
    finally:
        os.close(fd)
    os.replace(temporary, destination)
    _fsync_parent(destination)


def verify(path: Path) -> dict[str, str]:
    """Read one record snapshot and accept only a committed valid checksum."""

    try:
        fd = _open_existing(path, os.O_RDONLY)
    except FileNotFoundError as error:
        raise MarkerError("checkpoint marker is absent") from error
    try:
        commit_before = os.pread(fd, 1, COMMIT_OFFSET)
        first = os.pread(fd, MAX_RECORD_BYTES + 1, 0)
        commit_between = os.pread(fd, 1, COMMIT_OFFSET)
        second = os.pread(fd, MAX_RECORD_BYTES + 1, 0)
        commit_after = os.pread(fd, 1, COMMIT_OFFSET)
        _require_marker_identity(fd, path)
    finally:
        os.close(fd)
    if (
        commit_before != b"1"
        or commit_between != b"1"
        or commit_after != b"1"
        or first != second
    ):
        raise MarkerError("checkpoint marker changed during verification")
    data = first
    values = _parse_exact_lines(data, RECORD_KEYS)
    if values["complete"] != "1":
        raise MarkerError("checkpoint marker is not committed")
    record_lines = data[:-1].split(b"\n")
    payload = b"\n".join(record_lines[1:-1]) + b"\n"
    payload_values = validate_payload(payload)
    expected = hashlib.sha256(payload).hexdigest()
    if values["payload_sha256"] != expected:
        raise MarkerError("checkpoint marker checksum mismatch")
    return payload_values


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    for command in ("invalidate", "retire", "verify"):
        child = subparsers.add_parser(command)
        child.add_argument("path", type=Path)
    for command in ("publish", "atomic-publish"):
        child = subparsers.add_parser(command)
        child.add_argument("source", type=Path)
        child.add_argument("destination", type=Path)
    return parser


def main() -> int:
    args = _parser().parse_args()
    fault = os.environ.get("NVIM_CHECKPOINT_MARKER_FAULT") or None
    if fault is not None and fault not in FAULT_CODES:
        raise MarkerError(f"unknown injected fault: {fault}")
    try:
        if args.command == "invalidate":
            invalidate(args.path, fault=fault)
        elif args.command == "retire":
            retire(args.path)
        elif args.command == "publish":
            publish(args.source, args.destination, fault=fault)
        elif args.command == "atomic-publish":
            atomic_publish(args.source, args.destination)
        elif args.command == "verify":
            print(json.dumps(verify(args.path), sort_keys=True))
        else:
            raise AssertionError(args.command)
    except InjectedFault as error:
        return FAULT_CODES[error.point]
    except (MarkerError, OSError) as error:
        print(f"checkpoint marker error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
