#!/usr/bin/env python3
"""Body-free state machine for interactive macOS Messages triage."""

from __future__ import annotations

import argparse
import contextlib
import hashlib
import json
import os
import re
import stat
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterator

try:
    import fcntl
except ImportError as exc:  # pragma: no cover - macOS and Linux provide fcntl
    raise SystemExit("fcntl is required") from exc


SCHEMA_VERSION = 1
MAX_STATE_BYTES = 1_000_000
MAX_STDIN_CHARS = 200_000
MAX_DRAFT_CHARS = 40_000
HASH_RE = re.compile(r"^[0-9a-f]{64}$")
SERVICES = {"imessage", "sms"}
KINDS = {"direct", "group"}
CHOICES = {"leave_unread", "mark_read", "reply"}
BODY_KEYS = {
    "body",
    "card",
    "contact",
    "context",
    "draft",
    "message",
    "name",
    "phone",
    "preview",
    "recipient",
    "text",
}
ITEM_FIELDS = {
    "key",
    "service",
    "kind",
    "participant_count",
    "thread_sha256",
    "participants_sha256",
    "unread_sha256",
}


class StateError(Exception):
    pass


def json_pairs_no_duplicates(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise StateError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def parse_json(raw: str) -> Any:
    try:
        return json.loads(raw, object_pairs_hook=json_pairs_no_duplicates)
    except StateError:
        raise
    except json.JSONDecodeError as exc:
        raise StateError(f"invalid JSON: {exc.msg}") from exc


def require_hash(value: Any, label: str) -> str:
    if not isinstance(value, str) or not HASH_RE.fullmatch(value):
        raise StateError(f"{label} must be a lowercase SHA-256 hex digest")
    return value


def require_string(value: Any, label: str, limit: int = 256) -> str:
    if not isinstance(value, str) or not value or len(value) > limit:
        raise StateError(f"{label} must be a non-empty string up to {limit} characters")
    return value


def inspect_private_file(path: Path) -> os.stat_result:
    try:
        info = path.lstat()
    except FileNotFoundError as exc:
        raise StateError("manifest does not exist") from exc
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        raise StateError("manifest must be one regular, non-symlink file")
    if info.st_nlink != 1:
        raise StateError("manifest must not have hard links")
    if stat.S_IMODE(info.st_mode) != 0o600:
        raise StateError("manifest mode must be 0600")
    if info.st_size > MAX_STATE_BYTES:
        raise StateError("manifest exceeds the size limit")
    return info


def reject_body_keys(value: Any, path: str = "manifest") -> None:
    if isinstance(value, dict):
        for key, nested in value.items():
            if key.lower() in BODY_KEYS:
                raise StateError(f"body-bearing field is forbidden in persisted state: {path}.{key}")
            reject_body_keys(nested, f"{path}.{key}")
    elif isinstance(value, list):
        for index, nested in enumerate(value):
            reject_body_keys(nested, f"{path}[{index}]")


def require_fields(value: Any, allowed: set[str]) -> None:
    if not isinstance(value, dict) or set(value) - allowed:
        raise StateError("persisted state contains an unsupported field or shape")


def validate_persisted_shape(data: Any) -> None:
    root_fields = {"schema_version", "session_id", "snapshot_at", "run_state",
                   "snapshot_frozen", "inventory", "active_key", "preview_keys",
                   "decisions", "mutation_queue", "mutation_inflight", "resolved",
                   "unresolved", "body_free"}
    require_fields(data, root_fields)
    if set(data) != root_fields or data["body_free"] is not True:
        raise StateError("persisted state is incomplete or not body-free")
    if not isinstance(data["inventory"], list):
        raise StateError("persisted inventory must be a list")
    for item in data["inventory"]:
        if not isinstance(item, dict):
            raise StateError("persisted inventory item must be an object")
        require_fields(item, {"key", "materialized"} if item.get("materialized") is False else ITEM_FIELDS)
        validate_item(item)
    keys = {item["key"] for item in data["inventory"]}
    if (data["snapshot_frozen"] is not True or data["run_state"] not in {"active", "stopped"}
            or data["active_key"] is not None and data["active_key"] not in keys
            or not isinstance(data["preview_keys"], list)
            or any(not isinstance(key, str) or key not in keys for key in data["preview_keys"])):
        raise StateError("persisted snapshot identity is invalid")
    binding_fields = {"sidebar_sha256", "unread_sha256"}
    decision_fields = {"choice", "proof_state", "attempt_count", "approval_version", "approval", "read_binding"}
    operation_fields = {"key", "operation", "fresh_read", "attempt", "read_binding"}
    proof_fields = {"proof_sha256", "sidebar_sha256", "sent_message_sha256", "unique_outgoing",
                    "composer_empty", "no_failure", "no_attribution", "read_state"}
    for name in ("decisions", "resolved", "unresolved"):
        if not isinstance(data[name], dict) or set(data[name]) - keys:
            raise StateError("persisted state contains an unbound item")
    for decision in data["decisions"].values():
        require_fields(decision, decision_fields)
        if (decision.get("choice") not in CHOICES
                or decision.get("proof_state") not in {"awaiting_approval", "queued", "inflight", "resolved", "ambiguous", "blocked"}
                or type(decision.get("attempt_count")) is not int
                or not 0 <= decision["attempt_count"] <= 2):
            raise StateError("persisted decision is invalid")
        if "approval_version" in decision and (type(decision["approval_version"]) is not int or decision["approval_version"] < 1):
            raise StateError("persisted approval version is invalid")
        if "approval" in decision:
            require_fields(decision["approval"], {"draft_sha256", "service", "participants_sha256"})
            for field in ("draft_sha256", "participants_sha256"):
                require_hash(decision["approval"].get(field), field)
            if decision["approval"].get("service") not in SERVICES:
                raise StateError("persisted approval service is invalid")
        if "read_binding" in decision:
            require_fields(decision["read_binding"], binding_fields)
            for field in binding_fields:
                require_hash(decision["read_binding"].get(field), field)
    if not isinstance(data["mutation_queue"], list):
        raise StateError("persisted queue must be a list")
    operations = list(data["mutation_queue"])
    if data["mutation_inflight"] is not None:
        operations.append(data["mutation_inflight"])
    for operation in operations:
        require_fields(operation, operation_fields)
        if operation.get("key") not in keys:
            raise StateError("persisted operation has an unbound item")
        if operation.get("operation") not in {"send", "verify_unread", "mark_read"}:
            raise StateError("persisted operation is invalid")
        if "fresh_read" in operation and operation["fresh_read"] is not True:
            raise StateError("persisted fresh-read evidence is invalid")
        if "attempt" in operation and (type(operation["attempt"]) is not int or operation["attempt"] not in {1, 2}):
            raise StateError("persisted attempt is invalid")
        if "read_binding" in operation:
            require_fields(operation["read_binding"], binding_fields)
            for field in binding_fields:
                require_hash(operation["read_binding"].get(field), field)
    for resolved in data["resolved"].values():
        require_fields(resolved, {"choice", "operation", "attempt", "evidence_source", "rendered_proof"})
        require_fields(resolved.get("rendered_proof"), proof_fields)
        if (resolved.get("choice") not in CHOICES
                or resolved.get("operation") not in {"send", "verify_unread", "mark_read"}
                or type(resolved.get("attempt")) is not int or resolved["attempt"] not in {0, 1, 2}
                or "evidence_source" in resolved and resolved["evidence_source"] != "existing_foreground_readback"):
            raise StateError("persisted resolution is invalid")
        for field, value in resolved["rendered_proof"].items():
            if field.endswith("_sha256"):
                require_hash(value, field)
            elif field == "read_state":
                if value not in {"read", "unread"}:
                    raise StateError("persisted read state is invalid")
            elif value is not True:
                raise StateError("persisted proof flag is invalid")
    for unresolved in data["unresolved"].values():
        require_fields(unresolved, {"reason", "retryable"})
        if unresolved.get("reason") not in {"ambiguous", "two_definitive_failures"} or unresolved.get("retryable") is not False:
            raise StateError("persisted failure reason is unsupported")
    reject_body_keys(data)


def validate_item(item: Any) -> dict[str, Any]:
    if not isinstance(item, dict):
        raise StateError("every inventory item must be an object")
    if item.get("materialized") is False:
        if set(item) - {"key", "materialized", "card"}:
            raise StateError("a provisional item contains only an opaque key and materialized=false")
        return {"key": require_string(item.get("key"), "item key"), "materialized": False}
    persisted = {key: item[key] for key in ITEM_FIELDS if key in item}
    missing = ITEM_FIELDS - persisted.keys()
    if missing:
        raise StateError(f"inventory item is missing: {', '.join(sorted(missing))}")
    persisted["key"] = require_string(persisted["key"], "item key")
    if persisted["service"] not in SERVICES:
        raise StateError("service must be imessage or sms")
    if persisted["kind"] not in KINDS:
        raise StateError("kind must be direct or group")
    count = persisted["participant_count"]
    if not isinstance(count, int) or isinstance(count, bool) or count < 1 or count > 100:
        raise StateError("participant_count must be an integer from 1 to 100")
    if persisted["kind"] == "direct" and count != 1:
        raise StateError("a direct conversation must have exactly one participant")
    if persisted["kind"] == "group" and count < 2:
        raise StateError("a group conversation must have at least two participants")
    for field in ("thread_sha256", "participants_sha256", "unread_sha256"):
        persisted[field] = require_hash(persisted[field], field)
    return persisted


def require_materialized(item: dict[str, Any]) -> None:
    if item.get("materialized") is False:
        raise StateError("bind the exact foreground identity before approval or UI; the user decision is retained")


def adaptive_window_size(latency_ms: Any, failures: Any) -> int:
    if not isinstance(latency_ms, int) or isinstance(latency_ms, bool) or latency_ms < 0:
        raise StateError("recent_latency_ms must be a non-negative integer")
    if not isinstance(failures, int) or isinstance(failures, bool) or failures < 0:
        raise StateError("recent_failures must be a non-negative integer")
    if latency_ms >= 2500 or failures >= 2:
        return 4
    if latency_ms >= 1200 or failures >= 1:
        return 3
    return 2


@contextlib.contextmanager
def state_lock(path: Path) -> Iterator[None]:
    lock_path = path.with_name(path.name + ".lock")
    flags = os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW | getattr(os, "O_CLOEXEC", 0)
    try:
        fd = os.open(lock_path, flags, 0o600)
    except OSError as exc:
        raise StateError("cannot safely open the manifest lock") from exc
    try:
        opened = os.fstat(fd)
        linked = lock_path.lstat()
        if (not stat.S_ISREG(opened.st_mode) or opened.st_nlink != 1
                or opened.st_uid != os.getuid() or stat.S_IMODE(opened.st_mode) != 0o600
                or (opened.st_dev, opened.st_ino) != (linked.st_dev, linked.st_ino)):
            raise StateError("manifest lock must be one private owned regular file")
        with os.fdopen(fd, "r+", encoding="utf-8", closefd=False) as handle:
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
            linked = lock_path.lstat()
            if (opened.st_dev, opened.st_ino) != (linked.st_dev, linked.st_ino):
                raise StateError("manifest lock identity changed")
            yield
            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)
    finally:
        os.close(fd)


