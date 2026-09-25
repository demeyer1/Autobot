#!/usr/bin/env node
/** Bounded publication-only scanner. Never point this at a configured installation.
 * Generic detection is not semantic privacy review or authentication of reviewers. */
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import { inflateSync } from 'node:zlib';
import { fileURLToPath } from 'node:url';

export const LIMITS = Object.freeze({ files: 4096, bytes: 64 * 1024 * 1024, file: 2 * 1024 * 1024, line: 256 * 1024, decoded: 1024 * 1024, depth: 4, views: 512 });
export const hash = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
export class ScanError extends Error { constructor(rule) { super(rule); this.rule = rule; } }
export function reject(rule) { throw new ScanError(rule); }
export function safeRelative(value) {
  return typeof value === 'string' && value.length > 0 && value.length <= 512 && !value.startsWith('/') && !value.includes('\\') && /^[A-Za-z0-9._/-]+$/.test(value) && !/[\x00-\x20\x7f:]/.test(value) && value.split('/').every(s => s && s !== '.' && s !== '..' && !/[. ]$/.test(s));
}
export function safeAbsolute(value, { directory = false } = {}) {
  if (typeof value !== 'string' || !path.isAbsolute(value) || value.split(path.sep).includes('..')) reject('unsafe_root');
  const resolved = path.resolve(value);
  const forbidden = ['Desktop', 'Documents', 'Downloads', 'Mobile Documents', 'Photos Library.photoslibrary'];
  if (resolved === path.parse(resolved).root || resolved === os.homedir() || ['00_CONTEXT', '01_PROJECTS'].includes(path.basename(resolved)) || resolved.split(path.sep).some(s => forbidden.includes(s)) || resolved.startsWith('/Volumes/')) reject('unsafe_root');
  let current = path.parse(resolved).root;
  for (const segment of resolved.slice(current.length).split(path.sep).filter(Boolean)) {
    current = path.join(current, segment);
    const s = fs.lstatSync(current);
    if (s.isSymbolicLink()) reject('symlink');
  }
  const s = fs.lstatSync(resolved);
  if (directory ? !s.isDirectory() : !s.isFile() || s.nlink !== 1) reject('nonregular');
  return resolved;
}
export function readBounded(file, max = LIMITS.file) {
  safeAbsolute(file);
  const fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW);
  try {
    const a = fs.fstatSync(fd);
    if (!Number.isSafeInteger(max) || max < 0 || max > 128 * 1024 * 1024 || !a.isFile() || a.nlink !== 1 || a.size > max) reject('input_limit');
    // Read exactly the admitted size, then probe one byte. Growth never causes
    // an unbounded allocation or a read of the rest of a changing file.
    const bytes = Buffer.alloc(a.size); let used = 0;
    while (used < bytes.length) {
      const count = fs.readSync(fd, bytes, used, bytes.length - used, used);
      if (!count) reject('input_changed'); used += count;
    }
    const extra = Buffer.alloc(1); const grew = fs.readSync(fd, extra, 0, 1, a.size); const b = fs.fstatSync(fd);
    if (grew || a.ino !== b.ino || a.size !== b.size || a.mtimeMs !== b.mtimeMs || a.ctimeMs !== b.ctimeMs || bytes.length !== a.size) reject('input_changed');
    return bytes;
  } finally { fs.closeSync(fd); }
}
export function parseAllowlist(bytes) {
  let text; try { text = new TextDecoder('utf-8', { fatal: true }).decode(bytes); } catch { reject('allowlist_encoding'); }
  if (!text.endsWith('\n') || text.includes('\r')) reject('allowlist_grammar');
  const files = text.slice(0, -1).split('\n');
  if (!files.length || files.length > LIMITS.files || files.some(x => !safeRelative(x)) || new Set(files.map(x => x.toLowerCase())).size !== files.length || files.join('\n') !== [...files].sort().join('\n')) reject('allowlist_grammar');
  const set = new Set(files.map(x => x.toLowerCase()));
  for (const file of files) { let parent = path.posix.dirname(file).toLowerCase(); while (parent !== '.') { if (set.has(parent)) reject('allowlist_path_collision'); parent = path.posix.dirname(parent); } }
  return files;
}
function filenameRules(relative) {
  const segments = relative.split('/'); const name = segments.at(-1).toLowerCase();
  if (segments.some(s => s.startsWith('.')) && relative !== '.gitignore') reject('hidden_path');
  if (segments.some(s => ['state', 'dist', '.release', 'node_modules', '__MACOSX'].includes(s))) reject('private_or_generated_path');
  if (/^(credentials?|secrets?)(\.|$)|^id_(rsa|dsa|ecdsa|ed25519)$|^authorized_keys$|^known_hosts$/.test(name) || /\.(env|pem|key|p12|pfx|jks|keystore|log|bak|backup|orig|rej|swp|swo|db|sqlite|sqlite3)$/.test(name) || name.endsWith('~')) reject('forbidden_file');
}
// Decimal digits are normalized before any financial grammar runs.  NFKC
// handles full-width forms; the explicit block list covers the common Arabic,
// Indic and other decimal sets without depending on locale or a network
// service.  This is intentionally a small, deterministic detector, not a
// payment processor.
const DECIMAL_BLOCKS = Object.freeze([
  0x0660, 0x06f0, 0x07c0, 0x0966, 0x09e6, 0x0a66, 0x0ae6, 0x0b66,
  0x0be6, 0x0c66, 0x0ce6, 0x0d66, 0x0de6, 0x0e50, 0x0ed0, 0x0f20,
  0x1040, 0x1090, 0x17e0, 0x1810, 0x1946, 0x19d0, 0x1a80, 0x1a90,
  0x1b50, 0x1bb0, 0x1c40, 0x1c50, 0xa620, 0xa8d0, 0xa900, 0xa9d0,
  0xa9f0, 0xaa50, 0xabf0, 0xff10, 0x104a0, 0x10d30, 0x11066, 0x110f0,
  0x11136, 0x111d0, 0x112f0, 0x11450, 0x114d0, 0x11650, 0x116c0,
  0x11730, 0x118e0, 0x11950, 0x11c50, 0x11d50, 0x11da0, 0x16a60,
  0x16ac0, 0x16b50, 0x1d7ce, 0x1d7d8, 0x1d7e2, 0x1d7ec, 0x1d7f6,
]);

