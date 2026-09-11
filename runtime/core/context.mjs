import crypto from "node:crypto";

const PHASES = new Set(["producer", "validator", "recovery"]);
const OPEN_PREFIX = "<!-- AUTOBOT_CONTEXT_CAPSULE_V1:";
const CLOSE_PREFIX = "<!-- /AUTOBOT_CONTEXT_CAPSULE_V1:";

function sha256(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function utf8Bytes(value) {
  return Buffer.byteLength(value, "utf8");
}

function fullResult({ taskBody, sourceSha256, reason }) {
  const bytes = utf8Bytes(taskBody);
  return {
    mode: "full",
    reason,
    source_sha256: sourceSha256,
    source_utf8_bytes: bytes,
    emitted_utf8_bytes: bytes,
    saved_utf8_bytes: 0,
    text: taskBody,
  };
}

function extractCapsules(taskBody) {
  const capsules = new Map();
  const markerPattern = /<!--\s*(\/?)AUTOBOT_CONTEXT_CAPSULE_V1:([a-z]+)\s*-->/g;
  const markers = [...taskBody.matchAll(markerPattern)].map((match) => ({
    closing: match[1] === "/",
    phase: match[2],
    start: match.index,
    end: match.index + match[0].length,
  }));

  if ((taskBody.includes(OPEN_PREFIX) || taskBody.includes(CLOSE_PREFIX)) && markers.length === 0) {
    throw new Error("unparseable capsule marker");
  }

  for (let index = 0; index < markers.length; index += 2) {
    const open = markers[index];
    const close = markers[index + 1];
    if (!open || open.closing || !close || !close.closing || close.phase !== open.phase) {
      throw new Error("unbalanced capsule markers");
    }
    if (!PHASES.has(open.phase) || capsules.has(open.phase)) {
      throw new Error("unknown or duplicate capsule phase");
    }
    const content = taskBody.slice(open.end, close.start).trim();
    if (!content) throw new Error("empty capsule");
    capsules.set(open.phase, content);
  }
  if (markers.length % 2 !== 0) throw new Error("unbalanced capsule markers");
  return capsules;
}

export function compileTaskContext({
  taskPath,
  taskBody,
  phase,
  maxCapsuleUtf8Bytes = 8192,
}) {
  if (typeof taskPath !== "string" || !taskPath.startsWith("/")) {
    throw new Error("taskPath must be an absolute path");
  }
  if (typeof taskBody !== "string" || taskBody.length === 0) {
    throw new Error("taskBody must be a nonempty string");
  }
  if (!PHASES.has(phase)) throw new Error(`unsupported context phase: ${phase}`);
  if (!Number.isSafeInteger(maxCapsuleUtf8Bytes) || maxCapsuleUtf8Bytes < 512) {
    throw new Error("maxCapsuleUtf8Bytes must be an integer of at least 512");
  }

  const sourceSha256 = sha256(taskBody);
  let capsules;
  try {
    capsules = extractCapsules(taskBody);
  } catch (error) {
    return fullResult({
      taskBody,
      sourceSha256,
      reason: `capsule-invalid:${error.message}`,
    });
  }

  const capsule = capsules.get(phase);
  if (!capsule) {
    return fullResult({ taskBody, sourceSha256, reason: "capsule-absent" });
  }
  if (utf8Bytes(capsule) > maxCapsuleUtf8Bytes) {
    return fullResult({ taskBody, sourceSha256, reason: "capsule-over-budget" });
  }

  const text = `Capability-specific task capsule (${phase})\nSource: ${taskPath}\nSource SHA-256: ${sourceSha256}\n\n${capsule}\n\nThe complete immutable task contract remains at ${taskPath}. Read it if the capsule explicitly directs you there, if evidence conflicts, or if a detail required by the completion gate is absent. The source contract remains authoritative.`;
  const emittedBytes = utf8Bytes(text);
  const sourceBytes = utf8Bytes(taskBody);
  if (emittedBytes >= sourceBytes) {
    return fullResult({ taskBody, sourceSha256, reason: "capsule-not-smaller" });
  }

  return {
    mode: "capsule",
    reason: "valid-opt-in-capsule",
    source_sha256: sourceSha256,
    source_utf8_bytes: sourceBytes,
    emitted_utf8_bytes: emittedBytes,
    saved_utf8_bytes: sourceBytes - emittedBytes,
    text,
  };
}

