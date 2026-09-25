#!/usr/bin/env python3
"""Maintain a body-free Slack unread triage manifest.

The manifest contains Slack identifiers, user choices, exact-draft hashes, and
verification states. Message and draft bodies are never persisted.
"""

from __future__ import annotations

import argparse
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
import re
import stat
import sys
import tempfile
import time
import unicodedata
from decimal import Decimal
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 2
LEGACY_SCHEMA_VERSIONS = {1}
SURFACES = {"dm", "group_dm", "channel", "thread"}
DECISIONS = {"pending", "leave_unread", "mark_read", "reply"}
SEND_STATES = {
    "not_applicable",
    "not_dispatched",
    "ack_pending",
    "sent_verified",
    "ambiguous",
    "failed",
}
SEND_STATE_TRANSITIONS = {
    "not_applicable": frozenset(),
    "not_dispatched": frozenset({"ack_pending"}),
    "ack_pending": frozenset({"sent_verified", "ambiguous", "failed"}),
    "sent_verified": frozenset(),
    "ambiguous": frozenset(),
    "failed": frozenset(),
}
RUN_STATES = {"active", "stopped"}
UI_OPERATIONS = {
    "leave_unread",
    "mark_read",
    "restore_unread",
    "send",
    "inspect_send",
}
UI_OUTCOMES = {"succeeded", "failed", "ambiguous"}
UI_OBSERVED_STATES = {
    "target_already_correct",
    "target_not_reached",
    "selector_missing",
    "ui_changed",
    "ambiguous",
    "other",
}
UI_OPERATION_STATES = {"retry_available", "succeeded", "exhausted"}
MAX_UI_ATTEMPTS = 2
MAX_TRANSITION_LOG = 200
MANIFEST_LOCK_TIMEOUT_SECONDS = 1.0
MANIFEST_LOCK_POLL_SECONDS = 0.025
MAX_MANIFEST_BYTES = 8 * 1024 * 1024
MAX_JSON_DEPTH = 32
MAX_JSON_NODES = 250_000
MAX_JSON_INTEGER_DIGITS = 20
MAX_JSON_INTEGER_VALUE = (10**MAX_JSON_INTEGER_DIGITS) - 1
MAX_DRAFT_CHARS = 40_000
EMPTY_SHA256 = hashlib.sha256(b"").hexdigest()
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
NUMERIC_SLACK_TS_RE = re.compile(r"^\d+(?:\.\d+)?$")
SLACK_TS_RE = re.compile(r"^(?:0|[1-9]\d*)\.(?:0|\d*[1-9])$")
STRATEGY_RE = re.compile(r"^[a-z0-9][a-z0-9_-]{0,63}$")
SENT_MESSAGE_KEY_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:/-]{0,255}$")
MAX_IDENTITY_CHARS = 256
MAX_SLACK_TS_CHARS = 64


class StateError(ValueError):
    pass


ROOT_FIELDS = frozenset(
    {
        "schema_version",
        "run_id",
        "session_id",
        "session_generation",
        "snapshot_at",
        "created_at",
        "updated_at",
        "setup",
        "run_state",
        "active_key",
        "prefetched_key",
        "resume_key",
        "presented_keys",
        "resolved_keys",
        "stopped_at",
        "stopped_unread_keys",
        "transition_seq",
        "transition_log",
        "ui_operation",
        "ui_operation_history",
        "checkpoint",
        "read_cursor_checkpoints",
        "ui_retry_rearm_tokens",
        "failed_send_rearm_tokens",
        "messages",
        "decision_lane",
    }
)
SETUP_FIELDS = frozenset(
    {"references_loaded", "snapshot_frozen", "computer_use_initialized"}
)
DECISION_LANE_FIELDS = frozenset({"current_key", "submitted_keys", "workspace_accounts"})
SNAPSHOT_ROW_FIELDS = frozenset({
    "key", "workspace", "conversation", "surface", "message_ts",
    "unread_boundary_ts", "thread_key",
})
MESSAGE_FIELDS = frozenset(
    {
        "key",
        "workspace",
        "conversation",
        "surface",
        "message_ts",
        "thread_key",
        "original_unread",
        "original_unread_boundary_ts",
        "materialized",
        "decision",
        "draft_version",
        "approved_sha256",
        "approved_chars",
        "send_state",
        "sent_message_key",
        "legacy_send_reconciliation",
        "readonly_seen",
        "ui_disposition_verified",
    }
)
UI_OPERATION_FIELDS = frozenset(
    {
        "key",
        "operation",
        "intended_decision",
        "draft_version",
        "approved_sha256",
        "binding_trusted",
        "state",
        "attempts",
    }
)
UI_ATTEMPT_FIELDS = frozenset(
    {"attempt", "strategy", "outcome", "observed_state", "fresh_read", "at"}
)
CHECKPOINT_FIELDS = frozenset(
    {
        "kind",
        "key",
        "at",
        "read_cursor_restored",
        "operation",
        "attempts",
        "desired_state",
        "observed_state",
    }
)
CURSOR_CHECKPOINT_FIELDS = frozenset({"key", "boundary_ts", "state", "at"})
TRANSITION_FIELDS = frozenset(
    {
        "seq",
        "event",
        "key",
        "at",
        "fields",
        "decision",
        "send_state",
        "from_send_state",
        "operation",
        "attempt",
        "outcome",
        "retry_state",
        "intended_decision",
        "draft_version",
    }
)


def require_allowed_fields(value: Any, allowed: frozenset[str], field: str) -> None:
    """Reject unrecognized manifest fields before any migration can mask them."""

    if not isinstance(value, dict):
        return
    unknown = sorted(set(value) - allowed)
    if unknown:
        label = "field" if len(unknown) == 1 else "fields"
        raise StateError(
            f"{field} contains unknown {label} {unknown}; "
            "triage manifests must remain body-free"
        )


def is_exact_int(
    value: Any,
    *,
    minimum: int | None = None,
    maximum: int = MAX_JSON_INTEGER_VALUE,
) -> bool:
    """Return true only for real integers, never bool (a Python int subclass)."""

    return bool(
        type(value) is int
        and abs(value) <= maximum
        and (minimum is None or value >= minimum)
    )


def require_identity_string(
    value: Any,
    field: str,
    *,
    max_chars: int = MAX_IDENTITY_CHARS,
) -> str:
    """Validate one bounded, control-free identifier without accepting body text."""

    if not isinstance(value, str) or not value or value != value.strip():
        raise StateError(f"{field} must be a non-empty bounded single-line identity")
    if len(value) > max_chars or any(
        unicodedata.category(character).startswith("C")
        or character in {"\u2028", "\u2029"}
        for character in value
    ):
        raise StateError(f"{field} must be a non-empty bounded single-line identity")
    return value


def canonical_slack_timestamp(value: Any, field: str) -> str:
    """Normalize numeric Slack timestamps before storage or identity comparison."""

    text = require_identity_string(value, field, max_chars=MAX_SLACK_TS_CHARS)
    if not NUMERIC_SLACK_TS_RE.fullmatch(text):
        raise StateError(f"{field} must be numeric Slack-style time")
    integer, separator, fraction = text.partition(".")
    canonical_integer = str(int(integer))
    canonical_fraction = fraction.rstrip("0") if separator else ""
    if not canonical_fraction:
        canonical_fraction = "0"
    canonical = f"{canonical_integer}.{canonical_fraction}"
    if not SLACK_TS_RE.fullmatch(canonical):
        raise StateError(f"{field} must be canonical Slack-style time")
    return canonical


def slack_timestamp_value(value: Any, field: str) -> Decimal:
    """Return an exact, bounded numeric value for one canonical Slack timestamp."""

    return Decimal(canonical_slack_timestamp(value, field))


def validate_ui_outcome_observation(
    outcome: Any,
    observed_state: Any,
    field: str,
) -> None:
    """Reject contradictory rendered evidence before it can verify an action."""

    if outcome not in UI_OUTCOMES:
        raise StateError(f"{field}.outcome must be one of {sorted(UI_OUTCOMES)}")
    if observed_state not in UI_OBSERVED_STATES:
        raise StateError(
            f"{field}.observed_state must be one of {sorted(UI_OBSERVED_STATES)}"
        )
    if outcome == "succeeded" and observed_state != "target_already_correct":
        raise StateError(
            f"{field} succeeded outcome requires observed_state=target_already_correct"
        )
    if outcome == "ambiguous" and observed_state not in {
        "ambiguous",
        "ui_changed",
        "other",
    }:
        raise StateError(
            f"{field} ambiguous outcome requires an uncertain observed state"
        )
    if outcome == "failed" and observed_state not in {
        "selector_missing",
        "target_not_reached",
    }:
        raise StateError(
            f"{field} failed outcome contradicts observed_state={observed_state}"
        )


def validate_manifest_shape(data: dict[str, Any]) -> None:
    """Enforce the recursive body-free field allowlist for loaded state."""

    require_allowed_fields(data, ROOT_FIELDS, "state")
    require_allowed_fields(data.get("setup"), SETUP_FIELDS, "setup")
    if "decision_lane" in data:
        require_allowed_fields(data["decision_lane"], DECISION_LANE_FIELDS, "decision_lane")

    messages = data.get("messages")
    if isinstance(messages, list):
        for index, message in enumerate(messages):
            require_allowed_fields(message, MESSAGE_FIELDS, f"messages[{index}]")

    operation = data.get("ui_operation")
    require_allowed_fields(operation, UI_OPERATION_FIELDS, "ui_operation")
    if isinstance(operation, dict) and isinstance(operation.get("attempts"), list):
        for index, attempt in enumerate(operation["attempts"]):
            require_allowed_fields(
                attempt,
                UI_ATTEMPT_FIELDS,
                f"ui_operation.attempts[{index}]",
            )

    history = data.get("ui_operation_history")
    if isinstance(history, list):
        for history_index, historical in enumerate(history):
            prefix = f"ui_operation_history[{history_index}]"
            require_allowed_fields(historical, UI_OPERATION_FIELDS, prefix)
            if isinstance(historical, dict) and isinstance(
                historical.get("attempts"), list
            ):
                for attempt_index, attempt in enumerate(historical["attempts"]):
                    require_allowed_fields(
                        attempt,
                        UI_ATTEMPT_FIELDS,
                        f"{prefix}.attempts[{attempt_index}]",
                    )

    require_allowed_fields(data.get("checkpoint"), CHECKPOINT_FIELDS, "checkpoint")
    cursor_checkpoints = data.get("read_cursor_checkpoints")
    if isinstance(cursor_checkpoints, list):
        for index, checkpoint in enumerate(cursor_checkpoints):
            require_allowed_fields(
                checkpoint,
                CURSOR_CHECKPOINT_FIELDS,
                f"read_cursor_checkpoints[{index}]",
            )

    transition_log = data.get("transition_log")
    if isinstance(transition_log, list):
        for index, event in enumerate(transition_log):
            require_allowed_fields(
                event,
                TRANSITION_FIELDS,
                f"transition_log[{index}]",
            )


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def parse_iso(value: str, field: str) -> None:
    try:
        datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError as exc:
        raise StateError(f"{field} must be an ISO-8601 timestamp") from exc


def manifest_lock_path(path: Path) -> Path:
    """Return the stable advisory-lock path for one manifest."""

    return path.with_name(f".{path.name}.lock")


@contextmanager
def exclusive_manifest_lock(path: Path):
    """Serialize a manifest transaction on a stable, private lock inode.

    The lock file is deliberately retained after use. Removing it would allow
    two callers to lock different inodes for the same manifest. Unsafe lock
    paths or acquisition failures stop the transaction before the manifest is
    read or written. Brief contention waits, but the bounded deadline prevents
    a hung writer from stalling triage indefinitely.
    """

    path.parent.mkdir(parents=True, exist_ok=True)
    lock_path = manifest_lock_path(path)
    flags = os.O_RDWR | os.O_CREAT
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        fd = os.open(lock_path, flags, 0o600)
    except OSError as exc:
        raise StateError("cannot open manifest lock safely") from exc
    try:
        try:
            opened = os.fstat(fd)
            if not stat.S_ISREG(opened.st_mode):
                raise StateError("manifest lock is not a regular file")
            linked_before = os.stat(lock_path, follow_symlinks=False)
            if (opened.st_dev, opened.st_ino) != (
                linked_before.st_dev,
                linked_before.st_ino,
            ):
                raise StateError("manifest lock path is unsafe")
            if opened.st_nlink != 1:
                raise StateError("manifest lock has unexpected hard links")
            os.fchmod(fd, 0o600)
            deadline = time.monotonic() + MANIFEST_LOCK_TIMEOUT_SECONDS
            while True:
                try:
                    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    break
                except BlockingIOError as exc:
                    remaining = deadline - time.monotonic()
                    if remaining <= 0:
                        raise StateError(
                            "manifest lock contention exceeded "
                            f"{MANIFEST_LOCK_TIMEOUT_SECONDS:.3f}s"
                        ) from exc
                    time.sleep(min(MANIFEST_LOCK_POLL_SECONDS, remaining))
            linked = os.stat(lock_path, follow_symlinks=False)
            locked = os.fstat(fd)
        except StateError:
            raise
        except OSError as exc:
            raise StateError("cannot acquire manifest lock safely") from exc
        def verify_bound_lock() -> None:
            try:
                linked_now = os.stat(lock_path, follow_symlinks=False)
                locked_now = os.fstat(fd)
            except OSError as exc:
                raise StateError("manifest lock changed while held") from exc
            if (
                not stat.S_ISREG(linked_now.st_mode)
                or not stat.S_ISREG(locked_now.st_mode)
                or locked_now.st_nlink != 1
                or (locked_now.st_dev, locked_now.st_ino)
                != (linked_now.st_dev, linked_now.st_ino)
            ):
                raise StateError("manifest lock changed while held")
            if stat.S_IMODE(locked_now.st_mode) != 0o600:
                raise StateError("manifest lock permissions changed while held")

        verify_bound_lock()
        yield verify_bound_lock
    finally:
        os.close(fd)


def file_identity(info: os.stat_result) -> tuple[int, int, int, int, int, int, int]:
    """Bind one regular file's inode, privacy mode, size, and change times."""

    return (
        info.st_dev,
        info.st_ino,
        info.st_nlink,
        stat.S_IMODE(info.st_mode),
        info.st_size,
        info.st_mtime_ns,
        info.st_ctime_ns,
    )


def manifest_path(value: str | os.PathLike[str]) -> Path:
    """Canonicalize the parent while preserving the supplied manifest leaf.

    Resolving the complete path would follow a manifest symlink before the
    lstat/O_NOFOLLOW boundary can reject it.  Resolving only the parent keeps
    equivalent parent aliases on one lock path while leaving the final leaf
    available for fail-closed identity checks.
    """

    supplied = Path(value).expanduser()
    if not supplied.is_absolute():
        supplied = Path.cwd() / supplied
    try:
        parent = supplied.parent.resolve(strict=False)
    except OSError as exc:
        raise StateError("cannot canonicalize state parent") from exc
    return parent / supplied.name


def manifest_identity(path: Path) -> tuple[int, int, int, int, int, int, int]:
    try:
        linked = path.lstat()
    except FileNotFoundError as exc:
        raise StateError("state file does not exist") from exc
    if (
        stat.S_ISLNK(linked.st_mode)
        or not stat.S_ISREG(linked.st_mode)
        or linked.st_nlink != 1
    ):
        raise StateError("state file must be one regular, non-symlink, non-hardlinked file")
    if stat.S_IMODE(linked.st_mode) != 0o600:
        raise StateError("state file must have private mode 0600")
    if linked.st_size <= 0 or linked.st_size > MAX_MANIFEST_BYTES:
        raise StateError(
            f"state file must contain 1 to {MAX_MANIFEST_BYTES} bytes"
        )
    return file_identity(linked)


def reject_duplicate_json_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    """Reject ambiguous JSON objects instead of silently taking the last key."""

    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise StateError(f"state JSON contains duplicate object key {key!r}")
        result[key] = value
    return result


def reject_nonfinite_json(value: str) -> None:
    raise StateError(f"state JSON contains non-finite value {value!r}")


def parse_bounded_json_int(value: str) -> int:
    """Reject oversized or noncanonical integers before bigint conversion."""

    digits = value[1:] if value.startswith("-") else value
    if not digits or len(digits) > MAX_JSON_INTEGER_DIGITS:
        raise StateError(
            "state JSON integer token exceeds the "
            f"{MAX_JSON_INTEGER_DIGITS}-digit limit"
        )
    parsed = int(value)
    if str(parsed) != value:
        raise StateError(f"state JSON integer token is noncanonical: {value!r}")
    return parsed


def reject_json_float(value: str) -> None:
    raise StateError(
        f"state JSON floating-point numbers are not permitted: {value!r}"
    )


def validate_json_structure_limits(value: Any) -> None:
    """Bound parsed structure independently of the raw byte ceiling."""

    stack: list[tuple[Any, int]] = [(value, 0)]
    nodes = 0
    while stack:
        current, depth = stack.pop()
        nodes += 1
        if nodes > MAX_JSON_NODES:
            raise StateError(
                f"state JSON exceeds the {MAX_JSON_NODES}-node limit"
            )
        if depth > MAX_JSON_DEPTH:
            raise StateError(
                f"state JSON exceeds the {MAX_JSON_DEPTH}-level nesting limit"
            )
        if isinstance(current, dict):
            stack.extend((item, depth + 1) for item in current.values())
        elif isinstance(current, list):
            stack.extend((item, depth + 1) for item in current)
        elif type(current) is int and abs(current) > MAX_JSON_INTEGER_VALUE:
            raise StateError(
                "state JSON integer value exceeds the "
                f"{MAX_JSON_INTEGER_DIGITS}-digit limit"
            )


def read_state_bound(
    path: Path,
) -> tuple[dict[str, Any], tuple[int, int, int, int, int, int, int]]:
    expected = manifest_identity(path)
    flags = os.O_RDONLY
    if hasattr(os, "O_CLOEXEC"):
        flags |= os.O_CLOEXEC
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        fd = os.open(path, flags)
    except OSError as exc:
        raise StateError("cannot open state file safely") from exc
    try:
        opened = os.fstat(fd)
        opened_identity = file_identity(opened)
        if (
            not stat.S_ISREG(opened.st_mode)
            or opened.st_nlink != 1
            or stat.S_IMODE(opened.st_mode) != 0o600
            or opened.st_size <= 0
            or opened.st_size > MAX_MANIFEST_BYTES
            or opened_identity != expected
        ):
            raise StateError("state file changed during safe open")
        with os.fdopen(os.dup(fd), "rb") as handle:
            raw = handle.read(MAX_MANIFEST_BYTES + 1)
        if len(raw) > MAX_MANIFEST_BYTES:
            raise StateError(
                f"state file exceeds the {MAX_MANIFEST_BYTES}-byte limit"
            )
        final = os.fstat(fd)
        if file_identity(final) != opened_identity:
            raise StateError("state file changed during read")
        if manifest_identity(path) != opened_identity:
            raise StateError("state file path changed during read")
    finally:
        os.close(fd)
    try:
        data = json.loads(
            raw.decode("utf-8"),
            object_pairs_hook=reject_duplicate_json_keys,
            parse_int=parse_bounded_json_int,
            parse_float=reject_json_float,
            parse_constant=reject_nonfinite_json,
        )
    except UnicodeDecodeError as exc:
        raise StateError("state file must be UTF-8 JSON") from exc
    except json.JSONDecodeError as exc:
        raise StateError("invalid JSON in state file") from exc
    except RecursionError as exc:
        raise StateError("state JSON nesting is too deep") from exc
    if not isinstance(data, dict):
        raise StateError("state root must be an object")
    validate_json_structure_limits(data)
    return upgrade_state(data), opened_identity