def read_state(path: Path) -> dict[str, Any]:
    before = inspect_private_file(path)
    raw = path.read_text(encoding="utf-8")
    after = inspect_private_file(path)
    if (before.st_dev, before.st_ino, before.st_size) != (
        after.st_dev,
        after.st_ino,
        after.st_size,
    ):
        raise StateError("manifest identity changed during read")
    data = parse_json(raw)
    validate_persisted_shape(data)
    if not isinstance(data, dict) or data.get("schema_version") != SCHEMA_VERSION:
        raise StateError("unsupported manifest schema")
    if data.get("run_state", "active") not in {"active", "stopped"}:
        raise StateError("invalid run_state")
    reject_body_keys(data)
    inventory = data.get("inventory")
    if not isinstance(inventory, list) or not inventory:
        raise StateError("manifest inventory must be a non-empty list")
    keys = [validate_item(item)["key"] for item in inventory]
    if len(keys) != len(set(keys)):
        raise StateError("manifest contains duplicate item keys")
    return data


def atomic_write(path: Path, data: dict[str, Any]) -> None:
    validate_persisted_shape(data)
    encoded = (json.dumps(data, sort_keys=True, separators=(",", ":")) + "\n").encode()
    if len(encoded) > MAX_STATE_BYTES:
        raise StateError("manifest exceeds the size limit")
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    parent_mode = stat.S_IMODE(path.parent.stat().st_mode)
    if parent_mode & 0o077:
        raise StateError("manifest directory must not be accessible by group or others")
    fd, temp_name = tempfile.mkstemp(prefix=path.name + ".", dir=path.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "wb") as handle:
            handle.write(encoded)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp_name, path)
        os.chmod(path, 0o600)
    finally:
        if os.path.exists(temp_name):
            os.unlink(temp_name)