function decimalDigitValue(character) {
  const folded = character.normalize('NFKC');
  if (folded.length === 1 && folded >= '0' && folded <= '9') return folded.charCodeAt(0) - 48;
  const codePoint = character.codePointAt(0);
  for (const start of DECIMAL_BLOCKS) if (codePoint >= start && codePoint <= start + 9) return codePoint - start;
  return null;
}

export function normalizeDecimalDigits(text) {
  let normalized = '';
  for (const character of text) {
    const digit = decimalDigitValue(character);
    normalized += digit === null ? character : String(digit);
  }
  return normalized;
}

function decodeNumericEntities(text) {
  return text.replace(/&#(?:x([0-9a-f]{1,6})|([0-9]{1,7}));/gi, (raw, hex, decimal) => {
    const codePoint = Number.parseInt(hex || decimal, hex ? 16 : 10);
    if (!Number.isInteger(codePoint) || codePoint < 0 || codePoint > 0x10ffff || (codePoint >= 0xd800 && codePoint <= 0xdfff)) return raw;
    try { return String.fromCodePoint(codePoint); } catch { return raw; }
  });
}

export function luhnValid(digits) {
  if (!/^\d{12,19}$/.test(digits)) return false;
  let sum = 0;
  let alternate = false;
  for (let index = digits.length - 1; index >= 0; index--) {
    let value = Number(digits[index]);
    if (alternate) { value *= 2; if (value > 9) value -= 9; }
    sum += value;
    alternate = !alternate;
  }
  return sum % 10 === 0;
}

function cardIssuerLengthContext(digits) {
  const length = digits.length;
  const first = digits[0];
  const firstTwo = Number(digits.slice(0, 2));
  const firstThree = Number(digits.slice(0, 3));
  const firstFour = Number(digits.slice(0, 4));
  if (first === '4') return [13, 16, 19].includes(length); // Visa-family
  if (firstTwo === 34 || firstTwo === 37) return length === 15; // Amex-family
  if ((firstTwo >= 51 && firstTwo <= 55) || (firstFour >= 2221 && firstFour <= 2720)) return length === 16; // Mastercard-family
  if (digits.startsWith('6011') || firstTwo === 65 || (firstThree >= 644 && firstThree <= 649)) return [16, 19].includes(length); // Discover-family
  if (firstFour >= 3528 && firstFour <= 3589) return length >= 16 && length <= 19; // JCB-family
  if (firstTwo === 62) return length >= 16 && length <= 19; // UnionPay-family
  if ((firstThree >= 300 && firstThree <= 305) || firstTwo === 36 || firstTwo === 38) return length === 14; // Diners-family
  return false;
}