def read_state(path: Path) -> dict[str, Any]:
    data, _identity = read_state_bound(path)
    return data


def assert_manifest_identity(
    path: Path,
    expected: tuple[int, int, int, int, int, int, int],
) -> None:
    if manifest_identity(path) != expected:
        raise StateError("state file changed before commit")


def assert_manifest_absent(path: Path) -> None:
    try:
        path.lstat()
    except FileNotFoundError:
        return
    raise StateError("refusing to overwrite existing state")


def upgrade_ui_operation_binding(data: dict[str, Any]) -> None:
    """Keep legacy UI attempts readable without trusting an inferred binding."""

    operation = data.get("ui_operation")
    if not isinstance(operation, dict):
        return
    key = operation.get("key")
    messages = data.get("messages")
    if not isinstance(messages, list):
        return
    message = next(
        (
            item
            for item in messages
            if isinstance(item, dict) and item.get("key") == key
        ),
        None,
    )
    if message is None:
        return
    had_complete_binding = all(
        field in operation
        for field in (
            "intended_decision",
            "draft_version",
            "approved_sha256",
            "binding_trusted",
        )
    )
    operation.setdefault("intended_decision", message.get("decision"))
    if operation.get("operation") in {"send", "inspect_send"}:
        operation.setdefault("draft_version", message.get("draft_version"))
        operation.setdefault("approved_sha256", message.get("approved_sha256"))
    else:
        operation.setdefault("draft_version", None)
        operation.setdefault("approved_sha256", None)
    if not had_complete_binding:
        operation["binding_trusted"] = False


def canonicalize_manifest_timestamps(data: dict[str, Any]) -> None:
    """Canonicalize all numeric Slack identity timestamps in loaded state."""

    messages = data.get("messages")
    if isinstance(messages, list):
        for index, message in enumerate(messages):
            if not isinstance(message, dict):
                continue
            for name in ("message_ts", "original_unread_boundary_ts"):
                value = message.get(name)
                if value is not None:
                    message[name] = canonical_slack_timestamp(
                        value,
                        f"messages[{index}].{name}",
                    )
    cursor_checkpoints = data.get("read_cursor_checkpoints")
    if isinstance(cursor_checkpoints, list):
        for index, checkpoint in enumerate(cursor_checkpoints):
            if isinstance(checkpoint, dict) and checkpoint.get("boundary_ts") is not None:
                checkpoint["boundary_ts"] = canonical_slack_timestamp(
                    checkpoint["boundary_ts"],
                    f"read_cursor_checkpoints[{index}].boundary_ts",
                )


def upgrade_send_checkpoint(data: dict[str, Any]) -> None:
    """Preserve duplicate suppression for legacy ack-pending/ambiguous sends."""

    if isinstance(data.get("checkpoint"), dict):
        return
    owner_key = (
        data.get("active_key")
        if data.get("run_state", "active") == "active"
        else data.get("resume_key")
    )
    messages = data.get("messages")
    if not isinstance(messages, list):
        return
    owner = next(
        (
            item
            for item in messages
            if isinstance(item, dict) and item.get("key") == owner_key
        ),
        None,
    )
    if owner is None or owner.get("send_state") not in {"ack_pending", "ambiguous"}:
        return
    data["checkpoint"] = {
        "kind": (
            "send_ack_pending"
            if owner["send_state"] == "ack_pending"
            else "send_ambiguous"
        ),
        "key": owner_key,
        "at": data.get("updated_at") or now_iso(),
        "read_cursor_restored": False,
    }


def upgrade_unbound_send_evidence(data: dict[str, Any]) -> None:
    """Convert pre-binding send evidence into a duplicate-suppressed inspection gate."""

    operation = data.get("ui_operation")
    if (
        not isinstance(operation, dict)
        or operation.get("operation") != "send"
        or operation.get("binding_trusted") is not False
    ):
        return
    attempts = operation.get("attempts")
    final = attempts[-1] if isinstance(attempts, list) and attempts else None
    if not isinstance(final, dict) or final.get("outcome") not in {
        "succeeded",
        "ambiguous",
    }:
        return
    messages = data.get("messages")
    if not isinstance(messages, list):
        return
    owner = next(
        (
            message
            for message in messages
            if isinstance(message, dict) and message.get("key") == operation.get("key")
        ),
        None,
    )
    if not isinstance(owner, dict) or owner.get("decision") != "reply":
        return
    expected_state = (
        "ack_pending" if final.get("outcome") == "succeeded" else "ambiguous"
    )
    prior_state = owner.get("send_state")
    if prior_state == "not_dispatched":
        owner["send_state"] = expected_state
    elif prior_state not in {"ack_pending", "ambiguous"}:
        # Preserve an incoherent loaded tuple so validation rejects it.  Only
        # the exact early-v2 states the producer could have committed are
        # eligible for inspection-only migration.
        return
    owner["legacy_send_reconciliation"] = True
    owner["readonly_seen"] = False
    owner["sent_message_key"] = None
    owner["ui_disposition_verified"] = False


def upgrade_legacy_restore_unread_operation(data: dict[str, Any]) -> None:
    """Remove the obsolete public restore_unread operation without resetting risk."""

    operation = data.get("ui_operation")
    if not isinstance(operation, dict) or operation.get("operation") != "restore_unread":
        return
    if not ui_operation_all_definitively_failed(operation):
        raise StateError(
            "legacy restore_unread evidence is not definitively failed and must fail closed"
        )
    messages = data.get("messages")
    owner = next(
        (
            message
            for message in (messages if isinstance(messages, list) else [])
            if isinstance(message, dict)
            and message.get("key") == operation.get("key")
        ),
        None,
    )
    checkpoint = data.get("checkpoint")
    if isinstance(owner, dict) and owner.get("decision") == "leave_unread":
        old_rearm_used = ui_retry_rearm_was_used(data, owner, operation)
        operation["operation"] = "leave_unread"
        operation["intended_decision"] = "leave_unread"
        if old_rearm_used:
            translated_token = ui_retry_rearm_token(owner, operation)
            if translated_token not in data["ui_retry_rearm_tokens"]:
                data["ui_retry_rearm_tokens"].append(translated_token)
        if (
            isinstance(checkpoint, dict)
            and checkpoint.get("kind") == "ui_retry_exhausted"
            and checkpoint.get("key") == owner.get("key")
        ):
            checkpoint["operation"] = "leave_unread"
            checkpoint["desired_state"] = "leave_unread"
        return
    data["ui_operation"] = None
    if isinstance(checkpoint, dict) and checkpoint.get("key") == operation.get("key"):
        if data.get("run_state") == "stopped":
            data["checkpoint"] = {
                "kind": "stopped",
                "key": operation.get("key"),
                "at": checkpoint.get("at") or data.get("updated_at") or now_iso(),
                "read_cursor_restored": checkpoint.get("read_cursor_restored") is True,
            }
        else:
            data["checkpoint"] = None


def message_is_complete(message: dict[str, Any]) -> bool:
    if message.get("decision") in {"leave_unread", "mark_read"}:
        return bool(message.get("ui_disposition_verified"))
    if message.get("decision") == "reply":
        return message.get("send_state") == "sent_verified" and bool(
            message.get("ui_disposition_verified")
        )
    return False


def upgrade_state(data: dict[str, Any]) -> dict[str, Any]:
    """Upgrade a v1 body-free manifest in memory without losing resume state."""

    validate_manifest_shape(data)
    version = data.get("schema_version")
    if type(version) is not int:
        raise StateError("schema_version must be an exact integer")
    canonicalize_manifest_timestamps(data)
    if version == SCHEMA_VERSION:
        shared_retry_tokens = data.setdefault("ui_retry_rearm_tokens", [])
        messages = data.get("messages")
        if isinstance(messages, list):
            for message in messages:
                if isinstance(message, dict):
                    message.setdefault(
                        "materialized", message.get("message_ts") is not None
                    )
                    operation = data.get("ui_operation")
                    has_trusted_send_binding = bool(
                        isinstance(operation, dict)
                        and operation.get("key") == message.get("key")
                        and operation.get("operation") == "send"
                        and operation.get("binding_trusted") is True
                        and operation.get("intended_decision") == "reply"
                        and operation.get("draft_version")
                        == message.get("draft_version")
                        and operation.get("approved_sha256")
                        == message.get("approved_sha256")
                    )
                    message.setdefault(
                        "legacy_send_reconciliation",
                        message.get("decision") == "reply"
                        and message.get("send_state")
                        in {"ack_pending", "ambiguous"}
                        and not has_trusted_send_binding,
                    )
        if "failed_send_rearm_tokens" not in data:
            # Early schema-v2 builds stored both retry token types in one list.
            # A matching token is a consumed-budget tombstone, never retry
            # authority.  Copy every exact domain-separated failed-send token
            # into the typed list even when the bounded transition log no
            # longer retains its producer event.  Keep the shared list too so
            # a rare legacy cross-domain collision fails conservatively rather
            # than permitting a duplicate dispatch.
            shared_sequence = (
                shared_retry_tokens
                if isinstance(shared_retry_tokens, list)
                else []
            )
            failed_tokens: list[str] = []
            for message in messages if isinstance(messages, list) else []:
                if not isinstance(message, dict):
                    continue
                token = failed_send_rearm_token(message)
                if token in shared_sequence and token not in failed_tokens:
                    failed_tokens.append(token)
            data["failed_send_rearm_tokens"] = failed_tokens
        else:
            data.setdefault("failed_send_rearm_tokens", [])
        data.setdefault("ui_operation_history", [])
        upgrade_ui_operation_binding(data)
        upgrade_legacy_restore_unread_operation(data)
        upgrade_unbound_send_evidence(data)
        upgrade_send_checkpoint(data)
        return data
    if version not in LEGACY_SCHEMA_VERSIONS:
        return data

    messages = data.get("messages") if isinstance(data.get("messages"), list) else []
    for message in messages:
        if isinstance(message, dict):
            message.setdefault("original_unread_boundary_ts", message.get("message_ts"))
            message.setdefault("materialized", message.get("message_ts") is not None)
            operation = data.get("ui_operation")
            has_trusted_send_binding = bool(
                isinstance(operation, dict)
                and operation.get("key") == message.get("key")
                and operation.get("operation") == "send"
                and operation.get("binding_trusted") is True
            )
            message.setdefault(
                "legacy_send_reconciliation",
                message.get("decision") == "reply"
                and message.get("send_state") in {"ack_pending", "ambiguous"}
                and not has_trusted_send_binding,
            )
    data["schema_version"] = SCHEMA_VERSION
    data.setdefault("run_id", data.get("session_id"))
    data.setdefault("session_generation", 1)
    data.setdefault("run_state", "active")
    data.setdefault("active_key", None)
    presented_missing = "presented_keys" not in data
    data.setdefault("presented_keys", [])
    data.setdefault("stopped_unread_keys", [])
    data.setdefault("stopped_at", None)
    setup_missing = "setup" not in data
    data.setdefault(
        "setup",
        {
            "references_loaded": False,
            "snapshot_frozen": bool(data.get("active_key") or data.get("presented_keys")),
            "computer_use_initialized": False,
        },
    )
    complete_keys = [
        message.get("key")
        for message in messages
        if isinstance(message, dict) and message_is_complete(message)
    ]
    data["resolved_keys"] = complete_keys
    if presented_missing:
        reconstructed_presented = list(complete_keys)
        active_owner = data.get("active_key")
        if (
            isinstance(active_owner, str)
            and active_owner not in reconstructed_presented
        ):
            reconstructed_presented.append(active_owner)
        data["presented_keys"] = reconstructed_presented
    if setup_missing:
        data["setup"]["snapshot_frozen"] = bool(
            data["presented_keys"]
            or data.get("active_key")
            or data.get("resume_key")
            or (
                data.get("run_state") == "stopped"
                and any(
                    isinstance(message, dict)
                    and not message_is_complete(message)
                    for message in messages
                )
            )
        )
    data.setdefault("prefetched_key", None)
    data.setdefault("resume_key", None)
    data.setdefault("transition_seq", 0)
    data.setdefault("transition_log", [])
    data.setdefault("ui_operation", None)
    data.setdefault("ui_operation_history", [])
    data.setdefault("checkpoint", None)
    data.setdefault("read_cursor_checkpoints", [])
    data.setdefault("ui_retry_rearm_tokens", [])
    data.setdefault("failed_send_rearm_tokens", [])
    existing_cursor_proofs = data["read_cursor_checkpoints"]
    if isinstance(existing_cursor_proofs, list):
        for message in messages:
            if not isinstance(message, dict) or not message_is_complete(message):
                continue
            key = message.get("key")
            if any(
                isinstance(checkpoint, dict)
                and checkpoint.get("key") == key
                and checkpoint.get("state")
                in {"verified_read", "verified_unread"}
                for checkpoint in existing_cursor_proofs
            ):
                continue
            expected_state = (
                "verified_unread"
                if message.get("decision") == "leave_unread"
                else "verified_read"
            )
            existing_cursor_proofs.append(
                {
                    "key": key,
                    "boundary_ts": message.get("original_unread_boundary_ts"),
                    "state": expected_state,
                    "at": data.get("updated_at") or data.get("created_at") or now_iso(),
                }
            )

    snapshot_keys = {
        message.get("key")
        for message in messages
        if isinstance(message, dict) and isinstance(message.get("key"), str)
    }
    active_key = data.get("active_key")
    resume_key = data.get("resume_key")
    if active_key is not None and (
        not isinstance(active_key, str) or active_key not in snapshot_keys
    ):
        raise StateError("legacy active_key must identify a snapshot message")
    if resume_key is not None and (
        not isinstance(resume_key, str) or resume_key not in snapshot_keys
    ):
        raise StateError("legacy resume_key must identify a snapshot message")
    incomplete_keys = [
        message.get("key")
        for message in messages
        if isinstance(message, dict) and not message_is_complete(message)
    ]
    incomplete = {key for key in incomplete_keys if isinstance(key, str)}
    ui_operation = data.get("ui_operation")
    if (
        isinstance(ui_operation, dict)
        and ui_operation.get("key") in complete_keys
    ):
        data["ui_operation"] = None
        checkpoint = data.get("checkpoint")
        if (
            isinstance(checkpoint, dict)
            and checkpoint.get("key") == ui_operation.get("key")
        ):
            data["checkpoint"] = None

    if data["run_state"] == "stopped":
        candidate_order: list[Any] = [resume_key, active_key]
        stopped_unread = data.get("stopped_unread_keys")
        if isinstance(stopped_unread, list):
            candidate_order.extend(reversed(stopped_unread))
        presented = data.get("presented_keys")
        if isinstance(presented, list):
            candidate_order.extend(reversed(presented))
        candidate_order.extend(incomplete_keys)
        data["resume_key"] = next(
            (
                candidate
                for candidate in candidate_order
                if isinstance(candidate, str) and candidate in incomplete
            ),
            None,
        )
        data["active_key"] = None
        data["prefetched_key"] = None
        if data.get("stopped_at") is None:
            data["stopped_at"] = data.get("updated_at") or data.get("created_at")
        migrated_resume_key = data.get("resume_key")
        migrated_resume = next(
            (
                item
                for item in messages
                if isinstance(item, dict) and item.get("key") == migrated_resume_key
            ),
            None,
        )
        if (
            isinstance(migrated_resume, dict)
            and migrated_resume.get("send_state")
            not in {"ack_pending", "ambiguous"}
            and data.get("checkpoint") is None
        ):
            if (
                migrated_resume.get("materialized") is True
                and migrated_resume_key not in data["stopped_unread_keys"]
            ):
                data["stopped_unread_keys"].append(migrated_resume_key)
            data["checkpoint"] = {
                "kind": "stopped",
                "key": migrated_resume_key,
                "at": data.get("updated_at") or data.get("created_at") or now_iso(),
                "read_cursor_restored": True,
            }
            if (
                migrated_resume.get("materialized") is True
                and migrated_resume_key in data.get("presented_keys", [])
                and not any(
                    isinstance(proof, dict)
                    and proof.get("key") == migrated_resume_key
                    and proof.get("state") == "restored_unread"
                    for proof in data["read_cursor_checkpoints"]
                )
            ):
                data["read_cursor_checkpoints"].append(
                    {
                        "key": migrated_resume_key,
                        "boundary_ts": migrated_resume.get(
                            "original_unread_boundary_ts"
                        ),
                        "state": "restored_unread",
                        "at": data.get("updated_at")
                        or data.get("created_at")
                        or now_iso(),
                    }
                )
    else:
        data["resume_key"] = None
        if isinstance(active_key, str) and active_key in complete_keys:
            data["active_key"] = None
            data["prefetched_key"] = None
        prefetched_key = data.get("prefetched_key")
        if (
            data.get("active_key") is None
            or not isinstance(prefetched_key, str)
            or prefetched_key not in incomplete
            or prefetched_key == data.get("active_key")
        ):
            data["prefetched_key"] = None

    upgrade_ui_operation_binding(data)
    upgrade_legacy_restore_unread_operation(data)
    upgrade_unbound_send_evidence(data)
    upgrade_send_checkpoint(data)
    validate_manifest_shape(data)
    return data


