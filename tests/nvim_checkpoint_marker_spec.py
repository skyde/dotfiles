#!/usr/bin/env python3
"""Regression coverage for the stable-inode Debian checkpoint marker."""

from __future__ import annotations

import importlib.util
import os
import sys
import tempfile
import threading
from unittest import mock
from pathlib import Path


sys.dont_write_bytecode = True
SCRIPT_DIR = Path(__file__).resolve().parent
HELPER = SCRIPT_DIR / "nvim-debian" / "checkpoint_marker.py"
BYTECODE_ROOT = HELPER.parent / "__pycache__"
BYTECODE_BEFORE = (
    {entry.name for entry in BYTECODE_ROOT.iterdir()}
    if BYTECODE_ROOT.is_dir()
    else set()
)
SPEC = importlib.util.spec_from_file_location("checkpoint_marker", HELPER)
assert SPEC is not None and SPEC.loader is not None
checkpoint_marker = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(checkpoint_marker)


def payload(generation: int) -> bytes:
    return (
        "schema=1\n"
        f"generation={generation}\n"
        f"batch={generation}\n"
        f"startup_attempts={generation * 4}\n"
        "startup_failures=0\n"
        f"workload_attempts={generation}\n"
        "workload_failures=0\n"
        f"soak_elapsed_seconds={generation}\n"
        "checkpointed_utc=2026-07-24T19:17:00Z\n"
    ).encode("ascii")


def require_rejected(path: Path) -> None:
    try:
        checkpoint_marker.verify(path)
    except checkpoint_marker.MarkerError:
        return
    raise AssertionError(f"incomplete marker was accepted: {path}")


def require_operation_rejected(operation: object) -> None:
    try:
        assert callable(operation)
        operation()
    except (checkpoint_marker.MarkerError, OSError):
        return
    raise AssertionError("unsafe marker operation was accepted")


def fault_regressions(root: Path) -> None:
    for point in ("after_invalidate", "mid_payload", "after_payload_fsync"):
        marker = root / f"{point}.env"
        checkpoint_marker.publish_payload(payload(1), marker)
        inode = marker.stat().st_ino
        try:
            checkpoint_marker.publish_payload(payload(2), marker, fault=point)
        except checkpoint_marker.InjectedFault as error:
            assert error.point == point
        else:
            raise AssertionError(f"fault did not fire: {point}")
        assert marker.stat().st_ino == inode
        require_rejected(marker)

    committed = root / "after_commit_write.env"
    checkpoint_marker.publish_payload(payload(1), committed)
    inode = committed.stat().st_ino
    try:
        checkpoint_marker.publish_payload(
            payload(2),
            committed,
            fault="after_commit_write",
        )
    except checkpoint_marker.InjectedFault as error:
        assert error.point == "after_commit_write"
    else:
        raise AssertionError("after_commit_write fault did not fire")
    assert committed.stat().st_ino == inode
    assert checkpoint_marker.verify(committed)["generation"] == "2"


def concurrent_regression(marker: Path) -> None:
    checkpoint_marker.publish_payload(payload(1), marker)
    original_inode = marker.stat().st_ino
    stop = threading.Event()
    accepted = 0
    failures: list[BaseException] = []

    def reader() -> None:
        nonlocal accepted
        while not stop.is_set():
            try:
                values = checkpoint_marker.verify(marker)
                generation = int(values["generation"])
                assert int(values["batch"]) == generation
                assert int(values["startup_attempts"]) == generation * 4
                assert int(values["workload_attempts"]) == generation
                assert values["startup_failures"] == "0"
                assert values["workload_failures"] == "0"
                accepted += 1
            except checkpoint_marker.MarkerError:
                continue
            except BaseException as error:  # noqa: BLE001 - preserve thread failure
                failures.append(error)
                stop.set()

    thread = threading.Thread(target=reader, daemon=True)
    thread.start()
    try:
        for generation in range(2, 1002):
            checkpoint_marker.publish_payload(payload(generation), marker)
            assert marker.stat().st_ino == original_inode
    finally:
        stop.set()
        thread.join(timeout=5)
    assert not thread.is_alive()
    assert not failures
    assert accepted > 0
    assert checkpoint_marker.verify(marker)["generation"] == "1001"