const financialFieldPatterns = Object.freeze([
  ['payment_cvv', /(?:^|[^a-z0-9_])(?:cvv|cvc|cvv2|cvc2|cvn|cvn2|cid|card[\s_-]*identification(?:[\s_-]*number)?|security[\s_-]+code)(?:[\s_-]+(?:number|code))?[\s"'`_-]*[:=#-]?[\s"'`_-]*[0-9]{3,4}(?:[^0-9]|$)/i],
  ['payment_pin', /(?:^|[^a-z0-9_])(?:pin|pin[\s_-]+code|passcode|security[\s_-]+pin)(?:[\s_-]+(?:number|code))?[\s"'`_-]*[:=#-]?[\s"'`_-]*[0-9]{4,8}(?:[^0-9]|$)/i],
  ['pin_block', /(?:^|[^a-z0-9_])(?:encrypted[\s_-]*)?pin[\s_-]*block[\s"'`_-]*[:=#-]?[\s"'`_-]*[0-9a-f]{8,}(?:[^0-9a-f]|$)/i],
  ['bank_routing_number', /(?:^|[^a-z0-9_])(?:routing|routing[\s_-]+number|aba|aba[\s_-]+routing|transit[\s_-]+number|institution[\s_-]+number)[\s"'`_-]*(?:[:=#-][\s"'`_-]*|[\s"'`_-]+)[0-9](?:[0-9\s"'`_-]{7,14}[0-9])?(?:[^0-9]|$)/i],
  ['bank_account_number', /(?:^|[^a-z0-9_])(?:bank[\s_-]+account|account[\s_-]+number|checking[\s_-]+account|savings[\s_-]+account)[\s"'`_-]*(?:[:=#-][\s"'`_-]*|[\s"'`_-]+)[0-9](?:[0-9\s"'`_-]{2,32}[0-9])?(?:[^0-9]|$)/i],
  ['bank_iban', /(?:^|[^a-z0-9_])iban[\s_-]*[:=#-]?[\s"'`_-]*[A-Z]{2}[0-9A-Z](?:[0-9A-Z\s"'`_-]{12,32}[0-9A-Z])?(?:[^0-9A-Z]|$)/i],
  ['payment_expiry', /(?:^|[^a-z0-9_])(?:expiry|expiration|exp(?:iry|iration)?|valid[\s_-]*(?:thru|through)|card[\s_-]*expiry|exp[\s_-]*(?:month|year))[\s"'`_-]*[:=#-]?[\s"'`_-]*[0-9]{1,4}(?:[\s./-]+[0-9]{2,4})?(?:[^0-9]|$)/i],
  ['payment_service_code', /(?:^|[^a-z0-9_])service[\s_-]*code[\s"'`_-]*[:=#-]?[\s"'`_-]*[0-9]{3,4}(?:[^0-9]|$)/i],
  ['masked_card', /(?:^|[^a-z0-9_])(?:card|credit[\s_-]*card|debit[\s_-]*card|pan|billing[\s_-]*card)[\s"'=:_-]*(?:[*xX#•·][\s"'=:_.-]*){2,}[0-9]{4}(?:[^0-9]|$)/i],
]);
const trackDataPatterns = Object.freeze([
  /(?:^|[\r\n])%B[0-9]{12,19}\^[^\r\n^]{1,64}\^[0-9]{4,6}\?/i,
  /(?:^|[^0-9]);[0-9]{12,19}=[0-9]{4,6}\?(?:[^0-9]|$)/,
  /(?:^|[\r\n])%B[0-9\s./-]{4,}/i,
  /(?:^|[^0-9]);[0-9\s./-]{4,}(?:=|$)/,
]);
const contextualCardPattern = /(?:^|[^a-z0-9])(?:card|credit[\s_-]+card|debit[\s_-]+card|pan|primary[\s_-]+account|billing(?:[\s_-]+(?:card|account|payment|number))?)(?=[^a-z0-9]|$)/gi;
const paymentTokenPlaceholderPattern = /(?:^|[^a-z0-9_])(?:(?:payment|card|billing|network|source)[\s_-]*(?:token|method[\s_-]*id)|tokenized[\s_-]*pan)[\s"'_-]*[:=#-][\s"'_-]*(?:redacted|placeholder|synthetic|example|none|null|unknown|masked|n\/?a)(?:[^a-z0-9_-]|$)/i;
const maskedCardNumberPattern = /(?:^|[^a-z0-9_])(?:card|credit[\s_-]*card|debit[\s_-]*card|pan|billing[\s_-]*card)[\s_-]*number[\s"'=:_-]*(?:[*xX#•·][\s"=:_.-]*){2,}[0-9]{4}(?:[^0-9]|$)/i;
const labelledTrackPattern = /(?:^|[^a-z0-9_])track[\s_-]*(?:1|2|one|two)[\s"'`_-]*[:=#-][\s"'`_-]*[0-9]{4,19}=/i;
const paymentTokenFieldPattern = /(?<![a-z0-9_])(?:(?:(?:payment|card|billing|network|source)[\s_-]*(?:token|method[\s_-]*id)|tokenized[\s_-]*pan)[\s"'`_-]*[:=#-][\s"'`_-]*([a-z0-9_-]+)|((?:tok_)[a-z0-9_-]+))(?![a-z0-9_-])/gi;
const explicitPlaceholderPattern = /^(?:redacted|placeholder|synthetic|example|none|null|unknown|masked|n\/?a|card(?:[ _-]?number)?)$/i;
const populatedTextFieldPatterns = Object.freeze([
  ['billing_field', /(?<![a-z0-9_])billing[\s_-]*address[\s"'`_-]*[:=#-][\s_-]*(?:"([^"\r\n]*)"|'([^'\r\n]*)'|([^\s,;}]+))/gi],
  ['cardholder_name', /(?<![a-z0-9_])card[\s_-]*holder(?:[\s_-]*name)?[\s"'`_-]*[:=#-][\s_-]*(?:"([^"\r\n]*)"|'([^'\r\n]*)'|([^\s,;}]+))/gi],
]);
const paymentExpiryFieldPattern = /(?:^|[^a-z0-9])(?:expiry|expiration|exp(?:iry|iration)?|valid[\s_-]*(?:thru|through)|card[\s_-]*expiry)(?:[\s_-]*(?:date|month|year))?[\s"'_-]*[:=#-]?[\s"'_-]*[0-9]{1,4}(?:[\s./-]+[0-9]{2,4})?(?:[^0-9]|$)/i;

// Three unchanged public benchmark text files contain numeric score/hash
// substrings that can satisfy the deliberately broad PAN OR rule.  A numeric
// exception is admissible only when the exact public file bytes, relative
// path, source hash, line bytes, run range and run digest all match this
// frozen baseline.  No path-only, label-only or generic decimal exemption is
// allowed.  The run digests avoid retaining the public numeric tokens here.
const PUBLIC_BENCHMARK_NUMERIC_BINDINGS = Object.freeze([
  {
    path: 'benchmarks/osworld-2.0/results.csv',
    sourceSha256: 'ceaec4c2c4a668f2a4f37286bf5d95d329382b1a12a744ce2b826e9ebc1d6c7e',
    lines: Object.freeze([
      Object.freeze({ line: 15, lineSha256: '4ab24b76abb2c16d6fcfb7d0c2bdb365de3b8cfee5876e50db029aa1d5d0a1ca', runs: Object.freeze([{ offset: 4, end: 22, digest: 'cb51bcf44519bad845d1d1fb332446bdcf543a02cd715aeb0225139f0fd0b8ee' }]) }),
      Object.freeze({ line: 39, lineSha256: '5e9d40b998c7a018a4543b17a3042ecbb0e60d983ee8ee3c6c43095ee0314aca', runs: Object.freeze([{ offset: 36, end: 48, digest: '958e11a3dd82d38b9fb5be519b7ad0bd4ead1521639d200ea0649dbe882d80a1' }]) }),
      Object.freeze({ line: 54, lineSha256: 'aca2cfe3271b3706d8a587037e7d2b371ab4123851370b74b8cc294083073490', runs: Object.freeze([{ offset: 0, end: 21, digest: '632bbb3a7a156513c2b3f7c999f66b9561d7741fb7e4be1fafb6c34c1bdcbc6e' }]) }),
      Object.freeze({ line: 81, lineSha256: '3af888494f2e36f5737227528ef5d37bf28228e717ded9394da707c85b96b009', runs: Object.freeze([{ offset: 0, end: 21, digest: '885a9c85f21523203908acff9008cf9aa9581f145d5d9501b76789b9ccd9b3c9' }]) }),
      Object.freeze({ line: 90, lineSha256: '853db816e97c6aad313f45e8618ccef7862249730b6a2f8932e460818ab12323', runs: Object.freeze([{ offset: 71, end: 94, digest: '2526d254300828c2216cab8b6399c87f9685882b4ec6970595f3c33b6eaddeff' }]) }),
      Object.freeze({ line: 105, lineSha256: '8742f2cb189a5339a90322b8377068aea73678412001ea7a45b132f9790d2832', runs: Object.freeze([{ offset: 0, end: 21, digest: '4756f9e4f077350996a3250b7cf7eb62967047241bf5272d428f1254cfb77be1' }]) }),
      Object.freeze({ line: 107, lineSha256: '599f22c5e8eb447bb6b6589c2dfed6c2d6186aaf26a38bf6089af3d9edaf19db', runs: Object.freeze([{ offset: 74, end: 97, digest: '156861f770ae4fc84c3470941a330d5057214d3782e68e0a272e9162aeb0268d' }]) }),
    ]),
  },
  {
    path: 'benchmarks/osworld-2.0/score-evidence.json',
    sourceSha256: '3a9ce372820b3382a8f37cc0f567b83f24f5a04adcce0b1c7bd9e0c2b5f5ace1',
    lines: Object.freeze([
      Object.freeze({ line: 112, lineSha256: '38220e161f326262d266cf09be48646e4e754568904df36201b9f50d4febeebb', runs: Object.freeze([{ offset: 29, end: 47, digest: 'cb51bcf44519bad845d1d1fb332446bdcf543a02cd715aeb0225139f0fd0b8ee' }]) }),
      Object.freeze({ line: 305, lineSha256: '66c3d431cfb761dfdaf24638a77f8663813462110031a2552111da762e7ac390', runs: Object.freeze([{ offset: 56, end: 68, digest: '958e11a3dd82d38b9fb5be519b7ad0bd4ead1521639d200ea0649dbe882d80a1' }]) }),
    ]),
  },
  {
    path: 'benchmarks/osworld-2.0/summary.json',
    sourceSha256: 'dcdda182d4ec704e368f748779a113d1d53daf2b34d0e1a8e74ddefe7d9d6e27',
    lines: Object.freeze([
      Object.freeze({ line: 15, lineSha256: 'b975da3c077ec71224bfa2f73a4322c6637dc84364e225997c4a4bba153ea0d9', runs: Object.freeze([{ offset: 70, end: 89, digest: 'a4d063a4c78d425aa7514e053b4a1ca835de9b3145d23bdb8fe3b0b5fb970d7e' }]) }),
    ]),
  },
]);

function approvedBenchmarkRun(text, run, { path: sourcePath, sourceHash } = {}) {
  const binding = PUBLIC_BENCHMARK_NUMERIC_BINDINGS.find(candidate => candidate.path === sourcePath && candidate.sourceSha256 === sourceHash);
  if (!binding) return false;
  const lineStart = text.lastIndexOf('\n', run.start - 1) + 1;
  const lineEnd = text.indexOf('\n', run.start);
  const line = text.slice(lineStart, lineEnd < 0 ? text.length : lineEnd);
  const lineNumber = text.slice(0, lineStart).split('\n').length;
  const lineBinding = binding.lines.find(candidate => candidate.line === lineNumber && candidate.lineSha256 === hash(Buffer.from(line)));
  if (!lineBinding) return false;
  const offset = run.start - lineStart;
  return lineBinding.runs.some(candidate => candidate.offset === offset && candidate.end === run.end - lineStart && candidate.digest === hash(run.digits));
}

function financialDigitRuns(text) {
  const runs = [];
  for (let index = 0; index < text.length;) {
    if (text[index] < '0' || text[index] > '9') { index++; continue; }
    const start = index;
    let digits = '';
    while (index < text.length) {
      if (text[index] >= '0' && text[index] <= '9') { digits += text[index++]; continue; }
      if (/[\s./-]/.test(text[index]) && index + 1 < text.length && text[index + 1] >= '0' && text[index + 1] <= '9') { index++; continue; }
      break;
    }
    if (digits.length >= 12) runs.push({ digits, start, end: index });
    if (index === start) index++;
  }
  return runs;
}

function financialFragmentRuns(text) {
  const runs = [];
  const separator = /[\s.,/'"`()[\]{}:+_=-]/;
  for (let index = 0; index < text.length;) {
    if (text[index] < '0' || text[index] > '9') { index++; continue; }
    const start = index;
    let digits = '';
    while (index < text.length && digits.length < 19) {
      if (text[index] >= '0' && text[index] <= '9') { digits += text[index++]; continue; }
      if (!separator.test(text[index])) break;
      let lookahead = index + 1;
      while (lookahead < text.length && separator.test(text[lookahead])) lookahead++;
      if (lookahead >= text.length || text[lookahead] < '0' || text[lookahead] > '9') break;
      index = lookahead;
    }
    if (digits.length >= 12) runs.push({ digits, start, end: index });
    if (index === start) index++;
  }
  return runs;
}
function scanPaymentTokenFields(text) {
  for (const match of text.matchAll(paymentTokenFieldPattern)) {
    const value = (match[1] || match[2] || '').trim();
    if (value && !explicitPlaceholderPattern.test(value)) reject('payment_token');
  }
}
function scanPopulatedTextFields(text) {
  for (const [rule, pattern] of populatedTextFieldPatterns) {
    for (const match of text.matchAll(pattern)) {
      const value = (match[1] ?? match[2] ?? match[3] ?? '').trim();
      if (value && !explicitPlaceholderPattern.test(value)) reject(rule);
    }
  }
}
export function scanFinancialText(text, options = {}) {
  const normalized = normalizeDecimalDigits(decodeNumericEntities(text));
  scanPaymentTokenFields(normalized);
  scanPopulatedTextFields(normalized);
  for (const [rule, pattern] of financialFieldPatterns) {
    if (!pattern.test(normalized) && !(rule === 'payment_expiry' && paymentExpiryFieldPattern.test(normalized))) continue;
    reject(rule);
  }
  for (const pattern of trackDataPatterns) if (pattern.test(normalized)) reject('track_data');
  if (labelledTrackPattern.test(normalized) || maskedCardNumberPattern.test(normalized)) reject(labelledTrackPattern.test(normalized) ? 'track_data' : 'masked_card');
  for (const match of normalized.matchAll(contextualCardPattern)) {
    const window = normalized.slice(match.index + match[0].length, match.index + match[0].length + 96);
    for (const run of financialFragmentRuns(window)) reject('payment_card_pan');
  }
  for (const run of financialFragmentRuns(normalized)) {
    if (approvedBenchmarkRun(normalized, run, options)) continue;
    if (luhnValid(run.digits)) reject('payment_card_pan');
  }
  const runs = financialDigitRuns(normalized);
  if (runs.length > 512) reject('financial_candidate_limit');
  for (const run of runs) {
    if (approvedBenchmarkRun(normalized, run, options) || !luhnValid(run.digits)) continue;
    // Valid-Luhn runs are rejected even without an issuer prefix. Labelled
    // contextual fields above reject invalid check digits as well. Narrow
    // score-decimal controls preserve harmless benchmark metrics only.
    reject('payment_card_pan');
  }
}

const patterns = [
  ['email', /[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/i],
  ['phone', /(?:^|[^\w])(?:\+?1[ .()-]*)?[2-9]\d{2}[ .()-]*\d{3}[ .-]*\d{4}(?:$|[^\w])/],
  ['phone', /(?:^|[^\w])\+[1-9]\d{0,2}[ .()-]+\d[\d .()-]{6,17}\d(?:$|[^\w])/],
  ['home_path', /(?:\/Us[e]rs\/|\/ho[m]e\/|[A-Z]:[\\/]Us[e]rs[\\/])[^\s/\\"'<>]+/i],
  ['home_path', /(?:^|[^\w])(?:\/ro[o]t(?:\/|$)|\/m[n]t\/[a-z]\/us[e]rs\/[^\s/]+)/i],
  ['private_key', /BEGIN (?:RSA |EC |DSA |OPENSSH |PGP )?PRIV[A]TE KEY/],
  ['provider_token', /(?:s[k]-[A-Za-z0-9_-]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|github_p[a]t_[A-Za-z0-9_]{20,}|xo[x][abprs]-[A-Za-z0-9-]{10,}|A(?:KIA|SIA)[A-Z0-9]{16}|h[f]_[A-Za-z0-9]{20,}|AIz[a][A-Za-z0-9_-]{30,}|s[k]_(?:live|test)_[A-Za-z0-9]{16,}|np[m]_[A-Za-z0-9]{20,}|S[K][a-fA-F0-9]{32}|S[G]\.[A-Za-z0-9_-]{16,}\.[A-Za-z0-9_-]{16,})/],
  ['credential_assignment', /(?:pass[w]ord|pass[p]hrase|api[_-]?k[e]y|access[_-]?tok[e]n|refresh[_-]?tok[e]n|client[_-]?secr[e]t|session[_-]?(?:tok[e]n|cookie)|webhook[_-]?secr[e]t|signing[_-]?k[e]y)["']?\s*[:=]\s*["']?[A-Za-z0-9+/_=.@:-]{8,}/i],
  ['authorization', /authoriz[a]tion\s*:\s*(?:bearer|basic)\s+[A-Za-z0-9+/_=.-]{8,}/i],
  ['credential_url', /[a-z][a-z0-9+.-]*:\/\/[^\s/@:]+:[^\s/@]+@[^\s/]+/i],
  ['jwt', /eyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}/],
  ['private_resource_url', /(?:docs\.google\.com\/(?:document|spreadsheets|presentation)\/d\/|drive\.google\.com\/(?:file\/d\/|drive\/folders\/)|[?&](?:access_tok[e]n|refresh_tok[e]n|id_tok[e]n|client_secr[e]t|auth_code|X-Amz-Signature)=)[^\s"'<>]+/i],
  ['oauth_callback', /https?:\/\/[^\s"'<>]+[?&]code=[^\s&#"'<>]+/i],
  ['hidden_unicode', new RegExp('[' + [173,1564,8203,8204,8205,8206,8207,8234,8235,8236,8237,8238,8288,8294,8295,8296,8297,65279].map(n => String.fromCodePoint(n)).join('') + ']', 'u')],
];
function decodedViews(text) {
  const found = [];
  if (/%[\da-f]{2}|\\x[\da-f]{2}|\\u[\da-f]{4}/i.test(text)) {
    const v = text.replace(/%([\da-f]{2})|\\x([\da-f]{2})|\\u([\da-f]{4})/gi, (_, a, b, c) => String.fromCharCode(parseInt(a || b || c, 16)));
    if (v !== text) found.push(v);
  }
  for (const m of text.matchAll(/(?:[A-Za-z0-9+/_-]{16,}={0,2})/g)) {
    const candidate = m[0];
    // Strict digest fields are integrity values, not encoded text.
    if (/^[\da-f]{64}$/i.test(candidate)) continue;
    if (candidate.length % 4 === 1) continue;
    const b = Buffer.from(candidate, 'base64url');
    if (!b.length) continue;
    let value; try { value = new TextDecoder('utf-8', { fatal: true }).decode(b); } catch { continue; }
    if (!/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(value) && value !== candidate) found.push(value);
    if (found.length > LIMITS.views) reject('decode_limit');
  }
  return found;
}
export function scanText(text, { checksum = false, ...financialOptions } = {}) {
  if (/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(text)) reject('control_bytes');
  scanFinancialText(text, financialOptions);
  const queue = []; const seen = new Set(); let count = 0; let bytes = 0;
  for (let line of text.split('\n')) {
    if (Buffer.byteLength(line) > LIMITS.line) reject('line_limit');
    if (checksum && line) {
      const m = /^([a-f\d]{64})  (.+)$/.exec(line);
      if (!m || !safeRelative(m[2])) reject('checksum_grammar');
      line = m[2];
    }
    queue.push({ value: line, depth: 0 });
  }
  while (queue.length) {
    const { value, depth } = queue.shift();
    if (seen.has(value)) continue; seen.add(value);
    if (depth > 0 && (++count > LIMITS.views || (bytes += Buffer.byteLength(value)) > LIMITS.decoded)) reject('decode_limit');
    if (depth > 0) scanFinancialText(value, financialOptions);
    for (const [rule, re] of patterns) if (re.test(value)) reject(rule);
    const decoded = decodedViews(value);
    if (decoded.length && depth >= LIMITS.depth) reject('decode_depth');
    for (const v of decoded) queue.push({ value: v, depth: depth + 1 });
  }
}
export function crc32(bytes) {
  let c = 0xffffffff;
  for (const b of bytes) { c ^= b; for (let i = 0; i < 8; i++) c = (c >>> 1) ^ (0xedb88320 & -(c & 1)); }
  return (c ^ 0xffffffff) >>> 0;
}
function scanPng(bytes, relative, reviews) {
  const review = reviews.find(x => x.path === relative && x.sha256 === hash(bytes) && x.kind === 'png' && x.reviewed === true && typeof x.reviewer === 'string' && x.reviewer.trim());
  if (!review) reject('media_review_required');
  if (!bytes.subarray(0, 8).equals(Buffer.from([137,80,78,71,13,10,26,10]))) reject('media_format');
  let cursor = 8; let header = false; let data = false; let end = false; let width = 0; let height = 0; let channels = 0; const compressed = [];
  while (cursor < bytes.length) {
    if (cursor + 12 > bytes.length) reject('media_format');
    const len = bytes.readUInt32BE(cursor); const type = bytes.toString('ascii', cursor + 4, cursor + 8);
    if (cursor + 12 + len > bytes.length || !['IHDR', 'IDAT', 'IEND'].includes(type)) reject('media_metadata');
    if (crc32(bytes.subarray(cursor + 4, cursor + 8 + len)) !== bytes.readUInt32BE(cursor + 8 + len)) reject('media_crc');
    if (!header && (type !== 'IHDR' || len !== 13)) reject('media_format');
    if (type === 'IHDR') { if (header) reject('media_format'); header = true; if (!bytes.readUInt32BE(cursor+8) || !bytes.readUInt32BE(cursor+12) || bytes.readUInt32BE(cursor+8) * bytes.readUInt32BE(cursor+12) > 20000000) reject('media_limit'); }
    if (type === 'IHDR') { width = bytes.readUInt32BE(cursor+8); height = bytes.readUInt32BE(cursor+12); const depth=bytes[cursor+16], color=bytes[cursor+17]; if (depth!==8 || ![2,6].includes(color) || bytes[cursor+18]!==0 || bytes[cursor+19]!==0 || bytes[cursor+20]!==0) reject('media_format'); channels=color===2?3:4; }
    if (type === 'IDAT') { data = true; compressed.push(bytes.subarray(cursor+8,cursor+8+len)); }
    if (type === 'IEND') { if (len !== 0 || !data) reject('media_format'); end = true; }
    cursor += 12 + len;
    if (end && cursor !== bytes.length) reject('media_format');
  }
  if (!end) reject('media_format');
  const expected=height*(1+width*channels); let raster;
  try { raster=inflateSync(Buffer.concat(compressed), {maxOutputLength:expected}); } catch { reject('media_raster'); }
  if (raster.length!==expected) reject('media_raster');
  for (let y=0;y<height;y++) if (raster[y*(1+width*channels)]>4) reject('media_raster');
}
/** A bounded baseline-JPEG container inspector, not a pixel decoder. APP data
 * is admitted only by exact segment hashes from a separate private review. */
export function inspectJpeg(bytes) {
  if (!Buffer.isBuffer(bytes) || bytes.length < 4 || bytes.length > LIMITS.file || bytes.readUInt16BE(0) !== 0xffd8) reject('media_format');
  let cursor=2, frame=false, scan=false, ended=false, width=0, height=0, segments=0; const metadataSegments=[];
  while (cursor < bytes.length) {
    if (++segments>256) reject('media_limit');
    if (bytes[cursor++]!==255 || cursor>=bytes.length) reject('media_format');
    const marker=bytes[cursor++];
    if (marker===0xd9) { ended=true; if (!frame || !scan || cursor!==bytes.length) reject('media_format'); break; }
    if (scan || ![0xe0,0xe1,0xed,0xc0,0xc4,0xdb,0xdd,0xda].includes(marker) || cursor+2>bytes.length) reject('media_metadata');
    const length=bytes.readUInt16BE(cursor); if (length<2 || cursor+length>bytes.length) reject('media_format');
    const body=bytes.subarray(cursor+2,cursor+length); cursor+=length;
    if (marker>=0xe0) {
      if (marker===0xe0 && (body.length!==14 || body.toString('latin1',0,5)!=='JFIF'+String.fromCharCode(0) || body[12] || body[13])) reject('media_metadata');
      if (marker===0xe1 && (body.length<14 || body.length>4096 || body.toString('latin1',0,6)!=='Exif'+String.fromCharCode(0,0))) reject('media_metadata');
      if (marker===0xed && (body.length>1024 || body.toString('latin1',0,14)!=='Photoshop 3.0'+String.fromCharCode(0))) reject('media_metadata');
      metadataSegments.push({marker:'APP'+(marker-0xe0),length:body.length,sha256:hash(body)});
    } else if (marker===0xc0) {
      if(frame || body.length<9 || body[0]!==8 || ![1,3].includes(body[5]) || body.length!==6+3*body[5])reject('media_format');
      frame=true;height=body.readUInt16BE(1);width=body.readUInt16BE(3);if(!width || !height || width*height>20000000)reject('media_limit');
    } else if (marker===0xda) {
      if(!frame || body.length<6 || body.length!==4+2*body[0])reject('media_format');scan=true;
      // Entropy-coded bytes may contain stuffed FF00 and restart markers.
      // Any other marker must be the final EOI, with no hidden trailing payload.
      while(cursor<bytes.length) {
        if(bytes[cursor]!==255){cursor++;continue;}
        if(cursor+1>=bytes.length)reject('media_format');const next=bytes[cursor+1];
        if(next===0 || (next>=0xd0 && next<=0xd7)){cursor+=2;continue;}
        if(next===0xd9)break;reject('media_metadata');
      }
    }
  }
  if(!ended)reject('media_format');return {width,height,metadataSegments};
}
function scanJpeg(bytes, relative, reviews) {
  const review=reviews.find(x=>x.path===relative && x.sha256===hash(bytes) && x.kind==='jpeg' && x.reviewed===true && typeof x.reviewer==='string' && x.reviewer.trim());
  if(!review)reject('media_review_required');
  const inspected=inspectJpeg(bytes);
  if(review.metadataReviewed!==true || typeof review.metadataReviewer!=='string' || !review.metadataReviewer.trim() || !Array.isArray(review.metadataSegments) || JSON.stringify(review.metadataSegments)!==JSON.stringify(inspected.metadataSegments))reject('media_metadata_review_required');
}
// One frozen public baseline retains a stale README row in its published
// SHA256SUMS file. This is deliberately byte- and path-bound: the exception
// cannot be copied to another checksum file, target, digest, or README.
const LEGACY_OSWORLD_CHECKSUM_PATH = 'benchmarks/osworld-2.0/SHA256SUMS';
const LEGACY_OSWORLD_CHECKSUM_SHA256 = '5092cb9d6f0a38be0f2ea348d2b259d1ffb794cdb8db8071bd281bc811072078';
const LEGACY_OSWORLD_README_PATH = 'benchmarks/osworld-2.0/README.md';
const LEGACY_OSWORLD_README_SHA256 = '94752857af9b9e9f0e36c5f2186024976a9800c446ab331d377177db575c59be';
const LEGACY_OSWORLD_STALE_README_SHA256 = '2db789f4f2b4822d0a0d1d0ee3355f0c210b3f509ae76f945f437d2e218deb02';

function verifyChecksumEntry(entry, entriesByPath) {
  const text = new TextDecoder('utf-8', { fatal: true }).decode(entry.bytes);
  const directory = path.posix.dirname(entry.path);
  const frozenLegacyFile = entry.path === LEGACY_OSWORLD_CHECKSUM_PATH && hash(entry.bytes) === LEGACY_OSWORLD_CHECKSUM_SHA256;
  for (const line of text.split('\n')) {
    if (!line) continue;
    const match = /^([a-f\d]{64})  (.+)$/.exec(line);
    if (!match) continue;
    const referenced = path.posix.normalize(path.posix.join(directory, match[2]));
    if (!safeRelative(referenced)) reject('checksum_reference_invalid');
    const target = entriesByPath.get(referenced);
    if (!target) reject('checksum_reference_missing');
    const targetSha256 = hash(target.bytes);
    const frozenLegacyStaleRow = frozenLegacyFile && referenced === LEGACY_OSWORLD_README_PATH && match[1] === LEGACY_OSWORLD_STALE_README_SHA256 && targetSha256 === LEGACY_OSWORLD_README_SHA256;
    if (targetSha256 !== match[1] && !frozenLegacyStaleRow) reject('checksum_mismatch');
  }
}
export function scanEntries(entries, allowlist, { mediaReviews = [] } = {}) {
  if (!Array.isArray(entries) || entries.length > LIMITS.files) reject('entry_limit');
  if (entries.map(x => x.path).sort().join('\n') !== allowlist.join('\n')) reject('inventory_mismatch');
  const findings = []; let total = 0;
  const entriesByPath = new Map(entries.map(entry => [entry.path, entry]));
  for (let i = 0; i < entries.length; i++) {
    const e = entries[i];
    try {
      if (!safeRelative(e.path)) reject('unsafe_path'); filenameRules(e.path);
      if (!Buffer.isBuffer(e.bytes) || e.bytes.length > LIMITS.file || (total += e.bytes.length) > LIMITS.bytes) reject('input_limit');
      if (![0o600, 0o644, 0o700, 0o755].includes(e.mode)) reject('unsafe_mode');
      scanText(e.path);
      if (e.path.toLowerCase().endsWith('.png')) scanPng(e.bytes, e.path, mediaReviews);
      else if (/\.jpe?g$/i.test(e.path)) scanJpeg(e.bytes, e.path, mediaReviews);
      else {
        const extension = path.extname(e.path).toLowerCase();
        if (/\.(zip|tar|tgz|gz|bz2|xz|7z|rar|dmg|pkg|iso|jar|war)$/.test(extension)) reject('unsupported_opaque_archive');
        if (/\.(gif|webp|heic|avif|bmp|tif|tiff|ico|mp4|mov|mkv|wav|mp3|pdf)$/.test(extension)) reject('unsupported_opaque_media');
        if (!['', '.md', '.mjs', '.js', '.cjs', '.sh', '.json', '.txt', '.conf', '.yaml', '.yml', '.template', '.command', '.map', '.sha256', '.csv', '.py'].includes(extension)) reject('unsupported_format');
        let text; try { text = new TextDecoder('utf-8', { fatal: true }).decode(e.bytes); } catch { reject('unsupported_binary'); }
        if (/^(?:PK\x03\x04|%PDF-|SQLite format 3)/.test(text)) reject('opaque_container');
        const checksum = e.path.endsWith('.sha256') || path.basename(e.path) === 'SHA256SUMS';
        scanText(text, { checksum, path: e.path, sourceHash: hash(e.bytes) });
        if (checksum) verifyChecksumEntry(e, entriesByPath);
      }
    } catch (err) { if (!(err instanceof ScanError)) throw err; findings.push({ file: i + 1, rule: err.rule }); }
  }
  return { ok: findings.length === 0, files: entries.length, bytes: total, findings, limitation: 'Generic detection and exact supplied media-review binding; separate semantic privacy and reviewer-provenance validation required.' };
}
export function scanTree(root, { mediaReviews = [] } = {}) {
  root = safeAbsolute(root, { directory: true });
  // The complete candidate must equal the list. Even normally ignored directories are examined as names and rejected.
  const allowlist = parseAllowlist(readBounded(path.join(root, 'config/release-allowlist.txt')));
  const observed = []; const pending = []; const directories = new Set(); let statBytes = 0;
  for (const rel of allowlist) { let p = path.posix.dirname(rel); while (p !== '.') { directories.add(p); p = path.posix.dirname(p); } }
  function visit(dir, prefix = '') {
    for (const name of fs.readdirSync(dir).sort()) {
      const rel = prefix ? `${prefix}/${name}` : name;
      if (!safeRelative(rel)) reject('unsafe_path'); filenameRules(rel);
      const p = path.join(dir, name); const s = fs.lstatSync(p);
      if (s.isSymbolicLink()) reject('symlink');
      if (s.isDirectory()) { if (!directories.has(rel)) reject('unlisted_directory'); visit(p, rel); }
      else {
        if (!s.isFile() || s.nlink !== 1) reject('nonregular');
        if (!allowlist.includes(rel)) reject('unlisted_file');
        if (pending.length >= LIMITS.files) reject('entry_limit');
        if (s.size > LIMITS.file || (statBytes += s.size) > LIMITS.bytes) reject('input_limit');
        pending.push({ path: rel, absolute: p, mode: s.mode & 0o7777, size: s.size });
      }
    }
  }
  visit(root);
  let actualBytes = 0;
  for (const entry of pending) {
    const bytes = readBounded(entry.absolute, Math.min(LIMITS.file, LIMITS.bytes - actualBytes));
    if (bytes.length !== entry.size) reject('input_changed');
    actualBytes += bytes.length;
    if (actualBytes > LIMITS.bytes) reject('input_limit');
    observed.push({ path: entry.path, mode: entry.mode, bytes });
  }
  observed.sort((a,b) => a.path < b.path ? -1 : a.path > b.path ? 1 : 0);
  const report = scanEntries(observed, allowlist, { mediaReviews });
  return { ...report, entries: observed, allowlist };
}
export function readMediaReviews(file) {
  if (!file) return [];
  let value; try { value = JSON.parse(readBounded(file).toString('utf8')); } catch { reject('media_review_invalid'); }
  if (!Array.isArray(value) || value.length > 128 || value.some(x => !x || !safeRelative(x.path) || !/^[a-f\d]{64}$/.test(x.sha256 || ''))) reject('media_review_invalid');
  return value;
}
export function main(args) {
  if (Number(process.versions.node.split('.')[0]) < 22) reject('node_version');
  if (args.length === 1 && ['--help', '-h'].includes(args[0])) { console.log('Usage: node publication-scan.mjs --root ABSOLUTE_CANDIDATE [--media-review ABSOLUTE_PRIVATE_JSON]'); return; }
  const opts = {};
  for (let i=0;i<args.length;i+=2) { if (!['--root','--media-review'].includes(args[i]) || !args[i+1] || opts[args[i]]) reject('arguments'); opts[args[i]]=args[i+1]; }
  if (!opts['--root']) reject('arguments');
  const { entries, allowlist, ...report } = scanTree(opts['--root'], { mediaReviews: readMediaReviews(opts['--media-review']) });
  console.log(JSON.stringify(report)); if (!report.ok) process.exitCode = 1;
}
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { main(process.argv.slice(2)); } catch (err) { console.error(JSON.stringify({ ok: false, rule: err instanceof ScanError ? err.rule : 'inspection_failed' })); process.exitCode = 1; }
}