def read_stdin(limit: int = MAX_STDIN_CHARS) -> str:
    raw = sys.stdin.read(limit + 1)
    if len(raw) > limit:
        raise StateError("standard input exceeds the limit")
    return raw


def next_undecided(state: dict[str, Any]) -> str | None:
    decided = state["decisions"]
    for item in state["inventory"]:
        if item["key"] not in decided:
            return item["key"]
    return None


def item_by_key(state: dict[str, Any], key: str) -> dict[str, Any]:
    for item in state["inventory"]:
        if item["key"] == key:
            return item
    raise StateError(f"unknown item key: {key}")


def output(value: dict[str, Any]) -> None:
    print(json.dumps(value, sort_keys=True, separators=(",", ":")))


def require_active(state: dict[str, Any]) -> None:
    if state.get("run_state", "active") != "active":
        raise StateError("triage is stopped; explicit resume and fresh identity are required")


def command_bootstrap(args: argparse.Namespace) -> dict[str, Any]:
    path = Path(args.file)
    payload = parse_json(read_stdin())
    if not isinstance(payload, dict):
        raise StateError("bootstrap input must be an object")
    items = payload.get("items")
    if not isinstance(items, list) or not items:
        raise StateError("bootstrap requires at least one item")
    inventory = [validate_item(item) for item in items]
    keys = [item["key"] for item in inventory]
    if len(keys) != len(set(keys)):
        raise StateError("bootstrap item keys must be unique")
    cards = []
    for index, item in enumerate(items):
        card = item.get("card")
        if index == 0 and not isinstance(card, dict):
            raise StateError("the first item requires a transient card")
        cards.append(card)
    window_size = adaptive_window_size(
        payload.get("recent_latency_ms", 0), payload.get("recent_failures", 0)
    )
    if "preview_window_size" in payload:
        window_size = payload["preview_window_size"]
        if type(window_size) is not int or not 2 <= window_size <= 4:
            raise StateError("preview_window_size must be an integer from 2 to 4")
    window_cards = [card for card in cards[:window_size] if isinstance(card, dict)]
    preview_keys = [
        inventory[index]["key"]
        for index, card in enumerate(cards[:window_size])
        if index > 0 and isinstance(card, dict)
    ]
    snapshot_at = payload.get("snapshot_at") or datetime.now(timezone.utc).isoformat()
    try:
        observed = datetime.fromisoformat(snapshot_at.replace("Z", "+00:00"))
        if observed.tzinfo is None or observed.timestamp() > datetime.now(timezone.utc).timestamp() + 60:
            raise ValueError("unbound or future time")
    except (ValueError, TypeError, AttributeError) as exc:
        raise StateError("snapshot_at must be timezone-aware and not in the future; omit it to use the clock") from exc
    state = {
        "schema_version": SCHEMA_VERSION,
        "session_id": require_string(payload.get("session_id"), "session_id"),
        "snapshot_at": snapshot_at,
        "run_state": "active",
        "snapshot_frozen": True,
        "inventory": inventory,
        "active_key": inventory[0]["key"],
        "preview_keys": preview_keys,
        "decisions": {},
        "mutation_queue": [],
        "mutation_inflight": None,
        "resolved": {},
        "unresolved": {},
        "body_free": True,
    }
    with state_lock(path):
        if path.exists():
            raise StateError("bootstrap will not overwrite an existing manifest")
        atomic_write(path, state)
    return {
        "active_key": inventory[0]["key"],
        "first_card": window_cards[0],
        "preview_cards": window_cards[1:],
        "preview_window_size": window_size,
        "snapshot_total": len(inventory),
    }