def mixed_snapshot_regression(root: Path) -> None:
    marker = root / "mixed.env"
    checkpoint_marker.publish_payload(payload(1), marker)
    checkpoint_marker.publish_payload(payload(2), marker)
    new_record = marker.read_bytes()
    checkpoint_marker.publish_payload(payload(1), marker)
    reads = iter((b"1", new_record, b"0", new_record, b"0"))
    with mock.patch.object(
        checkpoint_marker.os,
        "pread",
        side_effect=lambda *_args: next(reads),
    ):
        require_rejected(marker)


def strict_verifier_regression(root: Path) -> None:
    marker = root / "strict.env"
    checkpoint_marker.publish_payload(payload(7), marker)
    inode = marker.stat().st_ino
    checkpoint_marker.invalidate(marker)
    assert marker.stat().st_ino == inode
    require_rejected(marker)

    checkpoint_marker.publish_payload(payload(8), marker)
    with marker.open("r+b", buffering=0) as stream:
        data = stream.read()
        offset = data.index(b"startup_attempts=") + len(b"startup_attempts=")
        os.pwrite(stream.fileno(), b"9", offset)
        os.fsync(stream.fileno())
    require_rejected(marker)

    checkpoint_marker.publish_payload(payload(9), marker)
    original_inode = marker.stat().st_ino
    oversized_digits = b"0" * 2000
    oversized = payload(10).replace(
        b"generation=10\nbatch=10\n",
        b"generation=" + oversized_digits + b"\nbatch=" + oversized_digits + b"\n",
    )
    require_operation_rejected(
        lambda: checkpoint_marker.publish_payload(oversized, marker)
    )
    assert marker.stat().st_ino == original_inode
    assert checkpoint_marker.verify(marker)["generation"] == "9"

    target = root / "target.env"
    target.write_text("do not mutate\n", encoding="ascii")
    target.chmod(0o644)
    target_mode = target.stat().st_mode & 0o777
    symlink = root / "symlink.env"
    symlink.symlink_to(target)
    require_operation_rejected(lambda: checkpoint_marker.invalidate(symlink))
    assert target.read_text(encoding="ascii") == "do not mutate\n"

    hardlink = root / "hardlink.env"
    os.link(target, hardlink)
    require_operation_rejected(lambda: checkpoint_marker.invalidate(hardlink))
    assert target.read_text(encoding="ascii") == "do not mutate\n"
    assert target.stat().st_mode & 0o777 == target_mode

    final_source = root / "final-source.env"
    final_source.write_text("status=0\ncomplete=1\n", encoding="ascii")
    final_destination = root / "final.env"
    checkpoint_marker.atomic_publish(final_source, final_destination)
    assert final_destination.read_bytes() == final_source.read_bytes()
    assert final_destination.stat().st_nlink == 1
    assert final_destination.stat().st_mode & 0o777 == 0o600

    checkpoint_marker.retire(marker)
    assert not marker.exists()
    checkpoint_marker.retire(marker)


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="nvim-checkpoint-marker.") as temp:
        root = Path(temp)
        fault_regressions(root)
        concurrent_regression(root / "concurrent.env")
        mixed_snapshot_regression(root)
        strict_verifier_regression(root)
    bytecode_after = (
        {entry.name for entry in BYTECODE_ROOT.iterdir()}
        if BYTECODE_ROOT.is_dir()
        else set()
    )
    assert bytecode_after == BYTECODE_BEFORE
    print("nvim stable checkpoint marker tests passed")


if __name__ == "__main__":
    main()