def atomic_write(
    path: Path, data: dict[str, Any], precommit_guard=None
) -> tuple[int, int, int, int, int, int, int]:
    """Replace one manifest and return the exact committed file identity.

    The temporary descriptor remains open across rename so post-commit checks
    can bind the destination path to the inode that was actually written.
    Never chmod the destination path after rename: a hostile pathname swap
    must fail closed, not follow and mutate an unrelated symlink target.
    """

    path.parent.mkdir(parents=True, exist_ok=True)
    validate_json_structure_limits(data)
    encoded = (json.dumps(data, indent=2, sort_keys=True) + "\n").encode("utf-8")
    if len(encoded) > MAX_MANIFEST_BYTES:
        raise StateError(
            f"state output exceeds the {MAX_MANIFEST_BYTES}-byte limit"
        )
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    tmp_path = Path(tmp_name)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "wb", closefd=False) as handle:
            handle.write(encoded)
            handle.flush()
            os.fsync(handle.fileno())
        staged = os.fstat(fd)
        if (
            not stat.S_ISREG(staged.st_mode)
            or staged.st_nlink != 1
            or stat.S_IMODE(staged.st_mode) != 0o600
            or staged.st_size != len(encoded)
        ):
            raise StateError("staged state file failed its private regular-file checks")
        if precommit_guard is not None:
            precommit_guard()
        os.replace(tmp_path, path)
        try:
            committed_path = path.lstat()
            committed_fd = os.fstat(fd)
        except OSError as exc:
            raise StateError("state file changed immediately after commit") from exc
        if (
            stat.S_ISLNK(committed_path.st_mode)
            or not stat.S_ISREG(committed_path.st_mode)
            or not stat.S_ISREG(committed_fd.st_mode)
            or committed_path.st_nlink != 1
            or committed_fd.st_nlink != 1
            or stat.S_IMODE(committed_path.st_mode) != 0o600
            or stat.S_IMODE(committed_fd.st_mode) != 0o600
            or committed_path.st_size != len(encoded)
            or committed_fd.st_size != len(encoded)
            or (committed_path.st_dev, committed_path.st_ino)
            != (committed_fd.st_dev, committed_fd.st_ino)
        ):
            raise StateError("state file path changed immediately after commit")
        return file_identity(committed_fd)
    finally:
        os.close(fd)
        try:
            tmp_path.unlink()
        except FileNotFoundError:
            pass