def record_choice(state: dict[str, Any], key: str, choice: str) -> str | None:
    require_active(state)
    if key != state["active_key"]:
        raise StateError("decision key is not the currently presented active key")
    if key in state["decisions"]:
        raise StateError("this item already has a recorded decision")
    if choice not in CHOICES:
        raise StateError("invalid decision")
    state["decisions"][key] = {
        "choice": choice,
        "proof_state": "awaiting_approval" if choice == "reply" else "queued",
        "attempt_count": 0,
    }
    if choice != "reply":
        operation = "verify_unread" if choice == "leave_unread" else "mark_read"
        state["mutation_queue"].append({"key": key, "operation": operation})
        state["active_key"] = next_undecided(state)
    return state["active_key"]


def command_decide(args: argparse.Namespace) -> dict[str, Any]:
    path = Path(args.file)
    with state_lock(path):
        state = read_state(path)
        key = require_string(args.key, "key")
        choice = args.choice
        next_key = record_choice(state, key, choice)
        atomic_write(path, state)
    return {"decision_recorded": key, "choice": choice, "next_key": next_key}


def command_approve_send(args: argparse.Namespace) -> dict[str, Any]:
    path = Path(args.file)
    draft = read_stdin(MAX_DRAFT_CHARS)
    if not draft or not draft.strip():
        raise StateError("approved draft must not be empty")
    digest = hashlib.sha256(draft.encode("utf-8")).hexdigest()
    with state_lock(path):
        state = read_state(path)
        key = require_string(args.key, "key")
        require_active(state)
        item = item_by_key(state, key)
        require_materialized(item)
        decision = state["decisions"].get(key)
        if not decision or decision["choice"] != "reply":
            raise StateError("approve-send requires a recorded reply decision")
        if args.service != item["service"]:
            raise StateError("visible service does not match the frozen item")
        participants = require_hash(args.participants_sha256, "participants_sha256")
        if participants != item["participants_sha256"]:
            raise StateError("participant set does not match the frozen item")
        queued_index = next(
            (
                index
                for index, entry in enumerate(state["mutation_queue"])
                if entry["key"] == key and entry["operation"] == "send"
            ),
            None,
        )
        if args.replace:
            if state["mutation_inflight"] and state["mutation_inflight"]["key"] == key:
                raise StateError("cannot replace an approval after a UI attempt begins")
            if queued_index is None or decision.get("attempt_count", 0) != 0:
                raise StateError("approval replacement requires one unattempted queued send")
            state["mutation_queue"].pop(queued_index)
        elif decision.get("approval") is not None or queued_index is not None:
            raise StateError("this reply already has an approved send operation")
        version = int(decision.get("approval_version", 0)) + 1
        decision["approval_version"] = version
        decision["approval"] = {
            "draft_sha256": digest,
            "service": item["service"],
            "participants_sha256": participants,
        }
        decision["proof_state"] = "queued"
        state["mutation_queue"].append({"key": key, "operation": "send"})
        if not args.replace:
            state["active_key"] = next_undecided(state)
        atomic_write(path, state)
    return {
        "approved_key": key,
        "approval_version": version,
        "draft_sha256": digest,
        "next_key": state["active_key"],
    }


