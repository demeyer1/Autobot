import crypto from 'node:crypto';

// Requirements refine an existing deliverable. They never grant action authority.
const hash = value => crypto.createHash('sha256').update(JSON.stringify(value)).digest('hex');
const text = (value, field, max = 800) => {
  if (typeof value !== 'string' || !value.trim() || value.length > max) throw new Error(`invalid requirement ${field}`);
  return value.trim();
};
export function requirementSource(root) {
  return hash([root.intent_sha256 || root.prompt_sha256, root.intent_revision || 1, root.corrections || []]);
}
export function reviseRequirements(previous, input, root, now = new Date()) {
  if (!Array.isArray(input) || !input.length || input.length > 64) throw new Error('requirements must contain 1–64 items');
  for (const item of input) {
    if (!item || typeof item !== 'object' || Array.isArray(item)) throw new Error('invalid requirement item');
    if (item.depends_on !== undefined && !Array.isArray(item.depends_on)) throw new Error('requirement dependencies must be an array');
    if (item.mandatory !== undefined && typeof item.mandatory !== 'boolean') throw new Error('requirement mandatory must be a boolean');
  }
  const items = input.map((item, i) => ({
    id: text(item.id || previous?.items?.[i]?.id || `r${i + 1}`, 'id', 64),
    summary: text(item.summary, 'summary'),
    target: text(item.target, 'target'),
    mandatory: item.mandatory !== false,
    depends_on: [...new Set(item.depends_on || [])].sort(),
  }));
  const ids = new Set(items.map(item => item.id));
  if (ids.size !== items.length) throw new Error('duplicate requirement id');
  for (const item of items) {
    if (!Array.isArray(item.depends_on) || item.depends_on.some(id => typeof id !== 'string' || !ids.has(id))) throw new Error('unknown requirement dependency');
  }
  const visiting = new Set(), visited = new Set();
  function visit(id) {
    if (visiting.has(id)) throw new Error('cyclic requirement dependency');
    if (visited.has(id)) return;
    visiting.add(id);
    for (const dependency of items.find(item => item.id === id).depends_on) visit(dependency);
    visiting.delete(id); visited.add(id);
  }
  for (const id of ids) visit(id);
  const source = requirementSource(root);
  // A producer cannot silently drop or downgrade an obligation. A new user
  // intent permits a replacement contract, which must receive fresh review.
  if (previous && previous.source_revision === source) {
    for (const prior of previous.items) {
      const next = items.find(item => item.id === prior.id);
      if (!next || (prior.mandatory && !next.mandatory)) throw new Error('removing or downgrading a requirement needs a changed user intent');
    }
  }
  const digest = hash([source, items]);
  if (previous?.digest === digest) return structuredClone(previous);
  return {
    version: 1, revision: (previous?.revision || 0) + 1, source_revision: source,
    digest, items, support: [], coverage: null, updated_at: now.toISOString(),
    history: [...(previous?.history || []), ...(previous ? [{ revision: previous.revision, digest: previous.digest, items: previous.items, support: previous.support, coverage: previous.coverage }] : [])],
  };
}
export function reviewRequirements(contract, root, deliverable, stage, attestation, now = new Date()) {
  if (!contract) return null;
  if (contract.source_revision !== requirementSource(root)) throw new Error('requirements need revision after user correction');
  if (attestation.requirement_digest !== contract.digest) throw new Error('requirement review must bind the current digest');
  const result = structuredClone(contract);
  for (const judgment of attestation.requirement_support || []) {
    const item = result.items.find(item => item.id === judgment.requirement_id);
    const evidence = stage.evidence.find(e => e.evidence_id === judgment.evidence_id);
    if (!item || !evidence || !['supported', 'unsupported', 'unknown'].includes(judgment.result)) throw new Error('invalid requirement support binding');
    if (attestation.validator_id === evidence.producer_id) throw new Error('requirement validator must be independent of evidence producer');
    const entry = {
      requirement_id: item.id, evidence_id: evidence.evidence_id, stage: attestation.stage,
      result: judgment.result, reason: text(judgment.reason, 'review reason'),
      digest: contract.digest, attempt_id: deliverable.attempt_id,
      content_sha256: deliverable.expected_content_sha256,
      validator_id: attestation.validator_id, validated_at: now.toISOString(),
    };
    result.support = result.support.filter(s => s.requirement_id !== item.id);
    result.support.push(entry);
  }
  if (attestation.requirement_coverage) {
    const coverage = attestation.requirement_coverage;
    if (typeof coverage.all_requested_clauses_covered !== 'boolean') throw new Error('explicit requirement coverage judgment required');
    result.coverage = { digest: contract.digest, all_requested_clauses_covered: coverage.all_requested_clauses_covered,
      reason: text(coverage.reason, 'coverage reason'), validator_id: attestation.validator_id,
      attempt_id: deliverable.attempt_id, validated_at: now.toISOString() };
  }
  return result;
}
export function requirementReadiness(root, deliverable) {
  const c = deliverable.requirements;
  if (!c) return { enabled: false, ready: true, total: 0, unsupported: [] };
  if (c.version !== 1 || !Array.isArray(c.items) || !c.items.length || !Array.isArray(c.support)) return { enabled: true, ready: false, reason: 'invalid requirement contract', unsupported: [] };
  const current = c.source_revision === requirementSource(root) && c.digest === hash([c.source_revision, c.items]);
  const supported = new Set(c.support.filter(s => {
    const stage = deliverable.stages?.[s.stage];
    return s.result === 'supported' && s.digest === c.digest && s.attempt_id === deliverable.attempt_id
      && s.content_sha256 === deliverable.expected_content_sha256
      && stage?.status === 'validated' && stage.validator_id === s.validator_id
      && stage.attempt_id === s.attempt_id
      && (!stage.invalidated_at || Date.parse(s.validated_at) > Date.parse(stage.invalidated_at))
      && stage.evidence?.some(e => e.evidence_id === s.evidence_id && e.producer_id !== s.validator_id);
  }).map(s => s.requirement_id));
  const needed = new Set();
  const byId = new Map(c.items.map(i => [i.id, i]));
  let malformed = byId.size !== c.items.length;
  function require(id, visiting = new Set()) {
    if (visiting.has(id) || !byId.has(id)) { malformed = true; return; }
    if (needed.has(id)) return;
    const next = new Set(visiting); next.add(id);
    for (const dep of byId.get(id).depends_on || []) require(dep, next);
    needed.add(id);
  }
  c.items.filter(i => i.mandatory).forEach(i => require(i.id));
  const unsupported = [...needed].filter(id => !supported.has(id));
  const coverage = c.coverage?.digest === c.digest && c.coverage?.all_requested_clauses_covered === true
    && c.coverage.attempt_id === deliverable.attempt_id;
  return { enabled: true, ready: current && !malformed && coverage && unsupported.length === 0,
    total: c.items.length, mandatory: needed.size, supported: [...needed].filter(id => supported.has(id)).length,
    unsupported, revision: c.revision, digest: c.digest, source_current: current, coverage_reviewed: coverage };
}