def require_string(value: Any, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise StateError(f"{field} must be a non-empty string")
    return value


def require_hash(value: Any, field: str) -> str:
    if not isinstance(value, str) or not SHA256_RE.fullmatch(value):
        raise StateError(f"{field} must be a lowercase SHA-256 hex digest")
    return value


def validate_message(message: Any, index: int) -> list[str]:
    if not isinstance(message, dict):
        raise StateError(f"messages[{index}] must be an object")
    prefix = f"messages[{index}]"
    require_identity_string(message.get("key"), f"{prefix}.key")
    require_identity_string(message.get("workspace"), f"{prefix}.workspace")
    require_identity_string(message.get("conversation"), f"{prefix}.conversation")
    surface = message.get("surface")
    if surface not in SURFACES:
        raise StateError(f"{prefix}.surface must be one of {sorted(SURFACES)}")
    if not isinstance(message.get("materialized"), bool):
        raise StateError(f"{prefix}.materialized must be boolean")
    materialized = message["materialized"]
    message_ts = message.get("message_ts")
    if materialized:
        if message_ts != canonical_slack_timestamp(message_ts, f"{prefix}.message_ts"):
            raise StateError(f"{prefix}.message_ts must be canonical Slack-style time")
    elif message_ts is not None:
        raise StateError(f"{prefix}.message_ts must be null until materialized")
    thread_key = message.get("thread_key")
    if thread_key is not None:
        require_identity_string(thread_key, f"{prefix}.thread_key")
    if message.get("original_unread") is not True:
        raise StateError(f"{prefix}.original_unread must be true")
    boundary_ts = message.get("original_unread_boundary_ts")
    if materialized:
        if boundary_ts != canonical_slack_timestamp(
            boundary_ts,
            f"{prefix}.original_unread_boundary_ts",
        ):
            raise StateError(
                f"{prefix}.original_unread_boundary_ts must be canonical Slack-style time"
            )
        if slack_timestamp_value(
            boundary_ts,
            f"{prefix}.original_unread_boundary_ts",
        ) > slack_timestamp_value(message_ts, f"{prefix}.message_ts"):
            raise StateError(
                f"{prefix}.original_unread_boundary_ts cannot follow message_ts"
            )
    elif boundary_ts is not None:
        raise StateError(
            f"{prefix}.original_unread_boundary_ts must be null until materialized"
        )
    if not materialized and thread_key is not None:
        raise StateError(f"{prefix}.thread_key must be null until materialized")

    decision = message.get("decision")
    if decision not in DECISIONS:
        raise StateError(f"{prefix}.decision must be one of {sorted(DECISIONS)}")
    # A complete read-only preview can carry user intent before Slack exposes
    # the timestamp. Intent never authorizes UI, approval, or resolution.
    if not materialized and (
        message.get("approved_sha256") is not None
        or message.get("ui_disposition_verified") is True
        or message.get("send_state") not in {"not_applicable", "not_dispatched"}
    ):
        raise StateError(f"{prefix} provisional intent cannot have approval or UI evidence")
    send_state = message.get("send_state")
    if send_state not in SEND_STATES:
        raise StateError(f"{prefix}.send_state must be one of {sorted(SEND_STATES)}")
    if not isinstance(message.get("ui_disposition_verified"), bool):
        raise StateError(f"{prefix}.ui_disposition_verified must be boolean")
    if not isinstance(message.get("readonly_seen"), bool):
        raise StateError(f"{prefix}.readonly_seen must be boolean")
    legacy_reconciliation = message.get("legacy_send_reconciliation")
    if not isinstance(legacy_reconciliation, bool):
        raise StateError(f"{prefix}.legacy_send_reconciliation must be boolean")

    version = message.get("draft_version")
    if not is_exact_int(version, minimum=0):
        raise StateError(f"{prefix}.draft_version must be a non-negative integer")
    approved_hash = message.get("approved_sha256")
    approved_chars = message.get("approved_chars")
    if approved_hash is not None and (
        not isinstance(approved_hash, str) or not SHA256_RE.fullmatch(approved_hash)
    ):
        raise StateError(f"{prefix}.approved_sha256 must be a SHA-256 or null")
    if approved_hash == EMPTY_SHA256:
        raise StateError(f"{prefix}.approved_sha256 cannot represent an empty draft")
    if approved_chars is not None and (
        not is_exact_int(
            approved_chars,
            minimum=1,
            maximum=MAX_DRAFT_CHARS,
        )
    ):
        raise StateError(f"{prefix}.approved_chars must be positive or null")
    if (approved_hash is None) != (approved_chars is None):
        raise StateError(f"{prefix} approval hash and character count must appear together")
    if approved_hash is not None and version < 1:
        raise StateError(f"{prefix} approval metadata requires draft_version >= 1")
    sent_key = message.get("sent_message_key")
    if sent_key is not None and (
        not isinstance(sent_key, str)
        or not SENT_MESSAGE_KEY_RE.fullmatch(sent_key)
    ):
        raise StateError(
            f"{prefix}.sent_message_key must be a stable single-line key or null"
        )
    if send_state != "sent_verified" and sent_key is not None:
        raise StateError(
            f"{prefix}.sent_message_key is valid only for send_state=sent_verified"
        )

    warnings: list[str] = []
    if decision == "pending":
        if send_state != "not_applicable" or version != 0 or approved_hash is not None:
            raise StateError(f"{prefix} pending decision has reply state")
        if message["ui_disposition_verified"]:
            raise StateError(f"{prefix} pending decision cannot be UI-verified")
    elif decision in {"leave_unread", "mark_read"}:
        if send_state != "not_applicable" or approved_hash is not None:
            raise StateError(f"{prefix} non-reply decision has reply state")
    else:
        if send_state == "not_applicable":
            raise StateError(f"{prefix} reply must have a dispatch state")
        if send_state in {"ack_pending", "sent_verified", "ambiguous", "failed"}:
            if approved_hash is None or version < 1:
                raise StateError(f"{prefix} dispatched reply lacks an approved draft")
        if send_state == "sent_verified":
            if not sent_key:
                raise StateError(f"{prefix} verified send lacks sent_message_key")
            if not message["ui_disposition_verified"]:
                raise StateError(f"{prefix} verified send lacks rendered UI verification")
        elif message["ui_disposition_verified"]:
            raise StateError(f"{prefix} reply is UI-verified before sent_verified")
        if send_state == "failed" and message["readonly_seen"] is not True:
            raise StateError(
                f"{prefix} definitive failed send requires a fresh rendered read"
            )
    if legacy_reconciliation and (
        decision != "reply"
        or send_state not in {"ack_pending", "ambiguous", "sent_verified"}
    ):
        raise StateError(
            f"{prefix}.legacy_send_reconciliation is valid only for a dispatched legacy reply"
        )
    return warnings


def validate_key_list(value: Any, field: str, seen: set[str]) -> list[str]:
    if not isinstance(value, list) or any(
        not isinstance(key, str) or key not in seen for key in value
    ):
        raise StateError(f"{field} must contain only snapshot message keys")
    if len(value) != len(set(value)):
        raise StateError(f"{field} must not contain duplicates")
    return value


def validate_ui_operation(value: Any, seen: set[str]) -> None:
    if value is None:
        return
    if not isinstance(value, dict):
        raise StateError("ui_operation must be an object or null")
    key = require_identity_string(value.get("key"), "ui_operation.key")
    if key not in seen:
        raise StateError("ui_operation.key must identify a snapshot message")
    operation = value.get("operation")
    if operation not in UI_OPERATIONS:
        raise StateError(f"ui_operation.operation must be one of {sorted(UI_OPERATIONS)}")
    intended_decision = value.get("intended_decision")
    expected_decision = {
        "leave_unread": "leave_unread",
        "mark_read": "mark_read",
        "send": "reply",
        "inspect_send": "reply",
    }.get(operation)
    if intended_decision not in DECISIONS:
        raise StateError(
            f"ui_operation.intended_decision must be one of {sorted(DECISIONS)}"
        )
    if expected_decision is not None and intended_decision != expected_decision:
        raise StateError(
            "ui_operation must bind to the disposition that the operation implements"
        )
    binding_trusted = value.get("binding_trusted")
    if not isinstance(binding_trusted, bool):
        raise StateError("ui_operation.binding_trusted must be boolean")
    bound_version = value.get("draft_version")
    bound_hash = value.get("approved_sha256")
    if operation in {"send", "inspect_send"}:
        if not is_exact_int(bound_version, minimum=1):
            raise StateError(
                "a send or inspection UI operation must bind a positive draft_version"
            )
        if not isinstance(bound_hash, str) or not SHA256_RE.fullmatch(bound_hash):
            raise StateError(
                "a send or inspection UI operation must bind an approved SHA-256"
            )
    elif bound_version is not None or bound_hash is not None:
        raise StateError("non-send UI operations cannot bind a draft")
    if value.get("state") not in UI_OPERATION_STATES:
        raise StateError(
            f"ui_operation.state must be one of {sorted(UI_OPERATION_STATES)}"
        )
    attempts = value.get("attempts")
    if not isinstance(attempts, list) or not 1 <= len(attempts) <= MAX_UI_ATTEMPTS:
        raise StateError(
            f"ui_operation.attempts must contain 1 to {MAX_UI_ATTEMPTS} attempts"
        )
    strategies: list[str] = []
    for index, attempt in enumerate(attempts):
        prefix = f"ui_operation.attempts[{index}]"
        if not isinstance(attempt, dict):
            raise StateError(f"{prefix} must be an object")
        if type(attempt.get("attempt")) is not int or attempt.get("attempt") != index + 1:
            raise StateError(f"{prefix}.attempt must be {index + 1}")
        strategy = require_string(attempt.get("strategy"), f"{prefix}.strategy")
        if not STRATEGY_RE.fullmatch(strategy):
            raise StateError(f"{prefix}.strategy must be a short stable identifier")
        strategies.append(strategy)
        validate_ui_outcome_observation(
            attempt.get("outcome"),
            attempt.get("observed_state"),
            prefix,
        )
        if attempt.get("fresh_read") is not True:
            raise StateError(f"{prefix}.fresh_read must be true")
        parse_iso(require_string(attempt.get("at"), f"{prefix}.at"), f"{prefix}.at")
        if index < len(attempts) - 1 and attempt.get("outcome") != "failed":
            raise StateError(
                f"{prefix} must be failed before a later UI attempt may exist"
            )
    if len(strategies) == 2 and strategies[0] == strategies[1]:
        raise StateError("the alternate UI attempt must use a different strategy")
    last_outcome = attempts[-1]["outcome"]
    state = value["state"]
    if last_outcome == "succeeded" and state != "succeeded":
        raise StateError("a successful UI attempt must set ui_operation.state=succeeded")
    if last_outcome == "ambiguous":
        if state != "exhausted":
            raise StateError("an ambiguous UI attempt must exhaust its retry budget immediately")
    elif last_outcome != "succeeded":
        expected = "retry_available" if len(attempts) < MAX_UI_ATTEMPTS else "exhausted"
        if state != expected:
            raise StateError(f"failed UI attempt must set ui_operation.state={expected}")


def validate_checkpoint(value: Any, seen: set[str]) -> None:
    if value is None:
        return
    if not isinstance(value, dict):
        raise StateError("checkpoint must be an object or null")
    kind = value.get("kind")
    if kind not in {
        "ui_retry_exhausted",
        "stopped",
        "send_ack_pending",
        "send_ambiguous",
    }:
        raise StateError("checkpoint.kind is invalid")
    base_fields = {"kind", "key", "at", "read_cursor_restored"}
    expected_fields = (
        base_fields
        | {"operation", "attempts", "desired_state", "observed_state"}
        if kind == "ui_retry_exhausted"
        else base_fields
    )
    actual_fields = set(value)
    if actual_fields != expected_fields:
        extra = sorted(actual_fields - expected_fields)
        missing = sorted(expected_fields - actual_fields)
        details: list[str] = []
        if extra:
            details.append(f"kind-inapplicable fields {extra}")
        if missing:
            details.append(f"missing fields {missing}")
        raise StateError(
            f"checkpoint kind {kind!r} has " + "; ".join(details)
        )
    key = value.get("key")
    if key is not None:
        require_identity_string(key, "checkpoint.key")
        if key not in seen:
            raise StateError("checkpoint.key must be a snapshot key or null")
    parse_iso(require_string(value.get("at"), "checkpoint.at"), "checkpoint.at")
    if not isinstance(value.get("read_cursor_restored"), bool):
        raise StateError("checkpoint.read_cursor_restored must be boolean")
    if kind == "ui_retry_exhausted":
        if value.get("operation") not in UI_OPERATIONS - {"inspect_send"}:
            raise StateError("an exhausted checkpoint must identify its UI operation")
        attempts = value.get("attempts")
        if type(attempts) is not int:
            raise StateError("an exhausted checkpoint attempts must be an integer")
        single_ambiguous_operation = (
            value.get("observed_state") in {"ambiguous", "ui_changed", "other"}
            and attempts == 1
        )
        if attempts != MAX_UI_ATTEMPTS and not single_ambiguous_operation:
            raise StateError(
                "an exhausted checkpoint must record two attempts or one ambiguous operation"
            )
        desired_state = require_string(
            value.get("desired_state"), "checkpoint.desired_state"
        )
        if desired_state != value.get("operation"):
            raise StateError(
                "an exhausted checkpoint desired_state must equal its operation"
            )
        if value.get("observed_state") not in UI_OBSERVED_STATES:
            raise StateError("an exhausted checkpoint must record observed_state")


def validate_cursor_checkpoints(
    value: Any,
    seen: set[str],
    messages: list[dict[str, Any]],
) -> None:
    if not isinstance(value, list):
        raise StateError("read_cursor_checkpoints must be an array")
    for index, checkpoint in enumerate(value):
        prefix = f"read_cursor_checkpoints[{index}]"
        if not isinstance(checkpoint, dict):
            raise StateError(f"{prefix} must be an object")
        key = require_identity_string(checkpoint.get("key"), f"{prefix}.key")
        if key not in seen:
            raise StateError(f"{prefix}.key must identify a snapshot message")
        boundary = checkpoint.get("boundary_ts")
        if boundary != canonical_slack_timestamp(boundary, f"{prefix}.boundary_ts"):
            raise StateError(f"{prefix}.boundary_ts must be canonical Slack-style time")
        owner = next(message for message in messages if message["key"] == key)
        if boundary != owner.get("original_unread_boundary_ts"):
            raise StateError(
                f"{prefix}.boundary_ts must equal the owner's original unread boundary"
            )
        if checkpoint.get("state") not in {
            "active_unresolved",
            "verified_read",
            "verified_unread",
            "restored_unread",
        }:
            raise StateError(f"{prefix}.state is invalid")
        parse_iso(require_string(checkpoint.get("at"), f"{prefix}.at"), f"{prefix}.at")


def ui_operation_has_duplicate_risk(operation: Any) -> bool:
    """Return whether another send attempt could duplicate an earlier dispatch."""

    if (
        not isinstance(operation, dict)
        or operation.get("operation") not in {"send", "inspect_send"}
    ):
        return False
    attempts = operation.get("attempts")
    return bool(
        isinstance(attempts, list)
        and any(
            isinstance(attempt, dict)
            and attempt.get("outcome") in {"succeeded", "ambiguous"}
            for attempt in attempts
        )
    )


def ui_operation_has_unsafe_outcome(operation: Any) -> bool:
    """Return whether any recorded attempt may already have changed live state."""

    if not isinstance(operation, dict):
        return False
    attempts = operation.get("attempts")
    return bool(
        isinstance(attempts, list)
        and any(
            isinstance(attempt, dict)
            and attempt.get("outcome") in {"succeeded", "ambiguous"}
            for attempt in attempts
        )
    )


def ui_operation_all_definitively_failed(operation: Any) -> bool:
    """Return whether every attempt proves the target was not changed."""

    if not isinstance(operation, dict):
        return False
    attempts = operation.get("attempts")
    return bool(
        isinstance(attempts, list)
        and attempts
        and all(
            isinstance(attempt, dict)
            and attempt.get("outcome") == "failed"
            and attempt.get("observed_state")
            in {"selector_missing", "target_not_reached"}
            for attempt in attempts
        )
    )


def ui_retry_rearm_token(
    message: dict[str, Any], operation: dict[str, Any]
) -> str:
    seed = "\0".join(
        [
            "ui-retry-rearm",
            message["key"],
            operation["operation"],
            str(operation.get("draft_version") or 0),
            operation.get("approved_sha256") or "",
        ]
    )
    return hashlib.sha256(seed.encode("utf-8")).hexdigest()


def legacy_ui_retry_rearm_token(
    message: dict[str, Any], operation: dict[str, Any]
) -> str:
    """Return the pre-domain-separation token for safe migration checks only."""

    seed = "\0".join(
        [
            message["key"],
            operation["operation"],
            str(operation.get("draft_version") or 0),
            operation.get("approved_sha256") or "",
        ]
    )
    return hashlib.sha256(seed.encode("utf-8")).hexdigest()


def ui_retry_rearm_was_used(
    data: dict[str, Any],
    message: dict[str, Any],
    operation: dict[str, Any],
) -> bool:
    tokens = data["ui_retry_rearm_tokens"]
    return bool(
        ui_retry_rearm_token(message, operation) in tokens
        or legacy_ui_retry_rearm_token(message, operation) in tokens
    )


def failed_send_rearm_token(message: dict[str, Any]) -> str:
    """Bind the one duplicate-safe failed-send rearm to one exact approved draft."""

    seed = "\0".join(
        [
            "failed-send-rearm",
            message["key"],
            str(message["draft_version"]),
            message.get("approved_sha256") or "",
        ]
    )
    return hashlib.sha256(seed.encode("utf-8")).hexdigest()


def require_bound_ui_operation(
    data: dict[str, Any],
    message: dict[str, Any],
    operation_name: str,
    *,
    allowed_states: set[str],
    allowed_outcomes: set[str],
) -> dict[str, Any]:
    """Require fresh evidence for the exact key, disposition, and approved draft."""

    operation = data.get("ui_operation")
    if not isinstance(operation, dict):
        raise StateError(
            f"{operation_name} verification requires its exact recorded UI operation"
        )
    if operation.get("key") != message["key"]:
        raise StateError("UI verification belongs to a different snapshot item")
    if operation.get("operation") != operation_name:
        raise StateError(
            f"UI verification is for {operation.get('operation')!r}, not {operation_name!r}"
        )
    if operation.get("intended_decision") != message["decision"]:
        raise StateError("UI verification is bound to a different disposition")
    if operation.get("binding_trusted") is not True:
        raise StateError("legacy UI evidence lacks a trusted exact-operation binding")
    if operation_name == "send" and (
        operation.get("draft_version") != message.get("draft_version")
        or operation.get("approved_sha256") != message.get("approved_sha256")
    ):
        raise StateError("send verification is bound to a different approved draft")
    if operation.get("state") not in allowed_states:
        raise StateError(
            f"the exact {operation_name} UI operation is not in a verifiable state"
        )
    attempts = operation.get("attempts")
    final_outcome = attempts[-1].get("outcome") if isinstance(attempts, list) and attempts else None
    if final_outcome not in allowed_outcomes:
        raise StateError(
            f"the exact {operation_name} UI operation lacks an accepted outcome"
        )
    return operation


def ui_operation_matches_message(
    operation: Any,
    message: dict[str, Any],
    *,
    operation_names: set[str],
    final_outcomes: set[str],
    trusted: bool = True,
) -> bool:
    """Return whether UI evidence is exactly bound to one reply and draft."""

    if not isinstance(operation, dict):
        return False
    attempts = operation.get("attempts")
    final_outcome = (
        attempts[-1].get("outcome")
        if isinstance(attempts, list) and attempts
        else None
    )
    return bool(
        operation.get("key") == message.get("key")
        and operation.get("operation") in operation_names
        and operation.get("intended_decision") == message.get("decision") == "reply"
        and operation.get("draft_version") == message.get("draft_version")
        and operation.get("approved_sha256") == message.get("approved_sha256")
        and (not trusted or operation.get("binding_trusted") is True)
        and final_outcome in final_outcomes
    )


def validate_checkpoint_cross_binding(data: dict[str, Any]) -> None:
    """Bind a checkpoint to its exact owner, lifecycle, decision, and UI evidence."""

    checkpoint = data.get("checkpoint")
    operation = data.get("ui_operation")
    run_state = data["run_state"]
    owner_key = data.get("active_key") if run_state == "active" else data.get("resume_key")
    if checkpoint is None:
        if (
            run_state == "stopped"
            and data.get("resume_key") is not None
            and not message_is_complete(find_message(data, data["resume_key"]))
        ):
            raise StateError(
                "a stopped incomplete run requires its exact resume checkpoint"
            )
        if isinstance(operation, dict) and operation.get("state") == "exhausted":
            raise StateError("an exhausted UI operation requires its exact checkpoint")
        return
    if checkpoint.get("key") != owner_key or owner_key is None:
        raise StateError(
            "checkpoint must belong to the active or exact resume item"
        )
    message = find_message(data, owner_key)
    kind = checkpoint["kind"]

    def require_rendered_unread_restoration() -> None:
        if (
            message.get("materialized") is not True
            or owner_key not in data.get("presented_keys", [])
        ):
            return
        proofs = [
            proof
            for proof in data.get("read_cursor_checkpoints", [])
            if isinstance(proof, dict) and proof.get("key") == owner_key
        ]
        if not proofs or proofs[-1].get("state") != "restored_unread":
            raise StateError(
                "a stopped materialized owner requires its final restored_unread cursor proof"
            )

    if kind == "stopped":
        if run_state != "stopped" or data.get("resume_key") != owner_key:
            raise StateError("a stopped checkpoint requires a stopped exact-resume owner")
        if message_is_complete(message):
            raise StateError("a stopped checkpoint cannot own a resolved item")
        if message.get("send_state") in {"ack_pending", "ambiguous"}:
            raise StateError("a dispatched reply requires a send-specific checkpoint")
        if operation is not None and not (
            isinstance(operation, dict)
            and operation.get("key") == owner_key
            and operation.get("state") == "retry_available"
        ):
            raise StateError(
                "a stopped checkpoint may retain only its exact partial retry evidence"
            )
        if checkpoint.get("read_cursor_restored") is not True:
            raise StateError(
                "a stopped checkpoint must record rendered unread restoration"
            )
        if (
            message.get("materialized") is True
            and owner_key not in data.get("stopped_unread_keys", [])
        ):
            raise StateError(
                "a stopped materialized owner must be in stopped_unread_keys"
            )
        require_rendered_unread_restoration()
        return

    if kind == "ui_retry_exhausted":
        if not isinstance(operation, dict):
            raise StateError("an exhausted checkpoint requires its exact UI operation")
        attempts = operation.get("attempts")
        final_attempt = attempts[-1] if isinstance(attempts, list) and attempts else None
        if (
            operation.get("key") != owner_key
            or operation.get("operation") != checkpoint.get("operation")
            or operation.get("state") != "exhausted"
            or not isinstance(final_attempt, dict)
            or len(attempts) != checkpoint.get("attempts")
            or final_attempt.get("observed_state") != checkpoint.get("observed_state")
            or checkpoint.get("desired_state") != operation.get("operation")
        ):
            raise StateError(
                "an exhausted checkpoint must exactly match its UI operation"
            )
        if run_state == "stopped":
            if checkpoint.get("read_cursor_restored") is not True:
                raise StateError(
                    "a stopped exhausted checkpoint must record rendered unread restoration"
                )
            if (
                message.get("materialized") is True
                and owner_key not in data.get("stopped_unread_keys", [])
            ):
                raise StateError(
                    "a stopped exhausted materialized owner must be in stopped_unread_keys"
                )
            require_rendered_unread_restoration()
        elif checkpoint.get("read_cursor_restored") is not False:
            raise StateError(
                "an active exhausted checkpoint cannot claim unread restoration"
            )
        return

    if message.get("decision") != "reply":
        raise StateError("a send checkpoint requires a reply decision")
    legacy_reconciliation = message.get("legacy_send_reconciliation") is True
    trusted_send = ui_operation_matches_message(
        operation,
        message,
        operation_names={"send"},
        final_outcomes={"succeeded", "ambiguous"},
    )
    legacy_untrusted = legacy_reconciliation and (
        operation is None
        or (
            isinstance(operation, dict)
            and operation.get("binding_trusted") is not True
        )
    )

    restored = checkpoint.get("read_cursor_restored") is True
    if run_state == "active" and restored:
        raise StateError(
            "an active send checkpoint cannot retain a stopped unread-restoration claim"
        )
    if run_state == "stopped" and restored:
        if owner_key not in data.get("stopped_unread_keys", []):
            raise StateError(
                "a restored stopped send owner must be in stopped_unread_keys"
            )
        require_rendered_unread_restoration()

    if kind == "send_ack_pending":
        if message.get("send_state") != "ack_pending":
            raise StateError(
                "send_ack_pending checkpoint requires send_state=ack_pending"
            )
        if not (trusted_send or legacy_untrusted):
            raise StateError(
                "send_ack_pending checkpoint requires exact send evidence or legacy reconciliation"
            )
        return

    if kind == "send_ambiguous":
        trusted_inspection = ui_operation_matches_message(
            operation,
            message,
            operation_names={"inspect_send"},
            final_outcomes={"ambiguous"},
        )
        duplicate_risk_before_state_commit = (
            message.get("send_state") == "not_dispatched"
            and trusted_send
            and operation["attempts"][-1]["outcome"] == "ambiguous"
        )
        terminal_ambiguous = message.get("send_state") == "ambiguous" and (
            trusted_send or trusted_inspection or legacy_untrusted
        )
        if not (duplicate_risk_before_state_commit or terminal_ambiguous):
            raise StateError(
                "send_ambiguous checkpoint requires ambiguous send state or exact duplicate-risk evidence"
            )
        return

    raise StateError(f"unsupported checkpoint kind: {kind}")


def validate_state(data: dict[str, Any]) -> dict[str, Any]:
    validate_manifest_shape(data)
    if data.get("schema_version") != SCHEMA_VERSION:
        raise StateError(f"schema_version must be {SCHEMA_VERSION}")
    require_identity_string(data.get("session_id"), "session_id")
    require_identity_string(data.get("run_id"), "run_id")
    session_generation = data.get("session_generation")
    if not is_exact_int(session_generation, minimum=1):
        raise StateError("session_generation must be a positive integer")
    for field in ("snapshot_at", "created_at", "updated_at"):
        parse_iso(require_string(data.get(field), field), field)
    messages = data.get("messages")
    if not isinstance(messages, list):
        raise StateError("messages must be an array")

    seen: set[str] = set()
    logical_identities: dict[tuple[str, str, str], str] = {}
    sent_message_keys: dict[str, str] = {}
    for index, message in enumerate(messages):
        validate_message(message, index)
        key = message["key"]
        if key in seen:
            raise StateError(f"duplicate message key: {key}")
        seen.add(key)
        if message["materialized"]:
            identity = (
                message["workspace"],
                message["conversation"],
                message["message_ts"],
            )
            previous_key = logical_identities.get(identity)
            if previous_key is not None:
                raise StateError(
                    "duplicate logical Slack identity for "
                    f"{previous_key!r} and {key!r}: "
                    f"workspace={identity[0]!r}, conversation={identity[1]!r}, "
                    f"message_ts={identity[2]!r}"
                )
            logical_identities[identity] = key
        sent_key = message.get("sent_message_key")
        if sent_key is not None:
            previous_owner = sent_message_keys.get(sent_key)
            if previous_owner is not None:
                raise StateError(
                    "duplicate sent_message_key for "
                    f"{previous_owner!r} and {key!r}: {sent_key!r}"
                )
            sent_message_keys[sent_key] = key

    setup = data.get("setup")
    if not isinstance(setup, dict):
        raise StateError("setup must be an object")
    for field in ("references_loaded", "snapshot_frozen", "computer_use_initialized"):
        if not isinstance(setup.get(field), bool):
            raise StateError(f"setup.{field} must be boolean")

    run_state = data.get("run_state", "active")
    if run_state not in RUN_STATES:
        raise StateError(f"run_state must be one of {sorted(RUN_STATES)}")
    active_key = data.get("active_key")
    if active_key is not None:
        require_string(active_key, "active_key")
        if active_key not in seen:
            raise StateError("active_key must identify a message in the snapshot")
    if run_state == "stopped" and active_key is not None:
        raise StateError("a stopped run cannot retain an active_key")
    if active_key is not None and not setup["snapshot_frozen"]:
        raise StateError("an active item requires a frozen snapshot")

    prefetched_key = data.get("prefetched_key")
    if prefetched_key is not None:
        require_string(prefetched_key, "prefetched_key")
        if prefetched_key not in seen:
            raise StateError("prefetched_key must identify a message in the snapshot")
        if prefetched_key == active_key:
            raise StateError("prefetched_key cannot equal active_key")
        if active_key is None:
            raise StateError("prefetched_key requires an active_key")
    resume_key = data.get("resume_key")
    if resume_key is not None:
        require_string(resume_key, "resume_key")
        if resume_key not in seen:
            raise StateError("resume_key must identify a message in the snapshot")

    presented_keys = validate_key_list(data.get("presented_keys", []), "presented_keys", seen)
    stopped_unread_keys = validate_key_list(
        data.get("stopped_unread_keys", []), "stopped_unread_keys", seen
    )
    resolved_keys = validate_key_list(data.get("resolved_keys", []), "resolved_keys", seen)
    for field in ("ui_retry_rearm_tokens", "failed_send_rearm_tokens"):
        rearm_tokens = data.get(field)
        if (
            not isinstance(rearm_tokens, list)
            or any(
                not isinstance(token, str) or not SHA256_RE.fullmatch(token)
                for token in rearm_tokens
            )
            or len(rearm_tokens) != len(set(rearm_tokens))
        ):
            raise StateError(f"{field} must contain unique SHA-256 tokens")
    if presented_keys and not setup["snapshot_frozen"]:
        raise StateError("presented items require a frozen snapshot")
    if run_state == "active" and resume_key is not None:
        raise StateError("an active run cannot retain resume_key")
    for key in resolved_keys:
        if not message_is_complete(find_message(data, key)):
            raise StateError(f"resolved key {key!r} has not crossed its verification gate")
    complete_keys = {message["key"] for message in messages if message_is_complete(message)}
    if complete_keys != set(resolved_keys):
        missing = sorted(complete_keys - set(resolved_keys))
        raise StateError(f"verified messages missing from resolved_keys: {missing}")
    if active_key in resolved_keys:
        raise StateError("a resolved key cannot remain active")
    if prefetched_key in resolved_keys:
        raise StateError("a resolved key cannot remain prefetched")

    message_order = [message["key"] for message in messages]
    unresolved_keys = [
        message["key"]
        for message in messages
        if message["key"] not in resolved_keys
    ]
    if resolved_keys != message_order[: len(resolved_keys)]:
        raise StateError("resolved_keys must be the completed frozen-order prefix")
    if active_key is not None:
        if not unresolved_keys or active_key != unresolved_keys[0]:
            raise StateError(
                "active_key must be the first unresolved item in frozen snapshot order"
            )
        expected_prefetch = (
            unresolved_keys[1] if len(unresolved_keys) > 1 else None
        )
        if prefetched_key != expected_prefetch:
            raise StateError(
                "prefetched_key must be the immediate unresolved successor"
            )
    elif prefetched_key is not None:
        raise StateError("prefetched_key requires an exact active owner")
    elif run_state == "active" and any(
        key in presented_keys for key in unresolved_keys
    ):
        raise StateError(
            "an active run cannot lose the owner of a presented unresolved item"
        )
    if run_state == "stopped" and resume_key is not None:
        if not unresolved_keys or resume_key != unresolved_keys[0]:
            raise StateError(
                "resume_key must be the first unresolved item in frozen snapshot order"
            )
    presented_owner = active_key if run_state == "active" else resume_key
    expected_presented = list(resolved_keys)
    if presented_owner is not None and presented_owner in presented_keys:
        expected_presented.append(presented_owner)
    if presented_keys != expected_presented:
        raise StateError(
            "presented_keys must be exactly the resolved prefix plus its current owner"
        )
    if active_key is not None and active_key not in presented_keys:
        raise StateError("active_key must already be recorded in presented_keys")
    validate_decision_lane(data, seen)

    transition_seq = data.get("transition_seq")
    if not is_exact_int(transition_seq, minimum=0):
        raise StateError("transition_seq must be a non-negative integer")
    transition_log = data.get("transition_log")
    if not isinstance(transition_log, list) or len(transition_log) > MAX_TRANSITION_LOG:
        raise StateError(f"transition_log must be an array of at most {MAX_TRANSITION_LOG}")
    previous_seq = 0
    for index, event in enumerate(transition_log):
        prefix = f"transition_log[{index}]"
        if not isinstance(event, dict):
            raise StateError(f"{prefix} must be an object")
        seq = event.get("seq")
        if not is_exact_int(seq, minimum=1) or seq <= previous_seq:
            raise StateError(f"{prefix}.seq must increase monotonically")
        previous_seq = seq
        key = event.get("key")
        if key is not None and (not isinstance(key, str) or key not in seen):
            raise StateError(f"{prefix}.key must be a snapshot key or null")
        event_name = require_string(event.get("event"), f"{prefix}.event")
        if not STRATEGY_RE.fullmatch(event_name):
            raise StateError(f"{prefix}.event must be a short stable identifier")
        parse_iso(require_string(event.get("at"), f"{prefix}.at"), f"{prefix}.at")
        fields = event.get("fields")
        if fields is not None and (
            not isinstance(fields, list)
            or any(
                not isinstance(field, str) or field not in SETUP_FIELDS
                for field in fields
            )
            or len(fields) != len(set(fields))
        ):
            raise StateError(f"{prefix}.fields must contain only unique setup fields")
        for field, allowed in (
            ("decision", DECISIONS),
            ("intended_decision", DECISIONS),
            ("send_state", SEND_STATES),
            ("from_send_state", SEND_STATES),
            ("operation", UI_OPERATIONS),
            ("outcome", UI_OUTCOMES),
            ("retry_state", UI_OPERATION_STATES),
        ):
            if field in event and event[field] not in allowed:
                raise StateError(f"{prefix}.{field} is invalid")
        if "attempt" in event and (
            type(event["attempt"]) is not int
            or not 1 <= event["attempt"] <= MAX_UI_ATTEMPTS
        ):
            raise StateError(f"{prefix}.attempt is invalid")
        if "draft_version" in event and (
            type(event["draft_version"]) is not int
            or event["draft_version"] < 0
        ):
            raise StateError(f"{prefix}.draft_version is invalid")
    if transition_log and transition_seq != transition_log[-1]["seq"]:
        raise StateError("transition_seq must equal the final transition log sequence")
    if not transition_log and transition_seq != 0:
        raise StateError("transition_seq must be zero when transition_log is empty")

    validate_ui_operation(data.get("ui_operation"), seen)
    ui_operation = data.get("ui_operation")
    if isinstance(ui_operation, dict):
        owner_key = active_key if run_state == "active" else resume_key
        if ui_operation["key"] != owner_key:
            raise StateError(
                "ui_operation must belong to the active or exact resume item"
            )
        owner = find_message(data, ui_operation["key"])
        if ui_operation["intended_decision"] != owner["decision"]:
            raise StateError("ui_operation is bound to a stale item disposition")
        if (
            ui_operation["operation"] in {"send", "inspect_send"}
            and ui_operation["binding_trusted"]
        ):
            if (
                ui_operation["draft_version"] != owner["draft_version"]
                or ui_operation["approved_sha256"] != owner["approved_sha256"]
            ):
                raise StateError("ui_operation is bound to a stale approved draft")
        stopped_duplicate_gate = (
            ui_operation["operation"] == "send"
            and owner["send_state"] in {
                "not_dispatched",
                "ack_pending",
                "ambiguous",
            }
            and ui_operation_has_duplicate_risk(ui_operation)
        )
        if (
            run_state == "stopped"
            and ui_operation["state"] not in {"retry_available", "exhausted"}
            and not stopped_duplicate_gate
        ):
            raise StateError(
                "only partial, exhausted, or duplicate-suppressed UI evidence may persist while stopped"
            )
        if ui_operation["key"] in resolved_keys:
            raise StateError("a resolved item cannot retain a UI operation")
    ui_operation_history = data.get("ui_operation_history")
    if not isinstance(ui_operation_history, list):
        raise StateError("ui_operation_history must be an array")
    if len(ui_operation_history) > max(1, len(messages) * 4):
        raise StateError("ui_operation_history exceeds its bounded snapshot limit")
    historical_identities: set[tuple[Any, ...]] = set()
    for index, historical in enumerate(ui_operation_history):
        validate_ui_operation(historical, seen)
        if not ui_operation_all_definitively_failed(historical):
            raise StateError(
                f"ui_operation_history[{index}] must contain only definitive failures"
            )
        if historical["key"] in resolved_keys:
            raise StateError("a resolved item cannot retain historical UI evidence")
        identity = (
            historical["key"],
            historical["operation"],
            historical.get("draft_version"),
            historical.get("approved_sha256"),
        )
        if identity in historical_identities:
            raise StateError("ui_operation_history must not contain duplicate epochs")
        historical_identities.add(identity)
        if isinstance(ui_operation, dict) and identity == (
            ui_operation["key"],
            ui_operation["operation"],
            ui_operation.get("draft_version"),
            ui_operation.get("approved_sha256"),
        ):
            raise StateError("current and historical UI evidence cannot share an epoch")
    validate_checkpoint(data.get("checkpoint"), seen)
    validate_checkpoint_cross_binding(data)
    checkpoint = data.get("checkpoint")
    current_owner_key = active_key if run_state == "active" else resume_key
    for message in messages:
        if message["send_state"] not in {"ack_pending", "ambiguous"}:
            continue
        if message["key"] != current_owner_key:
            raise StateError(
                "an unresolved dispatched reply must remain the active or exact resume item"
            )
        expected_kind = (
            "send_ack_pending"
            if message["send_state"] == "ack_pending"
            else "send_ambiguous"
        )
        if not (
            isinstance(checkpoint, dict)
            and checkpoint.get("kind") == expected_kind
            and checkpoint.get("key") == message["key"]
        ):
            raise StateError(
                f"{message['send_state']} requires an exact {expected_kind} checkpoint"
            )
    cursor_checkpoints = data.get("read_cursor_checkpoints")
    validate_cursor_checkpoints(cursor_checkpoints, seen, messages)
    for key in resolved_keys:
        message = find_message(data, key)
        expected_state = (
            "verified_unread"
            if message["decision"] == "leave_unread"
            else "verified_read"
        )
        owner_proofs = [
            item
            for item in cursor_checkpoints
            if item.get("key") == key
        ]
        proof_matches = bool(
            owner_proofs
            and (
                owner_proofs[-1].get("state") == expected_state
                or (
                    expected_state == "verified_unread"
                    and owner_proofs[-1].get("state") == "restored_unread"
                    and any(
                        proof.get("state") == "verified_unread"
                        for proof in owner_proofs
                    )
                )
            )
        )
        if not proof_matches:
            raise StateError(
                f"resolved key {key!r} requires final cursor proof {expected_state!r}"
            )
    for message in messages:
        if message["key"] in resolved_keys:
            continue
        if any(
            item.get("key") == message["key"]
            and item.get("state") in {"verified_read", "verified_unread"}
            for item in cursor_checkpoints
        ):
            raise StateError(
                f"unresolved key {message['key']!r} cannot retain final cursor proof"
            )
    stopped_at = data.get("stopped_at")
    if stopped_at is not None:
        parse_iso(require_string(stopped_at, "stopped_at"), "stopped_at")
    if run_state == "stopped" and stopped_at is None:
        raise StateError("a stopped run must have stopped_at")
    if run_state == "active" and stopped_at is not None:
        raise StateError("an active run cannot have stopped_at")
    if run_state == "stopped" and resume_key is None and any(
        not message_is_complete(message) for message in messages
    ):
        raise StateError("a stopped incomplete run must have resume_key")

    warnings: list[dict[str, Any]] = []
    cursor_reconciliation_pending = False
    groups: dict[tuple[str, str], list[dict[str, Any]]] = {}
    for message in messages:
        groups.setdefault((message["workspace"], message["conversation"]), []).append(message)
    for (workspace, conversation), group in groups.items():
        if any(item["decision"] == "leave_unread" and not item["materialized"]
               for item in group):
            cursor_reconciliation_pending = True
            warnings.append({"kind": "unbound_unread_intent", "workspace": workspace,
                             "conversation": conversation})
        unread_items = [
            item for item in group if item["decision"] == "leave_unread" and item["materialized"]
        ]
        earliest_unread = (
            min(
                unread_items,
                key=lambda item: slack_timestamp_value(
                    item["original_unread_boundary_ts"],
                    "original_unread_boundary_ts",
                ),
            )
            if unread_items
            else None
        )
        if earliest_unread is None:
            continue
        unread_boundary = slack_timestamp_value(
            earliest_unread["original_unread_boundary_ts"],
            "original_unread_boundary_ts",
        )
        collateral = [
            item["key"]
            for item in group
            if item["decision"] in {"mark_read", "reply"}
            and item.get("message_ts") is not None
            and slack_timestamp_value(item["message_ts"], "message_ts")
            > unread_boundary
        ]
        if collateral:
            group_keys = {item["key"] for item in group}
            group_proofs = [
                proof
                for proof in cursor_checkpoints
                if proof.get("key") in group_keys
            ]
            latest_group_proof = group_proofs[-1] if group_proofs else None
            reconciled = bool(
                isinstance(latest_group_proof, dict)
                and latest_group_proof.get("key") == earliest_unread["key"]
                and latest_group_proof.get("state") == "restored_unread"
                and latest_group_proof.get("boundary_ts")
                == earliest_unread["original_unread_boundary_ts"]
            )
            cursor_reconciliation_pending = (
                cursor_reconciliation_pending or not reconciled
            )
            warnings.append(
                {
                    "kind": "read_cursor_collateral",
                    "workspace": workspace,
                    "conversation": conversation,
                    "unread_anchor": earliest_unread["key"],
                    "processed_later_keys": collateral,
                    "cursor_reconciled": reconciled,
                }
            )

    counts = {decision: 0 for decision in sorted(DECISIONS)}
    counts.update({"sent_verified": 0, "unresolved_replies": 0})
    incomplete: list[str] = []
    for message in messages:
        counts[message["decision"]] += 1
        if message["send_state"] == "sent_verified":
            counts["sent_verified"] += 1
        if message["decision"] == "pending":
            incomplete.append(message["key"])
        elif message["decision"] in {"leave_unread", "mark_read"}:
            if not message["ui_disposition_verified"]:
                incomplete.append(message["key"])
        elif message["send_state"] != "sent_verified":
            counts["unresolved_replies"] += 1
            incomplete.append(message["key"])

    return {
        "ok": True,
        "schema_version": SCHEMA_VERSION,
        "run_id": data["run_id"],
        "session_id": data["session_id"],
        "session_generation": session_generation,
        "run_state": run_state,
        "active_key": active_key,
        **decision_lane_payload(data),
        "prefetched_key": prefetched_key,
        "resume_key": resume_key,
        "resolved_keys": list(resolved_keys),
        "setup": dict(setup),
        "checkpoint": data.get("checkpoint"),
        "ui_operation": data.get("ui_operation"),
        "snapshot_total": len(messages),
        "state": (
            "snapshot_verified"
            if setup["snapshot_frozen"]
            and not incomplete
            and not cursor_reconciliation_pending
            and (
                not messages
                or (
                    setup["references_loaded"]
                    and setup["computer_use_initialized"]
                )
            )
            else "in_progress"
        ),
        "counts": counts,
        "incomplete_keys": incomplete,
        "warnings": warnings,
    }


def find_message(data: dict[str, Any], key: str) -> dict[str, Any]:
    matches = [message for message in data["messages"] if message.get("key") == key]
    if len(matches) != 1:
        raise StateError(f"expected exactly one message with key {key!r}")
    return matches[0]


def mutate(path: Path, callback) -> dict[str, Any]:
    with exclusive_manifest_lock(path) as lock_guard:
        data, state_identity = read_state_bound(path)
        validate_state(data)
        changed = callback(data)
        if changed is False:
            result = validate_state(data)
            # A semantic no-op still consumed a transaction against one exact
            # manifest inode.  Recheck both the retained lock and state path
            # before returning so a concurrent replacement cannot make stale
            # state look authoritative to the caller.
            lock_guard()
            assert_manifest_identity(path, state_identity)
            return result
        data["updated_at"] = now_iso()
        result = validate_state(data)

        def precommit_guard() -> None:
            lock_guard()
            assert_manifest_identity(path, state_identity)

        committed_identity = atomic_write(
            path, data, precommit_guard=precommit_guard
        )
        lock_guard()
        assert_manifest_identity(path, committed_identity)
        return result


def new_snapshot(args: argparse.Namespace) -> dict[str, Any]:
    parse_iso(args.snapshot_at, "snapshot_at")
    timestamp = now_iso()
    session_id = require_identity_string(args.session_id, "session_id")
    run_id = require_identity_string(
        getattr(args, "run_id", None) or session_id,
        "run_id",
    )
    data = {
        "schema_version": SCHEMA_VERSION,
        "run_id": run_id,
        "session_id": session_id,
        "session_generation": 1,
        "snapshot_at": args.snapshot_at,
        "created_at": timestamp,
        "updated_at": timestamp,
        "setup": {
            "references_loaded": False,
            "snapshot_frozen": False,
            "computer_use_initialized": False,
        },
        "run_state": "active",
        "active_key": None,
        "prefetched_key": None,
        "resume_key": None,
        "presented_keys": [],
        "resolved_keys": [],
        "stopped_at": None,
        "stopped_unread_keys": [],
        "transition_seq": 0,
        "transition_log": [],
        "ui_operation": None,
        "ui_operation_history": [],
        "checkpoint": None,
        "read_cursor_checkpoints": [],
        "ui_retry_rearm_tokens": [],
        "failed_send_rearm_tokens": [],
        "messages": [],
    }
    return data


def cmd_new(args: argparse.Namespace) -> dict[str, Any]:
    path = manifest_path(args.file)
    with exclusive_manifest_lock(path) as lock_guard:
        assert_manifest_absent(path)
        data = new_snapshot(args)
        result = validate_state(data)

        def precommit_guard() -> None:
            lock_guard()
            assert_manifest_absent(path)

        committed_identity = atomic_write(
            path, data, precommit_guard=precommit_guard
        )
        lock_guard()
        assert_manifest_identity(path, committed_identity)
        return result


def synthetic_snapshot_key(
    data: dict[str, Any], workspace: str, conversation: str, surface: str
) -> str:
    ordinal = len(data["messages"]) + 1
    seed = "\0".join(
        [data["run_id"], str(ordinal), workspace, conversation, surface]
    )
    digest = hashlib.sha256(seed.encode("utf-8")).hexdigest()[:16]
    return f"snapshot:{ordinal:04d}:{digest}"


def add_snapshot_row(data: dict[str, Any], args: argparse.Namespace) -> dict[str, Any]:
    if data["run_state"] != "active":
        raise StateError("cannot add an item to a stopped run")
    if data["setup"]["snapshot_frozen"]:
        raise StateError("cannot add an item after the unread snapshot is frozen")
    workspace = require_identity_string(args.workspace, "workspace")
    conversation = require_identity_string(args.conversation, "conversation")
    key_arg = getattr(args, "key", None)
    key = (
        require_identity_string(key_arg, "key")
        if key_arg is not None
        else synthetic_snapshot_key(data, workspace, conversation, args.surface)
    )
    if any(message.get("key") == key for message in data["messages"]):
        raise StateError(f"duplicate message key: {key}")
    raw_message_ts = getattr(args, "message_ts", None)
    raw_boundary_ts = getattr(args, "unread_boundary_ts", None)
    message_ts = (
        canonical_slack_timestamp(raw_message_ts, "message_ts")
        if raw_message_ts is not None
        else None
    )
    boundary_ts = (
        canonical_slack_timestamp(raw_boundary_ts, "unread_boundary_ts")
        if raw_boundary_ts is not None
        else None
    )
    materialized = message_ts is not None
    if not materialized and boundary_ts is not None:
        raise StateError("--unread-boundary-ts requires --message-ts")
    if not materialized and args.thread_key is not None:
        raise StateError("--thread-key requires --message-ts")
    thread_key = (
        require_identity_string(args.thread_key, "thread_key")
        if args.thread_key is not None
        else None
    )
    data["messages"].append(
        {
            "key": key,
            "workspace": workspace,
            "conversation": conversation,
            "surface": args.surface,
            "message_ts": message_ts,
            "thread_key": thread_key,
            "original_unread": True,
            "original_unread_boundary_ts": (
                (boundary_ts or message_ts) if materialized else None
            ),
            "materialized": materialized,
            "decision": "pending",
            "draft_version": 0,
            "approved_sha256": None,
            "approved_chars": None,
            "send_state": "not_applicable",
            "sent_message_key": None,
            "legacy_send_reconciliation": False,
            "readonly_seen": False,
            "ui_disposition_verified": False,
        }
    )
    return {"added_key": key, "materialized": materialized}


def cmd_add(args: argparse.Namespace) -> dict[str, Any]:
    added: dict[str, Any] = {}

    def callback(data: dict[str, Any]) -> None:
        added.update(add_snapshot_row(data, args))

    result = mutate(manifest_path(args.file), callback)
    result.update(added)
    return result


def disposition_complete(message: dict[str, Any]) -> bool:
    """Return whether an item has crossed its live verification gate."""
    return message_is_complete(message)


def card_payload(message: dict[str, Any] | None) -> dict[str, Any] | None:
    """Return the body-free identity safe to present or prefetch."""

    if message is None:
        return None
    return {
        "key": message["key"],
        "workspace": message["workspace"],
        "conversation": message["conversation"],
        "surface": message["surface"],
        "message_ts": message["message_ts"],
        "thread_key": message["thread_key"],
        "decision": message["decision"],
        "draft_version": message["draft_version"],
        "approved_sha256": message["approved_sha256"],
        "approved_chars": message["approved_chars"],
        "send_state": message["send_state"],
        "ui_disposition_verified": message["ui_disposition_verified"],
        "readonly_seen": message["readonly_seen"],
        "legacy_send_reconciliation": message["legacy_send_reconciliation"],
    }


def validate_decision_lane(data: dict[str, Any], seen: set[str]) -> None:
    """The decision cursor may lead; the legacy mutation owner never skips."""
    if "decision_lane" not in data:
        return  # Existing manifests keep their serialized interaction contract.
    lane = data["decision_lane"]
    if not isinstance(lane, dict) or set(lane) != DECISION_LANE_FIELDS:
        raise StateError("decision_lane requires its exact body-free fields")
    if not data["setup"]["snapshot_frozen"] or not data["setup"]["references_loaded"]:
        raise StateError("decision_lane requires a frozen snapshot and loaded references")
    submitted = validate_key_list(lane["submitted_keys"], "submitted_keys", seen)
    order = [item["key"] for item in data["messages"]]
    if submitted != order[:len(submitted)]:
        raise StateError("submitted_keys must be the frozen-order decision prefix")
    expected = order[len(submitted)] if len(submitted) < len(order) else None
    if lane["current_key"] != expected:
        raise StateError("decision cursor must follow the submitted prefix")
    if not set(data["resolved_keys"]).issubset(submitted):
        raise StateError("only submitted decisions may resolve")
    accounts = lane["workspace_accounts"]
    if not isinstance(accounts, dict) or set(accounts) != {m["workspace"] for m in data["messages"]}:
        raise StateError("workspace_accounts must bind every snapshot workspace exactly")
    for workspace, account in accounts.items():
        require_identity_string(workspace, "workspace_accounts workspace")
        require_identity_string(account, "workspace_accounts account")
    for message in data["messages"]:
        key = message["key"]
        if key in submitted and message["decision"] == "pending":
            raise StateError("submitted items require a recorded decision")
        if key not in submitted and key != expected and message["decision"] != "pending":
            raise StateError("an unseen successor cannot have a decision")
    operation = data.get("ui_operation")
    if operation is not None and operation["key"] not in submitted:
        raise StateError("the mutation lane requires a submitted decision")


def decision_lane_payload(data: dict[str, Any]) -> dict[str, Any]:
    lane = data.get("decision_lane")
    if lane is None:
        return {}
    key = lane["current_key"]
    mutation_key = data.get("active_key") or data.get("resume_key")
    return {
        "decision_key": key,
        "decision_card": card_payload(find_message(data, key)) if key else None,
        "queued_keys": [k for k in lane["submitted_keys"] if k not in data["resolved_keys"]],
        "mutation_key": mutation_key,
        "mutation_card": card_payload(find_message(data, mutation_key)) if mutation_key else None,
    }


def require_decision_owner(data: dict[str, Any], args: argparse.Namespace) -> None:
    lane = data.get("decision_lane")
    if data["run_state"] != "active":
        raise StateError("cannot change a decision in a stopped run")
    owner = lane["current_key"] if lane is not None else data.get("active_key")
    correction = bool(
        lane is not None and getattr(args, "queued_correction", False)
        and args.key in lane["submitted_keys"] and args.key not in data["resolved_keys"]
    )
    if args.key != owner and not correction:
        raise StateError("decision/approval applies only to the visible decision card; queued corrections require an explicit key")


def require_submitted(data: dict[str, Any], key: str) -> None:
    lane = data.get("decision_lane")
    if lane is not None and key not in lane["submitted_keys"]:
        raise StateError("queue the exact decision before using the mutation lane")


def cmd_bootstrap(args: argparse.Namespace) -> dict[str, Any]:
    """Validate one shallow body-free snapshot and publish it in one transaction."""
    args.snapshot_at = args.snapshot_at or now_iso()
    try:
        snapshot_time = datetime.fromisoformat(args.snapshot_at.replace("Z", "+00:00"))
        if snapshot_time.tzinfo is None or snapshot_time.timestamp() > time.time() + 60:
            raise ValueError("unbound or future snapshot time")
    except (ValueError, TypeError) as exc:
        raise StateError("snapshot-at must be timezone-aware and not in the future; omit it to use the clock") from exc
    raw = sys.stdin.read(MAX_MANIFEST_BYTES + 1)
    if len(raw.encode("utf-8")) > MAX_MANIFEST_BYTES:
        raise StateError("bootstrap input exceeds the manifest byte limit")
    try:
        snapshot = json.loads(raw, object_pairs_hook=reject_duplicate_json_keys,
                              parse_int=parse_bounded_json_int, parse_float=reject_json_float,
                              parse_constant=reject_nonfinite_json)
    except (ValueError, RecursionError) as exc:
        raise StateError("invalid bounded bootstrap JSON") from exc
    validate_json_structure_limits(snapshot)
    if not isinstance(snapshot, dict) or set(snapshot) != {"items", "workspace_accounts"}:
        raise StateError("bootstrap requires only items and workspace_accounts")
    if not isinstance(snapshot["items"], list):
        raise StateError("bootstrap items must be an array")
    if not args.references_loaded:
        raise StateError("bootstrap requires --references-loaded after reading the protocol")
    data = new_snapshot(args)
    for row in snapshot["items"]:
        if not isinstance(row, dict):
            raise StateError("bootstrap rows must be body-free objects")
        require_allowed_fields(row, SNAPSHOT_ROW_FIELDS, "bootstrap row")
        if not {"workspace", "conversation", "surface"}.issubset(row):
            raise StateError("bootstrap row requires workspace, conversation and surface")
        fields = {name: row.get(name) for name in SNAPSHOT_ROW_FIELDS}
        add_snapshot_row(data, argparse.Namespace(**fields))
    data["setup"].update(references_loaded=True, snapshot_frozen=True,
                         computer_use_initialized=bool(args.computer_use_initialized))
    first = data["messages"][0] if data["messages"] else None
    data["decision_lane"] = {"current_key": first["key"] if first else None,
                             "submitted_keys": [], "workspace_accounts": snapshot["workspace_accounts"]}
    if first is not None:
        activate_message(data, first)
    result = validate_state(data)
    path = manifest_path(args.file)
    with exclusive_manifest_lock(path) as lock_guard:
        assert_manifest_absent(path)

        def precommit_guard() -> None:
            lock_guard()
            assert_manifest_absent(path)

        identity = atomic_write(path, data, precommit_guard=precommit_guard)
        lock_guard()
        assert_manifest_identity(path, identity)
    result["card"] = result["decision_card"]
    return result


def submit_decision(data: dict[str, Any], args: argparse.Namespace) -> None:
    lane = data.get("decision_lane")
    if lane is None:
        raise StateError("queue-decision requires a bootstrapped decision lane")
    require_decision_owner(data, args)
    record_decision(data, args)
    message = find_message(data, args.key)
    if message["decision"] == "reply" and message["approved_sha256"] is None:
        raise StateError("present and explicitly approve the exact reply before queueing it")
    lane["submitted_keys"].append(args.key)
    count = len(lane["submitted_keys"])
    lane["current_key"] = data["messages"][count]["key"] if count < len(data["messages"]) else None
    append_transition(data, "decision_queued", args.key, decision=args.decision)


def cmd_queue_decision(args: argparse.Namespace) -> dict[str, Any]:
    def callback(data: dict[str, Any]) -> None:
        submit_decision(data, args)

    result = mutate(manifest_path(args.file), callback)
    result["queued_key"] = args.key
    result["next_card"] = result["decision_card"]
    return result


def append_transition(
    data: dict[str, Any], event: str, key: str | None = None, **details: Any
) -> None:
    data["transition_seq"] += 1
    entry: dict[str, Any] = {
        "seq": data["transition_seq"],
        "event": event,
        "key": key,
        "at": now_iso(),
    }
    for name, value in details.items():
        if value is not None:
            entry[name] = value
    data["transition_log"].append(entry)
    if len(data["transition_log"]) > MAX_TRANSITION_LOG:
        data["transition_log"] = data["transition_log"][-MAX_TRANSITION_LOG:]


def append_cursor_checkpoint(
    data: dict[str, Any], message: dict[str, Any], state: str
) -> None:
    if not message["materialized"]:
        raise StateError("cannot checkpoint a read cursor before materialization")
    data["read_cursor_checkpoints"].append(
        {
            "key": message["key"],
            "boundary_ts": message["original_unread_boundary_ts"],
            "state": state,
            "at": now_iso(),
        }
    )


def unresolved_messages(data: dict[str, Any]) -> list[dict[str, Any]]:
    resolved = set(data["resolved_keys"])
    return [message for message in data["messages"] if message["key"] not in resolved]


def refresh_prefetch(data: dict[str, Any]) -> None:
    """Cache at most one body-free successor without presenting/opening it."""

    active_key = data.get("active_key")
    if active_key is None:
        data["prefetched_key"] = None
        return
    unresolved = unresolved_messages(data)
    keys = [message["key"] for message in unresolved]
    try:
        index = keys.index(active_key)
    except ValueError:
        data["prefetched_key"] = None
        return
    data["prefetched_key"] = keys[index + 1] if index + 1 < len(keys) else None


def activate_message(
    data: dict[str, Any], message: dict[str, Any], *, event: str = "activated"
) -> None:
    key = message["key"]
    if key in data["resolved_keys"]:
        raise StateError(f"resolved item {key!r} cannot become active")
    unresolved = unresolved_messages(data)
    if not unresolved or unresolved[0]["key"] != key:
        raise StateError(
            f"item {key!r} is not the first unresolved snapshot item"
        )
    data["active_key"] = key
    data["resume_key"] = None
    if key not in data["presented_keys"]:
        data["presented_keys"].append(key)
    if message["materialized"]:
        append_cursor_checkpoint(data, message, "active_unresolved")
    append_transition(data, event, key)
    refresh_prefetch(data)


def promote_next(data: dict[str, Any]) -> dict[str, Any] | None:
    data["active_key"] = None
    data["prefetched_key"] = None
    unresolved = unresolved_messages(data)
    if not unresolved:
        return None
    message = unresolved[0]
    activate_message(data, message, event="successor_promoted")
    return message


def commit_resolution_and_advance(
    data: dict[str, Any], message: dict[str, Any]
) -> dict[str, Any] | None:
    key = message["key"]
    if data.get("active_key") != key:
        raise StateError(f"only the active item {data.get('active_key')!r} can resolve")
    if not disposition_complete(message):
        raise StateError(f"item {key!r} has not crossed its verification gate")
    if key not in data["resolved_keys"]:
        data["resolved_keys"].append(key)
    append_transition(data, "resolved", key, decision=message["decision"])
    checkpoint = data.get("checkpoint")
    if isinstance(checkpoint, dict) and checkpoint.get("key") == key:
        data["checkpoint"] = None
    data["ui_operation"] = None
    data["ui_operation_history"] = [
        operation
        for operation in data["ui_operation_history"]
        if operation.get("key") != key
    ]
    return promote_next(data)


def cmd_next_card(args: argparse.Namespace) -> dict[str, Any]:
    """Select the next unresolved card from the frozen snapshot.

    The manifest order is the authoritative triage order established during
    inventory. An active unresolved card remains active; a decided-but-
    unverified card blocks advancement; and a verified card is never selected
    again.
    """

    selected: dict[str, Any] = {"message": None, "prefetched": None}

    def callback(data: dict[str, Any]) -> None:
        if data.get("run_state", "active") != "active":
            raise StateError("cannot select a card from a stopped run")
        if "decision_lane" in data:
            key = data["decision_lane"]["current_key"]
            selected["message"] = find_message(data, key) if key else None
            return False
        if not data["setup"]["snapshot_frozen"]:
            data["setup"]["snapshot_frozen"] = True
            append_transition(data, "snapshot_frozen")
        active_key = data.get("active_key")
        if active_key is not None:
            active = find_message(data, active_key)
            if not disposition_complete(active):
                if active["decision"] != "pending":
                    raise StateError(
                        f"active item {active_key!r} must pass live verification "
                        "before selecting the next card"
                    )
                selected["message"] = active
                refresh_prefetch(data)
                selected["prefetched"] = (
                    find_message(data, data["prefetched_key"])
                    if data["prefetched_key"] is not None
                    else None
                )
                return
            raise StateError(
                f"active item {active_key!r} is complete but not atomically resolved"
            )

        unresolved = unresolved_messages(data)
        message = unresolved[0] if unresolved else None
        if message is None:
            return
        activate_message(data, message)
        selected["message"] = message
        selected["prefetched"] = (
            find_message(data, data["prefetched_key"])
            if data["prefetched_key"] is not None
            else None
        )

    result = mutate(manifest_path(args.file), callback)
    message = selected["message"]
    result["card"] = card_payload(message)
    result["active"] = result["card"]
    result["prefetched"] = card_payload(selected["prefetched"])
    return result


def require_materialized(message: dict[str, Any], operation: str) -> None:
    if not message["materialized"]:
        raise StateError(
            f"active item {message['key']!r} must be materialized before {operation}"
        )


def require_live_setup(data: dict[str, Any], action: str) -> None:
    """Require the one-time protocol and Computer Use gates for live evidence."""

    setup = data.get("setup")
    if not isinstance(setup, dict) or not (
        setup.get("references_loaded") is True
        and setup.get("computer_use_initialized") is True
    ):
        raise StateError(
            f"{action} requires setup references_loaded and computer_use_initialized"
        )


def require_references_loaded(data: dict[str, Any], action: str) -> None:
    """Require the read-only protocol reference gate without forcing UI startup."""

    setup = data.get("setup")
    if not isinstance(setup, dict) or setup.get("references_loaded") is not True:
        raise StateError(f"{action} requires setup references_loaded")


def cmd_materialize(args: argparse.Namespace) -> dict[str, Any]:
    materialized: dict[str, Any] = {"message": None}

    def callback(data: dict[str, Any]) -> None:
        # A read-only connector may supply body-free Slack identity before
        # Computer Use is initialized.  Materialization is not a Slack write
        # or a rendered mutation claim, so only the reference gate applies.
        require_references_loaded(data, "Slack identity materialization")
        if data["run_state"] != "active":
            raise StateError("cannot materialize an item in a stopped run")
        lane = data.get("decision_lane")
        mutation_owner = bool(lane and args.key == data.get("active_key")
                              and args.key in lane["submitted_keys"])
        if not mutation_owner:
            require_decision_owner(data, args)
        message = find_message(data, args.key)
        message_ts = canonical_slack_timestamp(args.message_ts, "message_ts")
        boundary_ts = canonical_slack_timestamp(
            args.unread_boundary_ts or message_ts,
            "unread_boundary_ts",
        )
        if slack_timestamp_value(
            boundary_ts,
            "unread_boundary_ts",
        ) > slack_timestamp_value(message_ts, "message_ts"):
            raise StateError("unread_boundary_ts cannot follow message_ts")
        thread_key = (
            require_identity_string(args.thread_key, "thread_key")
            if args.thread_key is not None
            else None
        )
        requested = (message_ts, boundary_ts, thread_key)
        existing = (
            message.get("message_ts"),
            message.get("original_unread_boundary_ts"),
            message.get("thread_key"),
        )
        if message["materialized"]:
            if existing != requested:
                raise StateError(
                    "the active item is already materialized with different identity data"
                )
            materialized["message"] = message
            return
        message.update(
            {
                "materialized": True,
                "message_ts": message_ts,
                "original_unread_boundary_ts": boundary_ts,
                "thread_key": thread_key,
            }
        )
        if data.get("active_key") == args.key:
            append_cursor_checkpoint(data, message, "active_unresolved")
        append_transition(data, "materialized", args.key)
        materialized["message"] = message

    result = mutate(manifest_path(args.file), callback)
    result["card"] = card_payload(materialized["message"])
    result["active"] = result["card"]
    result["materialized_key"] = args.key
    return result


def cmd_stop(args: argparse.Namespace) -> dict[str, Any]:
    """Checkpoint a run without silently consuming its active unread item."""

    def callback(data: dict[str, Any]) -> None:
        final_decision = getattr(args, "decision", None)
        final_key = getattr(args, "key", None)
        if bool(final_decision) != bool(final_key):
            raise StateError("stop intent requires both --key and --decision")
        if final_decision:
            if final_decision == "reply":
                record_decision(data, args)
            else:
                submit_decision(data, args)
        if args.current_restored_unread:
            require_live_setup(data, "rendered unread restoration")
        if data.get("run_state", "active") != "active":
            raise StateError("run is already stopped")
        if not data["setup"]["snapshot_frozen"]:
            data["setup"]["snapshot_frozen"] = True
            append_transition(data, "snapshot_frozen")
        active_key = data.get("active_key")
        resume_key = active_key
        if active_key is not None:
            active = find_message(data, active_key)
            if not disposition_complete(active):
                if not active["materialized"]:
                    data["checkpoint"] = {
                        "kind": "stopped",
                        "key": active_key,
                        "at": now_iso(),
                        "read_cursor_restored": True,
                    }
                    data["active_key"] = None
                    data["prefetched_key"] = None
                    data["resume_key"] = active_key
                    data["run_state"] = "stopped"
                    data["stopped_at"] = now_iso()
                    append_transition(data, "stopped", active_key)
                    return
                send_operation = data.get("ui_operation")
                duplicate_gate = active["decision"] == "reply" and (
                    active["send_state"] in {"ack_pending", "ambiguous"}
                    or (
                        active["send_state"] == "not_dispatched"
                        and ui_operation_has_duplicate_risk(send_operation)
                    )
                )
                if duplicate_gate and active["send_state"] == "not_dispatched":
                    final_outcome = send_operation["attempts"][-1]["outcome"]
                    active["send_state"] = "ack_pending"
                    append_transition(
                        data,
                        "send_state_recorded",
                        active_key,
                        from_send_state="not_dispatched",
                        send_state="ack_pending",
                        intended_decision="reply",
                        draft_version=active["draft_version"],
                    )
                    if final_outcome == "ambiguous":
                        active["send_state"] = "ambiguous"
                        append_transition(
                            data,
                            "send_state_recorded",
                            active_key,
                            from_send_state="ack_pending",
                            send_state="ambiguous",
                            intended_decision="reply",
                            draft_version=active["draft_version"],
                        )
                if not args.current_restored_unread and not duplicate_gate:
                    raise StateError(
                        f"active unresolved item {active_key!r} must be restored unread "
                        "in first-party Slack before stopping; rerun with "
                        "--current-restored-unread after rendered verification"
                    )
                if args.current_restored_unread:
                    append_cursor_checkpoint(data, active, "restored_unread")
                    if active_key not in data["stopped_unread_keys"]:
                        data["stopped_unread_keys"].append(active_key)
                current_checkpoint = data.get("checkpoint")
                if (
                    not duplicate_gate
                    and isinstance(current_checkpoint, dict)
                    and current_checkpoint.get("kind") == "ui_retry_exhausted"
                ):
                    current_checkpoint["read_cursor_restored"] = bool(
                        args.current_restored_unread
                    )
                    current_checkpoint["at"] = now_iso()
                else:
                    if duplicate_gate:
                        ambiguous_gate = active["send_state"] == "ambiguous" or (
                            active["send_state"] == "not_dispatched"
                            and isinstance(send_operation, dict)
                            and send_operation["attempts"][-1]["outcome"]
                            == "ambiguous"
                        )
                        kind = (
                            "send_ambiguous" if ambiguous_gate else "send_ack_pending"
                        )
                    else:
                        kind = "stopped"
                        preserve_partial_retry = (
                            isinstance(send_operation, dict)
                            and send_operation.get("key") == active_key
                            and send_operation.get("state") == "retry_available"
                        )
                        if not preserve_partial_retry:
                            data["ui_operation"] = None
                    data["checkpoint"] = {
                        "kind": kind,
                        "key": active_key,
                        "at": now_iso(),
                        "read_cursor_restored": bool(args.current_restored_unread),
                    }
                if active_key not in data["stopped_unread_keys"] and args.current_restored_unread:
                    data["stopped_unread_keys"].append(active_key)
        elif unresolved_messages(data):
            resume_key = unresolved_messages(data)[0]["key"]
            resume_message = find_message(data, resume_key)
            data["ui_operation"] = None
            data["checkpoint"] = {
                "kind": "stopped",
                "key": resume_key,
                "at": now_iso(),
                "read_cursor_restored": True,
            }
            if (
                resume_message.get("materialized") is True
                and resume_key not in data["stopped_unread_keys"]
            ):
                data["stopped_unread_keys"].append(resume_key)
        data["active_key"] = None
        data["prefetched_key"] = None
        data["resume_key"] = resume_key
        data["run_state"] = "stopped"
        data["stopped_at"] = now_iso()
        append_transition(data, "stopped", resume_key)

    return mutate(manifest_path(args.file), callback)


def record_decision(data: dict[str, Any], args: argparse.Namespace) -> None:
    if data["run_state"] != "active":
        raise StateError("cannot decide an item in a stopped run")
    if not data["setup"]["snapshot_frozen"]:
        data["setup"]["snapshot_frozen"] = True
        append_transition(data, "snapshot_frozen")
    message = find_message(data, args.key)
    if args.key in data["resolved_keys"]:
        raise StateError("a resolved item cannot receive another decision")
    if "decision_lane" in data:
        require_decision_owner(data, args)
    elif data.get("active_key") is None:
        unresolved = unresolved_messages(data)
        if not unresolved or unresolved[0]["key"] != args.key:
            raise StateError("a disposition applies only to the first active item")
        activate_message(data, message)
    elif data["active_key"] != args.key:
        raise StateError(f"decision applies only to active item {data['active_key']!r}")
    # Record the user's choice immediately. All mutation and send helpers
    # still require materialization and the unchanged rendered-proof gates.
    if message["decision"] != "pending":
        if message["decision"] == args.decision:
            return
        current_operation = data.get("ui_operation")
        current_checkpoint = data.get("checkpoint")
        if isinstance(current_operation, dict) and current_operation["key"] != args.key:
            current_operation = None
        if isinstance(current_checkpoint, dict) and current_checkpoint["key"] != args.key:
            current_checkpoint = None
        definitive_failed_cancel = bool(
            message["decision"] == "reply"
            and args.decision in {"leave_unread", "mark_read"}
            and message["send_state"] == "failed"
            and message.get("readonly_seen") is True
            and current_operation is None
            and current_checkpoint is None
        )
        safe_failed_operation = bool(
            isinstance(current_operation, dict)
            and current_operation.get("key") == args.key
            and ui_operation_all_definitively_failed(current_operation)
            and (
                current_checkpoint is None
                or (
                    isinstance(current_checkpoint, dict)
                    and current_checkpoint.get("key") == args.key
                    and current_checkpoint.get("kind") == "ui_retry_exhausted"
                )
            )
        )
        ordinary_pre_ui_correction = bool(
            message["send_state"] in {"not_applicable", "not_dispatched"}
            and message["ui_disposition_verified"] is False
            and (
                (current_operation is None and current_checkpoint is None)
                or safe_failed_operation
            )
        )
        if not (definitive_failed_cancel or ordinary_pre_ui_correction):
            raise StateError(
                "the active decision can change only before its first UI attempt, "
                "or after a freshly verified definitive send failure"
            )
        if safe_failed_operation:
            data["ui_operation_history"].append(current_operation)
        if data.get("active_key") == args.key:
            data["ui_operation"] = None
        if (
            isinstance(current_checkpoint, dict)
            and current_checkpoint.get("key") == args.key
        ):
            data["checkpoint"] = None
        message.update(
            {
                "decision": args.decision,
                # This is a monotonic authorization identity, not merely the
                # current decision's draft count. Never reuse a spoken
                # version after a draft is canceled and drafting resumes.
                "draft_version": message["draft_version"],
                "approved_sha256": None,
                "approved_chars": None,
                "send_state": (
                    "not_dispatched"
                    if args.decision == "reply"
                    else "not_applicable"
                ),
                "sent_message_key": None,
                "legacy_send_reconciliation": False,
                "readonly_seen": False,
                "ui_disposition_verified": False,
            }
        )
        append_transition(
            data,
            "decision_corrected",
            args.key,
            decision=args.decision,
        )
        return
    message.update(
        {
            "decision": args.decision,
            "draft_version": 0,
            "approved_sha256": None,
            "approved_chars": None,
            "send_state": "not_dispatched" if args.decision == "reply" else "not_applicable",
            "sent_message_key": None,
            "legacy_send_reconciliation": False,
            "readonly_seen": False,
            "ui_disposition_verified": False,
        }
    )
    if data.get("active_key") == args.key:
        data["ui_operation"] = None
    append_transition(data, "decision_recorded", args.key, decision=args.decision)


def cmd_decide(args: argparse.Namespace) -> dict[str, Any]:
    def callback(data: dict[str, Any]) -> None:
        record_decision(data, args)

    return mutate(manifest_path(args.file), callback)


def cmd_approve(args: argparse.Namespace) -> dict[str, Any]:
    draft = sys.stdin.read(MAX_DRAFT_CHARS + 1)
    if len(draft) > MAX_DRAFT_CHARS:
        raise StateError(
            f"approve draft exceeds the {MAX_DRAFT_CHARS}-character limit"
        )
    if not draft:
        raise StateError("approve requires the exact non-empty draft on standard input")
    approved_sha256 = hashlib.sha256(draft.encode("utf-8")).hexdigest()
    approved_chars = len(draft)
    idempotent = {"value": False}
    approved_card: dict[str, Any] = {"value": None}

    def callback(data: dict[str, Any]) -> bool | None:
        message = find_message(data, args.key)
        require_decision_owner(data, args)
        require_materialized(message, "approving a draft")
        if message["decision"] != "reply":
            raise StateError("only a reply decision can approve a draft")
        if (
            message.get("approved_sha256") == approved_sha256
            and message.get("approved_chars") == approved_chars
        ):
            idempotent["value"] = True
            approved_card["value"] = card_payload(message)
            return False
        if message["send_state"] in {"ack_pending", "ambiguous", "sent_verified"}:
            raise StateError(
                "cannot replace an approval after dispatch; inspect the live destination"
            )
        current_operation = data.get("ui_operation")
        if (
            isinstance(current_operation, dict)
            and current_operation.get("key") == args.key
            and ui_operation_has_duplicate_risk(current_operation)
        ):
            raise StateError(
                "cannot replace an approval after a duplicate-prone send attempt"
            )
        if isinstance(current_operation, dict) and current_operation.get("key") == args.key:
            data["ui_operation"] = None
        data["ui_operation_history"] = [
            operation
            for operation in data["ui_operation_history"]
            if not (
                operation.get("key") == args.key
                and operation.get("operation") == "send"
            )
        ]
        checkpoint = data.get("checkpoint")
        if isinstance(checkpoint, dict) and checkpoint.get("key") == args.key:
            data["checkpoint"] = None
        message.update(
            {
                "draft_version": message["draft_version"] + 1,
                "approved_sha256": approved_sha256,
                "approved_chars": approved_chars,
                "send_state": "not_dispatched",
                "sent_message_key": None,
                "readonly_seen": False,
                "ui_disposition_verified": False,
            }
        )
        approved_card["value"] = card_payload(message)
        return None

    result = mutate(manifest_path(args.file), callback)
    result["approval_idempotent"] = idempotent["value"]
    result["card"] = approved_card["value"]
    result["approved_version"] = approved_card["value"]["draft_version"]
    result["approved_sha256"] = approved_card["value"]["approved_sha256"]
    return result


def cmd_verify_disposition(args: argparse.Namespace) -> dict[str, Any]:
    outcome: dict[str, Any] = {"next": None, "prefetched": None}

    def callback(data: dict[str, Any]) -> None:
        require_live_setup(data, "disposition verification")
        message = find_message(data, args.key)
        if data.get("active_key") != args.key:
            raise StateError("verify-disposition applies only to the active item")
        require_submitted(data, args.key)
        require_materialized(message, "disposition verification")
        if message["decision"] not in {"leave_unread", "mark_read"}:
            raise StateError("verify-disposition applies only to unread/read decisions")
        require_bound_ui_operation(
            data,
            message,
            message["decision"],
            allowed_states={"succeeded"},
            allowed_outcomes={"succeeded"},
        )
        message["ui_disposition_verified"] = True
        append_cursor_checkpoint(
            data,
            message,
            "verified_unread" if message["decision"] == "leave_unread" else "verified_read",
        )
        outcome["next"] = commit_resolution_and_advance(data, message)
        outcome["prefetched"] = (
            find_message(data, data["prefetched_key"])
            if data["prefetched_key"] is not None
            else None
        )

    result = mutate(manifest_path(args.file), callback)
    result["resolved_key"] = args.key
    result["next_card"] = None if "decision_key" in result else card_payload(outcome["next"])
    result["prefetched"] = card_payload(outcome["prefetched"])
    return result


def cmd_send_state(args: argparse.Namespace) -> dict[str, Any]:
    outcome: dict[str, Any] = {"next": None, "prefetched": None}

    def callback(data: dict[str, Any]) -> None:
        require_live_setup(data, "send-state verification")
        message = find_message(data, args.key)
        if data.get("active_key") != args.key:
            raise StateError("send-state applies only to the active item")
        require_submitted(data, args.key)
        require_materialized(message, "recording send state")
        if message["decision"] != "reply":
            raise StateError("send-state applies only to a reply decision")
        if message["approved_sha256"] is None:
            raise StateError("approve the exact draft before changing send state")
        prior_state = message["send_state"]
        allowed = SEND_STATE_TRANSITIONS[prior_state]
        if args.state not in allowed:
            raise StateError(
                f"send-state transition {prior_state!r} -> {args.state!r} is forbidden"
            )
        if args.state == "sent_verified":
            if (
                not args.sent_message_key
                or not SENT_MESSAGE_KEY_RE.fullmatch(args.sent_message_key)
                or not args.ui_verified
                or not args.rendered_text_sha256
            ):
                raise StateError(
                    "sent_verified requires --sent-message-key, --ui-verified, and "
                    "--rendered-text-sha256"
                )
            rendered_text_sha256 = require_hash(
                args.rendered_text_sha256, "rendered_text_sha256"
            )
            if rendered_text_sha256 != message["approved_sha256"]:
                raise StateError(
                    "rendered outgoing text does not match the approved draft"
                )
            if any(
                candidate.get("sent_message_key") == args.sent_message_key
                and candidate.get("key") != args.key
                for candidate in data["messages"]
            ):
                raise StateError("sent_message_key is already bound to another reply")
        elif (
            args.sent_message_key is not None
            or args.ui_verified
            or args.rendered_text_sha256 is not None
        ):
            raise StateError(
                "--sent-message-key, --ui-verified, and --rendered-text-sha256 "
                "apply only to sent_verified"
            )
        send_operation = require_bound_ui_operation(
            data,
            message,
            "send",
            allowed_states={"succeeded", "exhausted"},
            allowed_outcomes={"succeeded", "ambiguous"},
        )
        if (
            args.state == "failed"
            and send_operation["attempts"][-1]["outcome"] == "ambiguous"
        ):
            raise StateError(
                "an ambiguous send can never transition to retryable failure"
            )
        if args.state == "failed" and not args.readonly_seen:
            raise StateError(
                "definitive failed send requires --readonly-seen after a fresh rendered read"
            )
        message["send_state"] = args.state
        message["readonly_seen"] = bool(args.readonly_seen)
        message["sent_message_key"] = args.sent_message_key
        message["ui_disposition_verified"] = args.state == "sent_verified" and bool(args.ui_verified)
        append_transition(
            data,
            "send_state_recorded",
            args.key,
            from_send_state=prior_state,
            send_state=args.state,
            intended_decision="reply",
            draft_version=message["draft_version"],
        )
        if args.state == "ack_pending":
            data["checkpoint"] = {
                "kind": "send_ack_pending",
                "key": args.key,
                "at": now_iso(),
                "read_cursor_restored": False,
            }
        elif args.state == "ambiguous":
            data["checkpoint"] = {
                "kind": "send_ambiguous",
                "key": args.key,
                "at": now_iso(),
                "read_cursor_restored": False,
            }
        elif args.state == "failed":
            data["checkpoint"] = None
            data["ui_operation"] = None
            message["sent_message_key"] = None
        elif args.state == "sent_verified":
            append_cursor_checkpoint(data, message, "verified_read")
            outcome["next"] = commit_resolution_and_advance(data, message)
            outcome["prefetched"] = (
                find_message(data, data["prefetched_key"])
                if data["prefetched_key"] is not None
                else None
            )

    result = mutate(manifest_path(args.file), callback)
    result["next_card"] = None if "decision_key" in result else card_payload(outcome["next"])
    result["prefetched"] = card_payload(outcome["prefetched"])
    return result


def cmd_rearm_failed_send(args: argparse.Namespace) -> dict[str, Any]:
    """Allow one duplicate-safe retry of one definitively failed approved draft."""

    if not args.fresh_read:
        raise StateError("failed-send recovery requires --fresh-read")

    def callback(data: dict[str, Any]) -> None:
        require_live_setup(data, "failed-send rendered recovery")
        if data.get("run_state") != "active":
            raise StateError("failed-send recovery requires an active run")
        if data.get("active_key") != args.key:
            raise StateError("failed-send recovery applies only to the active item")
        message = find_message(data, args.key)
        require_materialized(message, "failed-send recovery")
        if (
            message.get("decision") != "reply"
            or message.get("send_state") != "failed"
            or message.get("readonly_seen") is not True
            or message.get("approved_sha256") is None
            or message.get("draft_version", 0) < 1
        ):
            raise StateError(
                "failed-send recovery requires an exact approved reply with a definitive rendered failure"
            )
        if data.get("ui_operation") is not None or data.get("checkpoint") is not None:
            raise StateError(
                "failed-send recovery requires a clean duplicate-safe active checkpoint"
            )
        token = failed_send_rearm_token(message)
        if token in data["failed_send_rearm_tokens"]:
            raise StateError(
                "this exact failed approved draft was already rearmed once"
            )
        data["failed_send_rearm_tokens"].append(token)
        message["send_state"] = "not_dispatched"
        message["readonly_seen"] = False
        message["sent_message_key"] = None
        message["ui_disposition_verified"] = False
        append_transition(
            data,
            "failed_send_rearmed",
            args.key,
            from_send_state="failed",
            send_state="not_dispatched",
            intended_decision="reply",
            draft_version=message["draft_version"],
        )

    return mutate(manifest_path(args.file), callback)


def cmd_reconcile_send(args: argparse.Namespace) -> dict[str, Any]:
    """Resolve an ambiguous or migrated send through rendered no-dispatch inspection."""

    if not args.fresh_read:
        raise StateError("send reconciliation requires --fresh-read")
    outcome: dict[str, Any] = {"next": None, "prefetched": None}

    def callback(data: dict[str, Any]) -> None:
        require_live_setup(data, "send reconciliation")
        message = find_message(data, args.key)
        if data.get("active_key") != args.key:
            raise StateError("reconcile-send applies only to the active item")
        require_materialized(message, "send reconciliation")
        legacy_reconciliation = message.get("legacy_send_reconciliation") is True
        ordinary_ambiguous = message.get("send_state") == "ambiguous"
        if message.get("decision") != "reply" or not (
            ordinary_ambiguous
            or (
                legacy_reconciliation
                and message.get("send_state") in {"ack_pending", "ambiguous"}
            )
        ):
            raise StateError(
                "reconcile-send is limited to ambiguous or migrated unresolved replies"
            )
        current_operation = data.get("ui_operation")
        already_inspected_ambiguous = bool(
            isinstance(current_operation, dict)
            and current_operation.get("operation") == "inspect_send"
            and current_operation.get("state") == "exhausted"
            and ui_operation_has_unsafe_outcome(current_operation)
        )
        if already_inspected_ambiguous and args.state == "ambiguous":
            raise StateError(
                "the rendered inspection is already ambiguous; do not loop or resend"
            )
        if (
            isinstance(current_operation, dict)
            and current_operation.get("binding_trusted") is True
            and not ordinary_ambiguous
        ):
            raise StateError(
                "trusted dispatch evidence must use the ordinary send-state path"
            )

        if args.state == "sent_verified":
            sent_key = args.sent_message_key
            if (
                not isinstance(sent_key, str)
                or not SENT_MESSAGE_KEY_RE.fullmatch(sent_key)
                or not args.ui_verified
                or not args.rendered_text_sha256
            ):
                raise StateError(
                    "sent_verified reconciliation requires a stable "
                    "--sent-message-key, --ui-verified, and "
                    "--rendered-text-sha256"
                )
            rendered_text_sha256 = require_hash(
                args.rendered_text_sha256, "rendered_text_sha256"
            )
            if rendered_text_sha256 != message["approved_sha256"]:
                raise StateError(
                    "rendered outgoing text does not match the approved draft"
                )
            if any(
                candidate.get("sent_message_key") == sent_key
                and candidate.get("key") != args.key
                for candidate in data["messages"]
            ):
                raise StateError("sent_message_key is already bound to another reply")
            ui_outcome = "succeeded"
            observed_state = "target_already_correct"
            operation_state = "succeeded"
        else:
            if (
                args.sent_message_key is not None
                or args.ui_verified
                or args.rendered_text_sha256 is not None
            ):
                raise StateError(
                    "ambiguous reconciliation cannot claim a sent key, verification, "
                    "or rendered text digest"
                )
            sent_key = None
            ui_outcome = "ambiguous"
            observed_state = "ambiguous"
            operation_state = "exhausted"

        prior_state = message["send_state"]
        data["ui_operation"] = {
            "key": args.key,
            "operation": "inspect_send",
            "state": operation_state,
            "attempts": [
                {
                    "attempt": 1,
                    "strategy": "rendered_inspection",
                    "outcome": ui_outcome,
                    "observed_state": observed_state,
                    "fresh_read": True,
                    "at": now_iso(),
                }
            ],
            "intended_decision": "reply",
            "draft_version": message["draft_version"],
            "approved_sha256": message["approved_sha256"],
            "binding_trusted": True,
        }
        message["send_state"] = args.state
        message["readonly_seen"] = True
        message["sent_message_key"] = sent_key
        message["ui_disposition_verified"] = bool(
            args.state == "sent_verified" and args.ui_verified
        )
        append_transition(
            data,
            "legacy_send_reconciled",
            args.key,
            from_send_state=prior_state,
            send_state=args.state,
            intended_decision="reply",
            draft_version=message["draft_version"],
            operation="inspect_send",
            outcome=ui_outcome,
        )
        if args.state == "ambiguous":
            data["checkpoint"] = {
                "kind": "send_ambiguous",
                "key": args.key,
                "at": now_iso(),
                "read_cursor_restored": False,
            }
            return

        append_cursor_checkpoint(data, message, "verified_read")
        outcome["next"] = commit_resolution_and_advance(data, message)
        outcome["prefetched"] = (
            find_message(data, data["prefetched_key"])
            if data["prefetched_key"] is not None
            else None
        )

    result = mutate(manifest_path(args.file), callback)
    result["next_card"] = None if "decision_key" in result else card_payload(outcome["next"])
    result["prefetched"] = card_payload(outcome["prefetched"])
    return result


def cmd_reconcile_cursor(args: argparse.Namespace) -> dict[str, Any]:
    """Prove the final earliest unread boundary after later cursor mutations."""

    if not args.fresh_read:
        raise StateError("cursor reconciliation requires --fresh-read")
    reconciled: dict[str, Any] = {"idempotent": False}

    def callback(data: dict[str, Any]) -> bool | None:
        require_live_setup(data, "conversation cursor reconciliation")
        if data.get("run_state") != "active":
            raise StateError("cursor reconciliation requires an active run")
        if unresolved_messages(data):
            raise StateError(
                "finish every frozen snapshot item before cursor reconciliation"
            )
        anchor = find_message(data, args.anchor_key)
        require_materialized(anchor, "cursor reconciliation")
        if (
            anchor.get("decision") != "leave_unread"
            or args.anchor_key not in data["resolved_keys"]
        ):
            raise StateError(
                "cursor reconciliation anchor must be a resolved leave-unread item"
            )
        group = [
            message
            for message in data["messages"]
            if message["workspace"] == anchor["workspace"]
            and message["conversation"] == anchor["conversation"]
        ]
        if any(message["key"] not in data["resolved_keys"] for message in group):
            raise StateError(
                "finish every frozen item in the conversation before cursor reconciliation"
            )
        unread_items = [
            message for message in group if message["decision"] == "leave_unread"
        ]
        earliest = min(
            unread_items,
            key=lambda message: slack_timestamp_value(
                message["original_unread_boundary_ts"],
                "original_unread_boundary_ts",
            ),
        )
        if earliest["key"] != args.anchor_key:
            raise StateError(
                "cursor reconciliation must target the earliest chosen unread boundary"
            )
        anchor_value = slack_timestamp_value(
            anchor["original_unread_boundary_ts"],
            "original_unread_boundary_ts",
        )
        collateral = [
            message
            for message in group
            if message["decision"] in {"mark_read", "reply"}
            and slack_timestamp_value(message["message_ts"], "message_ts")
            > anchor_value
        ]
        if not collateral:
            raise StateError(
                "the conversation has no later processed cursor collateral to reconcile"
            )
        group_keys = {message["key"] for message in group}
        group_proofs = [
            proof
            for proof in data["read_cursor_checkpoints"]
            if proof.get("key") in group_keys
        ]
        if (
            group_proofs
            and group_proofs[-1].get("key") == args.anchor_key
            and group_proofs[-1].get("state") == "restored_unread"
            and group_proofs[-1].get("boundary_ts")
            == anchor["original_unread_boundary_ts"]
        ):
            reconciled["idempotent"] = True
            return False
        append_cursor_checkpoint(data, anchor, "restored_unread")
        append_transition(
            data,
            "cursor_reconciled",
            args.anchor_key,
            operation="leave_unread",
            outcome="succeeded",
        )
        return None

    result = mutate(manifest_path(args.file), callback)
    result["anchor_key"] = args.anchor_key
    result["cursor_reconciliation_idempotent"] = reconciled["idempotent"]
    return result


def cmd_setup(args: argparse.Namespace) -> dict[str, Any]:
    requested = {
        "references_loaded": bool(args.references_loaded),
        "snapshot_frozen": bool(args.snapshot_frozen),
        "computer_use_initialized": bool(args.computer_use_initialized),
    }
    if not any(requested.values()):
        raise StateError("setup requires at least one completed setup flag")

    def callback(data: dict[str, Any]) -> None:
        if data["run_state"] != "active":
            raise StateError("cannot initialize setup on a stopped run")
        changed: list[str] = []
        for field, enabled in requested.items():
            if enabled and not data["setup"][field]:
                data["setup"][field] = True
                changed.append(field)
        if not changed:
            return False
        append_transition(
            data,
            "setup_recorded",
            fields=changed,
        )

    return mutate(manifest_path(args.file), callback)


def expected_ui_operations(message: dict[str, Any]) -> set[str]:
    if message["decision"] == "pending":
        return set()
    if message["decision"] == "leave_unread":
        return {"leave_unread"}
    if message["decision"] == "mark_read":
        return {"mark_read"}
    if message["decision"] == "reply":
        operations: set[str] = set()
        if (
            message["approved_sha256"] is not None
            and message["send_state"] == "not_dispatched"
        ):
            operations.add("send")
        return operations
    return set()


def cmd_ui_attempt(args: argparse.Namespace) -> dict[str, Any]:
    if not args.fresh_read:
        raise StateError("every UI attempt requires --fresh-read")
    validate_ui_outcome_observation(args.outcome, args.observed_state, "UI attempt")
    outcome: dict[str, Any] = {}

    def callback(data: dict[str, Any]) -> None:
        require_live_setup(data, "a live UI attempt")
        if data["run_state"] != "active":
            raise StateError("cannot record a UI attempt on a stopped run")
        if data.get("active_key") != args.key:
            raise StateError("UI attempts apply only to the active item")
        require_submitted(data, args.key)
        message = find_message(data, args.key)
        require_materialized(message, "a UI attempt")
        if args.operation not in expected_ui_operations(message):
            if args.operation == "send" and message["decision"] == "reply":
                raise StateError(
                    "send is already dispatched or unresolved; duplicate send attempts are forbidden"
                )
            raise StateError(
                f"operation {args.operation!r} is not valid for the active decision"
            )
        current = data.get("ui_operation")
        restored_history = False
        if current is None:
            matching_index = next(
                (
                    index
                    for index, historical in enumerate(
                        data["ui_operation_history"]
                    )
                    if historical.get("key") == args.key
                    and historical.get("operation") == args.operation
                    and (
                        args.operation != "send"
                        or (
                            historical.get("draft_version")
                            == message.get("draft_version")
                            and historical.get("approved_sha256")
                            == message.get("approved_sha256")
                        )
                    )
                ),
                None,
            )
            if matching_index is not None:
                current = data["ui_operation_history"].pop(matching_index)
                restored_history = True
        if current is None:
            attempts: list[dict[str, Any]] = []
        else:
            if current["key"] != args.key or current["operation"] != args.operation:
                raise StateError("finish the current bounded UI operation first")
            if current.get("binding_trusted") is not True:
                if not ui_operation_all_definitively_failed(current):
                    raise StateError(
                        "legacy UI evidence is not definitively failed and cannot authorize recovery"
                    )
                rearm_token = ui_retry_rearm_token(message, current)
                if ui_retry_rearm_was_used(data, message, current):
                    raise StateError(
                        "the legacy UI retry budget was already rearmed once for this item and operation"
                    )
                data["ui_retry_rearm_tokens"].append(rearm_token)
                data["ui_operation"] = None
                checkpoint = data.get("checkpoint")
                if (
                    isinstance(checkpoint, dict)
                    and checkpoint.get("key") == args.key
                ):
                    data["checkpoint"] = None
                append_transition(data, "legacy_ui_retry_rearmed", args.key)
                current = None
                attempts = []
            else:
                attempts = list(current["attempts"])
            if current is not None and current.get("intended_decision") != message["decision"]:
                raise StateError("the current UI operation is bound to a stale disposition")
            if current is not None and args.operation == "send" and (
                current.get("draft_version") != message["draft_version"]
                or current.get("approved_sha256") != message["approved_sha256"]
            ):
                raise StateError("the current send attempt is bound to a stale draft")
            if (
                current is not None
                and restored_history
                and current["state"] == "exhausted"
                and ui_operation_all_definitively_failed(current)
            ):
                rearm_token = ui_retry_rearm_token(message, current)
                if ui_retry_rearm_was_used(data, message, current):
                    raise StateError(
                        "the UI retry budget was already rearmed once for this item and operation"
                    )
                data["ui_retry_rearm_tokens"].append(rearm_token)
                append_transition(data, "ui_retry_budget_rearmed", args.key)
                current = None
                attempts = []
            if current is not None and current["state"] in {"succeeded", "exhausted"}:
                raise StateError(f"UI operation is already {current['state']}")
        if len(attempts) >= MAX_UI_ATTEMPTS:
            raise StateError("UI operation exhausted its two-attempt budget")
        if attempts and attempts[-1]["strategy"] == args.strategy:
            raise StateError("the alternate attempt must use a different strategy")
        attempt = {
            "attempt": len(attempts) + 1,
            "strategy": require_string(args.strategy, "strategy"),
            "outcome": args.outcome,
            "observed_state": args.observed_state,
            "fresh_read": True,
            "at": now_iso(),
        }
        attempts.append(attempt)
        if args.outcome == "succeeded":
            state = "succeeded"
        elif args.outcome == "ambiguous":
            state = "exhausted"
        elif len(attempts) < MAX_UI_ATTEMPTS:
            state = "retry_available"
        else:
            state = "exhausted"
        data["ui_operation"] = {
            "key": args.key,
            "operation": args.operation,
            "state": state,
            "attempts": attempts,
            "intended_decision": message["decision"],
            "draft_version": (
                message["draft_version"] if args.operation == "send" else None
            ),
            "approved_sha256": (
                message["approved_sha256"] if args.operation == "send" else None
            ),
            "binding_trusted": True,
        }
        if state == "exhausted":
            if args.operation == "send" and args.outcome == "ambiguous":
                data["checkpoint"] = {
                    "kind": "send_ambiguous",
                    "key": args.key,
                    "at": now_iso(),
                    "read_cursor_restored": False,
                }
            else:
                data["checkpoint"] = {
                    "kind": "ui_retry_exhausted",
                    "key": args.key,
                    "operation": args.operation,
                    "desired_state": args.operation,
                    "observed_state": args.observed_state,
                    "attempts": len(attempts),
                    "at": now_iso(),
                    "read_cursor_restored": False,
                }
        append_transition(
            data,
            "ui_attempt_recorded",
            args.key,
            operation=args.operation,
            attempt=len(attempts),
            outcome=args.outcome,
            retry_state=state,
        )
        outcome.update(
            {
                "operation": data["ui_operation"],
                "remaining_attempts": MAX_UI_ATTEMPTS - len(attempts),
            }
        )

    result = mutate(manifest_path(args.file), callback)
    result.update(outcome)
    return result


def cmd_resume(args: argparse.Namespace) -> dict[str, Any]:
    selected: dict[str, Any] = {"message": None, "prefetched": None}

    def callback(data: dict[str, Any]) -> None:
        if data["run_state"] != "stopped":
            raise StateError("resume requires a stopped run")
        resume_key = data.get("resume_key")
        if resume_key is not None and resume_key in data["resolved_keys"]:
            raise StateError("resume key is already resolved")
        data["run_state"] = "active"
        data["stopped_at"] = None
        data["session_generation"] += 1
        ui_operation = data.get("ui_operation")
        checkpoint = data.get("checkpoint")
        if isinstance(ui_operation, dict) and ui_operation.get(
            "binding_trusted"
        ) is not True:
            if ui_operation_has_unsafe_outcome(ui_operation):
                # Pre-binding send evidence may only continue through the
                # duplicate-suppressed rendered inspection checkpoint.
                if not (
                    isinstance(checkpoint, dict)
                    and checkpoint.get("kind")
                    in {"send_ack_pending", "send_ambiguous"}
                ):
                    raise StateError(
                        "unsafe legacy UI evidence requires its send checkpoint"
                    )
            elif not ui_operation_all_definitively_failed(ui_operation):
                raise StateError(
                    "legacy UI evidence is not definitively failed and cannot authorize recovery"
                )
            else:
                if resume_key is None:
                    raise StateError("legacy UI recovery requires an exact resume key")
                resume_message = find_message(data, resume_key)
                rearm_token = ui_retry_rearm_token(resume_message, ui_operation)
                if ui_retry_rearm_was_used(data, resume_message, ui_operation):
                    raise StateError(
                        "the legacy UI retry budget was already rearmed once for this item and operation"
                    )
                data["ui_retry_rearm_tokens"].append(rearm_token)
                data["ui_operation"] = None
                data["checkpoint"] = None
                append_transition(data, "legacy_ui_retry_rearmed", resume_key)
        elif (
            isinstance(ui_operation, dict)
            and ui_operation.get("state") == "exhausted"
            and not ui_operation_has_unsafe_outcome(ui_operation)
        ):
            if resume_key is None:
                raise StateError("an exhausted UI operation requires an exact resume key")
            resume_message = find_message(data, resume_key)
            rearm_token = ui_retry_rearm_token(resume_message, ui_operation)
            if ui_retry_rearm_was_used(data, resume_message, ui_operation):
                raise StateError(
                    "the UI retry budget was already rearmed once for this item and operation"
                )
            data["ui_retry_rearm_tokens"].append(rearm_token)
            data["ui_operation"] = None
            data["checkpoint"] = None
            append_transition(data, "ui_retry_budget_rearmed", resume_key)
        elif (
            isinstance(ui_operation, dict)
            and ui_operation.get("state") == "exhausted"
            and ui_operation_has_unsafe_outcome(ui_operation)
            and isinstance(checkpoint, dict)
            and checkpoint.get("kind") == "ui_retry_exhausted"
        ):
            checkpoint["read_cursor_restored"] = False
            checkpoint["at"] = now_iso()
        elif isinstance(checkpoint, dict) and checkpoint.get("kind") == "stopped":
            data["checkpoint"] = None
        checkpoint = data.get("checkpoint")
        if isinstance(checkpoint, dict) and checkpoint.get("kind") in {
            "send_ack_pending",
            "send_ambiguous",
        }:
            # Resuming adds a fresh active_unresolved cursor proof.  Any
            # restoration recorded while stopped is therefore historical, not
            # a current active-state claim.
            checkpoint["read_cursor_restored"] = False
            checkpoint["at"] = now_iso()
        data["resume_key"] = None
        if resume_key is None:
            unresolved = unresolved_messages(data)
            message = unresolved[0] if unresolved else None
        else:
            message = find_message(data, resume_key)
        if message is not None:
            activate_message(data, message, event="resumed")
            selected["message"] = message
            selected["prefetched"] = (
                find_message(data, data["prefetched_key"])
                if data["prefetched_key"] is not None
                else None
            )
        else:
            append_transition(data, "resumed_complete")

    result = mutate(manifest_path(args.file), callback)
    result["card"] = result.get("decision_card", card_payload(selected["message"]))
    result["active"] = result["card"]
    result["prefetched"] = card_payload(selected["prefetched"])
    return result


def cmd_validate(args: argparse.Namespace) -> dict[str, Any]:
    return validate_state(read_state(manifest_path(args.file)))


def cmd_go_back(args: argparse.Namespace) -> dict[str, Any]:
    """Return the prior presented card without mutating triage ownership or Slack."""

    path = manifest_path(args.file)
    data = read_state(path)
    summary = validate_state(data)
    presented = data["presented_keys"]
    owner_key = (
        data.get("active_key")
        if data["run_state"] == "active"
        else data.get("resume_key")
    )
    if "decision_lane" in data:
        lane = data["decision_lane"]
        owner_key = lane["current_key"]
        presented = list(lane["submitted_keys"])
        if owner_key is not None:
            presented.append(owner_key)
    if owner_key in presented:
        owner_index = presented.index(owner_key)
        prior_key = presented[owner_index - 1] if owner_index > 0 else None
    else:
        prior_key = presented[-1] if presented else None
    if prior_key is None:
        raise StateError("there is no prior presented card in this snapshot")
    return {
        "ok": True,
        "run_state": summary["run_state"],
        "owner_key": owner_key,
        "card": card_payload(find_message(data, prior_key)),
        "read_only": True,
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    new = subparsers.add_parser("new", help="create a new empty snapshot manifest")
    new.add_argument("--file", required=True)
    new.add_argument("--session-id", required=True)
    new.add_argument("--run-id")
    new.add_argument("--snapshot-at", required=True)
    new.set_defaults(handler=cmd_new)

    bootstrap = subparsers.add_parser("bootstrap", help="atomically freeze body-free stdin snapshot and return the first decision card")
    bootstrap.add_argument("--file", required=True)
    bootstrap.add_argument("--session-id", required=True)
    bootstrap.add_argument("--run-id")
    bootstrap.add_argument("--snapshot-at", help="observed UTC/offset time; defaults to the current clock")
    bootstrap.add_argument("--references-loaded", action="store_true")
    bootstrap.add_argument("--computer-use-initialized", action="store_true")
    bootstrap.set_defaults(handler=cmd_bootstrap)

    add = subparsers.add_parser(
        "add",
        help=(
            "add one body-free snapshot row; omit key/time for a provisional row"
        ),
    )
    add.add_argument("--file", required=True)
    add.add_argument("--key")
    add.add_argument("--workspace", required=True)
    add.add_argument("--conversation", required=True)
    add.add_argument("--surface", choices=sorted(SURFACES), required=True)
    add.add_argument("--message-ts")
    add.add_argument("--unread-boundary-ts")
    add.add_argument("--thread-key")
    add.set_defaults(handler=cmd_add)

    next_card = subparsers.add_parser(
        "next-card", help="select the current or next unresolved snapshot item"
    )
    next_card.add_argument("--file", required=True)
    next_card.set_defaults(handler=cmd_next_card)

    materialize = subparsers.add_parser(
        "materialize",
        help="bind Slack identity fields to the active provisional snapshot row",
    )
    materialize.add_argument("--file", required=True)
    materialize.add_argument("--key", required=True)
    materialize.add_argument("--message-ts", required=True)
    materialize.add_argument("--unread-boundary-ts")
    materialize.add_argument("--thread-key")
    materialize.set_defaults(handler=cmd_materialize)

    decide = subparsers.add_parser("decide", help="record the user's disposition")
    decide.add_argument("--file", required=True)
    decide.add_argument("--key", required=True)
    decide.add_argument("--queued-correction", action="store_true")
    decide.add_argument(
        "--decision", choices=["leave_unread", "mark_read", "reply"], required=True
    )
    decide.set_defaults(handler=cmd_decide)

    queue = subparsers.add_parser("queue-decision", help="record the current choice and return the next decision card without advancing the mutation lane")
    queue.add_argument("--file", required=True)
    queue.add_argument("--key", required=True)
    queue.add_argument("--decision", choices=["leave_unread", "mark_read", "reply"], required=True)
    queue.set_defaults(handler=cmd_queue_decision)

    approve = subparsers.add_parser("approve", help="hash an exact draft from stdin")
    approve.add_argument("--file", required=True)
    approve.add_argument("--key", required=True)
    approve.add_argument("--queued-correction", action="store_true")
    approve.set_defaults(handler=cmd_approve)

    verify = subparsers.add_parser(
        "verify-disposition", help="record rendered verification of read/unread state"
    )
    verify.add_argument("--file", required=True)
    verify.add_argument("--key", required=True)
    verify.set_defaults(handler=cmd_verify_disposition)

    send = subparsers.add_parser("send-state", help="record one reply's dispatch state")
    send.add_argument("--file", required=True)
    send.add_argument("--key", required=True)
    send.add_argument(
        "--state",
        choices=["ack_pending", "sent_verified", "ambiguous", "failed"],
        required=True,
    )
    send.add_argument("--sent-message-key")
    send.add_argument("--readonly-seen", action="store_true")
    send.add_argument("--ui-verified", action="store_true")
    send.add_argument("--rendered-text-sha256")
    send.set_defaults(handler=cmd_send_state)

    rearm_failed_send = subparsers.add_parser(
        "rearm-failed-send",
        help="rearm one exact definitively failed approved reply at most once",
    )
    rearm_failed_send.add_argument("--file", required=True)
    rearm_failed_send.add_argument("--key", required=True)
    rearm_failed_send.add_argument("--fresh-read", action="store_true")
    rearm_failed_send.set_defaults(handler=cmd_rearm_failed_send)

    reconcile_send = subparsers.add_parser(
        "reconcile-send",
        help="inspect and reconcile an ambiguous or migrated send without dispatching",
    )
    reconcile_send.add_argument("--file", required=True)
    reconcile_send.add_argument("--key", required=True)
    reconcile_send.add_argument(
        "--state",
        choices=["sent_verified", "ambiguous"],
        required=True,
    )
    reconcile_send.add_argument("--sent-message-key")
    reconcile_send.add_argument("--ui-verified", action="store_true")
    reconcile_send.add_argument("--rendered-text-sha256")
    reconcile_send.add_argument("--fresh-read", action="store_true")
    reconcile_send.set_defaults(handler=cmd_reconcile_send)

    reconcile_cursor = subparsers.add_parser(
        "reconcile-cursor",
        help="verify the final earliest unread boundary for one conversation",
    )
    reconcile_cursor.add_argument("--file", required=True)
    reconcile_cursor.add_argument("--anchor-key", required=True)
    reconcile_cursor.add_argument("--fresh-read", action="store_true")
    reconcile_cursor.set_defaults(handler=cmd_reconcile_cursor)

    validate = subparsers.add_parser("validate", help="validate and summarize state")
    validate.add_argument("--file", required=True)
    validate.set_defaults(handler=cmd_validate)

    go_back = subparsers.add_parser(
        "go-back", help="read the prior presented card without changing state"
    )
    go_back.add_argument("--file", required=True)
    go_back.set_defaults(handler=cmd_go_back)

    stop = subparsers.add_parser(
        "stop", help="checkpoint and stop without consuming the active unread item"
    )
    stop.add_argument("--file", required=True)
    stop.add_argument("--key")
    stop.add_argument("--decision", choices=["leave_unread", "mark_read", "reply"])
    stop.add_argument("--current-restored-unread", action="store_true")
    stop.set_defaults(handler=cmd_stop)

    resume = subparsers.add_parser(
        "resume", help="resume the exact persisted checkpoint without re-asking"
    )
    resume.add_argument("--file", required=True)
    resume.set_defaults(handler=cmd_resume)

    setup = subparsers.add_parser(
        "setup", help="record setup-once gates without rerunning completed setup"
    )
    setup.add_argument("--file", required=True)
    setup.add_argument("--references-loaded", action="store_true")
    setup.add_argument("--snapshot-frozen", action="store_true")
    setup.add_argument("--computer-use-initialized", action="store_true")
    setup.set_defaults(handler=cmd_setup)

    ui_attempt = subparsers.add_parser(
        "ui-attempt", help="record one of at most two fresh semantic UI attempts"
    )
    ui_attempt.add_argument("--file", required=True)
    ui_attempt.add_argument("--key", required=True)
    ui_attempt.add_argument(
        "--operation",
        choices=sorted(UI_OPERATIONS - {"inspect_send", "restore_unread"}),
        required=True,
    )
    ui_attempt.add_argument("--strategy", required=True)
    ui_attempt.add_argument("--outcome", choices=sorted(UI_OUTCOMES), required=True)
    ui_attempt.add_argument(
        "--observed-state", choices=sorted(UI_OBSERVED_STATES), required=True
    )
    ui_attempt.add_argument("--fresh-read", action="store_true")
    ui_attempt.set_defaults(handler=cmd_ui_attempt)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        result = args.handler(args)
    except StateError as exc:
        print(json.dumps({"ok": False, "error": str(exc)}, sort_keys=True), file=sys.stderr)
        return 2
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