def command_claim(args: argparse.Namespace) -> dict[str, Any]:
    path = Path(args.file)
    with state_lock(path):
        state = read_state(path)
        require_active(state)
        if state["mutation_inflight"] is not None:
            raise StateError("one mutation is already inflight")
        if not state["mutation_queue"]:
            raise StateError("no mutation is queued")
        pending = state["mutation_queue"][0]
        sidebar_args = (args.key, args.sidebar_sha256, args.unread_sha256, args.unique_row)
        read_binding = None
        if any(sidebar_args):
            if pending["operation"] == "send":
                raise StateError("sidebar identity cannot authorize a send")
            if not all(sidebar_args) or args.key != pending["key"]:
                raise StateError("sidebar claim requires the oldest queued key, both hashes, and --unique-row")
            read_binding = {
                "sidebar_sha256": require_hash(args.sidebar_sha256, "sidebar_sha256"),
                "unread_sha256": require_hash(args.unread_sha256, "unread_sha256"),
            }
            previous = state["decisions"][pending["key"]].get("read_binding")
            if previous is not None and previous != read_binding:
                raise StateError("the frozen read-state identity cannot be replaced")
        else:
            if state["decisions"][pending["key"]].get("read_binding") is not None:
                raise StateError("reacquire the same sidebar identity before a read-state retry")
            require_materialized(item_by_key(state, pending["key"]))
            pending_decision = state["decisions"][pending["key"]]
            if (
                pending["operation"] == "send"
                and pending_decision.get("attempt_count", 0) >= 1
                and pending.get("fresh_read") is not True
            ):
                raise StateError("send retry requires fresh-read evidence")
        entry = state["mutation_queue"].pop(0)
        decision = state["decisions"][entry["key"]]
        attempts = int(decision.get("attempt_count", 0)) + 1
        if attempts > 2:
            raise StateError("operation attempt limit is exhausted")
        decision["attempt_count"] = attempts
        decision["proof_state"] = "inflight"
        if read_binding is not None:
            decision["read_binding"] = read_binding
        state["mutation_inflight"] = {**entry, "attempt": attempts}
        if read_binding is not None:
            state["mutation_inflight"]["read_binding"] = read_binding
        atomic_write(path, state)
    return {"mutation_inflight": state["mutation_inflight"]}


