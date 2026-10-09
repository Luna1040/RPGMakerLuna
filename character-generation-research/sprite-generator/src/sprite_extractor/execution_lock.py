"""Cross-process locks for mutable engine output trees."""

from __future__ import annotations

import fcntl
import atexit
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator


class OutputTreeBusy(RuntimeError):
    pass


def hold_output_tree_lock(output: str | Path):
    """Hold an output lock until process exit (suited to the existing CLI)."""
    target = Path(output).resolve()
    target.parent.mkdir(parents=True, exist_ok=True)
    handle = (target.parent / f".{target.name}.sprite-extractor.lock").open("a+b")
    fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
    atexit.register(handle.close)
    return handle


@contextmanager
def output_tree_lock(output: str | Path, *, blocking: bool = True) -> Iterator[None]:
    target = Path(output).resolve()
    target.parent.mkdir(parents=True, exist_ok=True)
    lock = target.parent / f".{target.name}.sprite-extractor.lock"
    with lock.open("a+b") as handle:
        operation = fcntl.LOCK_EX | (0 if blocking else fcntl.LOCK_NB)
        try:
            fcntl.flock(handle.fileno(), operation)
        except BlockingIOError as exc:
            raise OutputTreeBusy(f"output tree is already in use: {target}") from exc
        try:
            yield
        finally:
            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