def command_verify(args: argparse.Namespace) -> dict[str, Any]:
    path = Path(args.file)
    with state_lock(path):
        state = read_state(path)
        key = require_string(args.key, "key")
        inflight = state["mutation_inflight"]
        if not inflight or inflight["key"] != key:
            raise StateError("verification key does not match the inflight mutation")
        proof = require_hash(args.proof_sha256, "proof_sha256")
        operation = inflight["operation"]
        if operation == "verify_unread" and args.read_state != "unread":
            raise StateError("leave-unread proof must show read_state=unread")
        if operation == "mark_read" and args.read_state != "read":
            raise StateError("mark-read proof must show read_state=read")
        rendered: dict[str, Any] = {"proof_sha256": proof}
        if "read_binding" in inflight:
            sidebar = require_hash(args.sidebar_sha256, "sidebar_sha256")
            if sidebar != inflight["read_binding"]["sidebar_sha256"]:
                raise StateError("rendered read-state proof does not match the claimed sidebar row")
            rendered["sidebar_sha256"] = sidebar
        if operation == "send":
            if not all(
                (
                    args.unique_outgoing,
                    args.composer_empty,
                    args.no_failure,
                    args.no_attribution,
                )
            ):
                raise StateError("send proof requires unique outgoing, empty composer, no failure, and no attribution")
            sent_message_sha256 = require_hash(
                args.sent_message_sha256, "sent_message_sha256"
            )
            approval = state["decisions"][key].get("approval")
            approved_sha256 = (
                approval.get("draft_sha256")
                if isinstance(approval, dict)
                else None
            )
            if sent_message_sha256 != approved_sha256:
                raise StateError("rendered sent message does not match approved draft")
            rendered["sent_message_sha256"] = sent_message_sha256
            rendered.update(
                {
                    "unique_outgoing": True,
                    "composer_empty": True,
                    "no_failure": True,
                    "no_attribution": True,
                }
            )
        else:
            rendered["read_state"] = args.read_state
        state["resolved"][key] = {
            "choice": state["decisions"][key]["choice"],
            "operation": operation,
            "attempt": inflight["attempt"],
            "rendered_proof": rendered,
        }
        state["decisions"][key]["proof_state"] = "resolved"
        state["mutation_inflight"] = None
        atomic_write(path, state)
    return {"resolved_key": key, "operation": operation, **status_summary(state)}


def command_record_failure(args: argparse.Namespace) -> dict[str, Any]:
    path = Path(args.file)
    with state_lock(path):
        state = read_state(path)
        key = require_string(args.key, "key")
        inflight = state["mutation_inflight"]
        if not inflight or inflight["key"] != key:
            raise StateError("failure key does not match the inflight mutation")
        decision = state["decisions"][key]
        if args.outcome == "ambiguous":
            decision["proof_state"] = "ambiguous"
            state["unresolved"][key] = {"reason": "ambiguous", "retryable": False}
        elif args.outcome == "definitive_failure":
            retrying_send = (
                inflight["operation"] == "send" and decision["attempt_count"] < 2
            )
            if retrying_send and not args.fresh_read:
                raise StateError(
                    "definitive send failure requires --fresh-read before retry"
                )
            if decision["attempt_count"] < 2:
                decision["proof_state"] = "queued"
                retry_entry = {"key": key, "operation": inflight["operation"]}
                if retrying_send:
                    retry_entry["fresh_read"] = True
                state["mutation_queue"].insert(0, retry_entry)
            else:
                decision["proof_state"] = "blocked"
                state["unresolved"][key] = {
                    "reason": "two_definitive_failures",
                    "retryable": False,
                }
        else:
            raise StateError("invalid failure outcome")
        state["mutation_inflight"] = None
        atomic_write(path, state)
    return {"failure_key": key, "outcome": args.outcome, **status_summary(state)}


def command_reconcile_read(args: argparse.Namespace) -> dict[str, Any]:
    """Record existing rendered evidence without claiming/replaying a UI attempt."""
    path = Path(args.file)
    with state_lock(path):
        state = read_state(path)
        key = require_string(args.key, "key")
        if state["mutation_inflight"] is not None:
            raise StateError("reconcile the inflight operation through verify before another item")
        if not state["mutation_queue"] or state["mutation_queue"][0]["key"] != key:
            raise StateError("reconcile-read requires the oldest queued read-state item")
        pending = state["mutation_queue"][0]
        decision = state["decisions"][key]
        if pending["operation"] == "send" or decision.get("attempt_count", 0) != 0:
            raise StateError("reconcile-read is only for unclaimed read-state actions, never sends or retries")
        expected = "unread" if pending["operation"] == "verify_unread" else "read"
        if args.read_state != expected or not args.unique_row:
            raise StateError("existing readback must prove the exact unique row and requested read state")
        binding = {
            "sidebar_sha256": require_hash(args.sidebar_sha256, "sidebar_sha256"),
            "unread_sha256": require_hash(args.unread_sha256, "unread_sha256"),
        }
        proof = require_hash(args.proof_sha256, "proof_sha256")
        decision["read_binding"] = binding
        decision["proof_state"] = "resolved"
        state["resolved"][key] = {
            "choice": decision["choice"],
            "operation": pending["operation"],
            "attempt": 0,
            "evidence_source": "existing_foreground_readback",
            "rendered_proof": {
                "proof_sha256": proof,
                "sidebar_sha256": binding["sidebar_sha256"],
                "read_state": args.read_state,
            },
        }
        state["mutation_queue"].pop(0)
        atomic_write(path, state)
    return {"reconciled_key": key, "no_ui_replay": True, **status_summary(state)}


def status_summary(state: dict[str, Any]) -> dict[str, Any]:
    total = len(state["inventory"])
    resolved = len(state["resolved"])
    unresolved = len(state["unresolved"])
    complete = (
        resolved == total
        and unresolved == 0
        and state["mutation_inflight"] is None
        and not state["mutation_queue"]
        and state["active_key"] is None
    )
    return {
        "run_state": state.get("run_state", "active"),
        "ui_paused": state.get("run_state", "active") == "stopped",
        "snapshot_total": total,
        "decisions_recorded": len(state["decisions"]),
        "resolved_count": resolved,
        "unresolved_count": unresolved,
        "active_key": state["active_key"],
        "queued_count": len(state["mutation_queue"]),
        "mutation_inflight": state["mutation_inflight"],
        "snapshot_verified": complete,
    }


def command_status(args: argparse.Namespace) -> dict[str, Any]:
    state = read_state(Path(args.file))
    return status_summary(state)


def command_validate(args: argparse.Namespace) -> dict[str, Any]:
    state = read_state(Path(args.file))
    return {"valid": True, "body_free": True, **status_summary(state)}


def command_stop(args: argparse.Namespace) -> dict[str, Any]:
    path = Path(args.file)
    with state_lock(path):
        state = read_state(path)
        require_active(state)
        if bool(args.key) != bool(args.choice):
            raise StateError("stop intent requires both --key and --choice")
        if args.key:
            record_choice(state, require_string(args.key, "key"), args.choice)
        state["run_state"] = "stopped"
        state["preview_keys"] = []
        atomic_write(path, state)
    return {"stopped": True, "intent_recorded": args.key, **status_summary(state)}


def command_materialize(args: argparse.Namespace) -> dict[str, Any]:
    payload = parse_json(read_stdin())
    if not isinstance(payload, dict) or set(payload) != ITEM_FIELDS:
        raise StateError("materialize requires exactly the body-free identity fields")
    identity = validate_item(payload)
    if identity["key"] != args.key:
        raise StateError("identity key does not match the selected item")
    path = Path(args.file)
    with state_lock(path):
        state = read_state(path)
        require_active(state)
        mutation_key = state["mutation_queue"][0]["key"] if state["mutation_queue"] else None
        if args.key not in {state["active_key"], mutation_key}:
            raise StateError("materialize only the visible or oldest queued item")
        item = item_by_key(state, args.key)
        if item.get("materialized") is not False and item != identity:
            raise StateError("the existing frozen identity cannot be replaced")
        item.clear()
        item.update(identity)
        atomic_write(path, state)
    return {"materialized_key": args.key, **status_summary(state)}


def command_resume(args: argparse.Namespace) -> dict[str, Any]:
    if not args.fresh_identity:
        raise StateError("resume requires --fresh-identity after the foreground identity check")
    path = Path(args.file)
    with state_lock(path):
        state = read_state(path)
        if state.get("run_state", "active") != "stopped":
            raise StateError("run is not stopped")
        state["run_state"] = "active"
        state["preview_keys"] = []
        atomic_write(path, state)
    return {"resumed": True, **status_summary(state)}


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    bootstrap = subparsers.add_parser("bootstrap")
    bootstrap.add_argument("--file", required=True)
    bootstrap.set_defaults(handler=command_bootstrap)

    decide = subparsers.add_parser("decide")
    decide.add_argument("--file", required=True)
    decide.add_argument("--key", required=True)
    decide.add_argument("--choice", choices=sorted(CHOICES), required=True)
    decide.set_defaults(handler=command_decide)

    approve = subparsers.add_parser("approve-send")
    approve.add_argument("--file", required=True)
    approve.add_argument("--key", required=True)
    approve.add_argument("--service", choices=sorted(SERVICES), required=True)
    approve.add_argument("--participants-sha256", required=True)
    approve.add_argument("--replace", action="store_true")
    approve.set_defaults(handler=command_approve_send)

    claim = subparsers.add_parser("claim")
    claim.add_argument("--file", required=True)
    claim.add_argument("--key")
    claim.add_argument("--sidebar-sha256")
    claim.add_argument("--unread-sha256")
    claim.add_argument("--unique-row", action="store_true")
    claim.set_defaults(handler=command_claim)

    verify = subparsers.add_parser("verify")
    verify.add_argument("--file", required=True)
    verify.add_argument("--key", required=True)
    verify.add_argument("--proof-sha256", required=True)
    verify.add_argument("--sidebar-sha256")
    verify.add_argument("--read-state", choices=("read", "unread"))
    verify.add_argument("--unique-outgoing", action="store_true")
    verify.add_argument("--composer-empty", action="store_true")
    verify.add_argument("--no-failure", action="store_true")
    verify.add_argument("--no-attribution", action="store_true")
    verify.add_argument("--sent-message-sha256")
    verify.set_defaults(handler=command_verify)

    failure = subparsers.add_parser("record-failure")
    failure.add_argument("--file", required=True)
    failure.add_argument("--key", required=True)
    failure.add_argument(
        "--outcome", choices=("definitive_failure", "ambiguous"), required=True
    )
    failure.add_argument(
        "--fresh-read",
        action="store_true",
        help="prove a fresh rendered destination read before a send retry",
    )
    failure.set_defaults(handler=command_record_failure)

    stop = subparsers.add_parser("stop")
    stop.add_argument("--file", required=True)
    stop.add_argument("--key")
    stop.add_argument("--choice", choices=sorted(CHOICES))
    stop.set_defaults(handler=command_stop)

    resume = subparsers.add_parser("resume")
    resume.add_argument("--file", required=True)
    resume.add_argument("--fresh-identity", action="store_true")
    resume.set_defaults(handler=command_resume)

    materialize = subparsers.add_parser("materialize")
    materialize.add_argument("--file", required=True)
    materialize.add_argument("--key", required=True)
    materialize.set_defaults(handler=command_materialize)

    reconcile = subparsers.add_parser("reconcile-read")
    reconcile.add_argument("--file", required=True)
    reconcile.add_argument("--key", required=True)
    reconcile.add_argument("--sidebar-sha256", required=True)
    reconcile.add_argument("--unread-sha256", required=True)
    reconcile.add_argument("--proof-sha256", required=True)
    reconcile.add_argument("--unique-row", action="store_true")
    reconcile.add_argument("--read-state", choices=("read", "unread"), required=True)
    reconcile.set_defaults(handler=command_reconcile_read)

    for name, handler in (("status", command_status), ("validate", command_validate)):
        command = subparsers.add_parser(name)
        command.add_argument("--file", required=True)
        command.set_defaults(handler=handler)
    return parser


def main() -> int:
    try:
        args = build_parser().parse_args()
        output(args.handler(args))
        return 0
    except (OSError, StateError, ValueError) as exc:
        print(json.dumps({"error": str(exc)}, sort_keys=True), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
