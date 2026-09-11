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
  if (/^(credentials?|secrets?)(\.|$)|^id_(rsa|dsa|ecdsa|ed25519)$|^authorized_keys$|^known_hosts$/.test(name) || /\.(env|pem|key|p12|pfx|jks|keystore|log|bak|backup|orig|rej|swp|swo|zip|tar|tgz|gz|bz2|xz|7z|rar|dmg|pkg|iso|db|sqlite|sqlite3)$/.test(name) || name.endsWith('~')) reject('forbidden_file');
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
  for (const m of text.matchAll(/(?:[A-Za-z0-9+/_-]{24,}={0,2})/g)) {
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
export function scanText(text, { checksum = false } = {}) {
  if (/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(text)) reject('control_bytes');
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
export function scanEntries(entries, allowlist, { mediaReviews = [] } = {}) {
  if (!Array.isArray(entries) || entries.length > LIMITS.files) reject('entry_limit');
  if (entries.map(x => x.path).sort().join('\n') !== allowlist.join('\n')) reject('inventory_mismatch');
  const findings = []; let total = 0;
  for (let i = 0; i < entries.length; i++) {
    const e = entries[i];
    try {
      if (!safeRelative(e.path)) reject('unsafe_path'); filenameRules(e.path);
      if (!Buffer.isBuffer(e.bytes) || e.bytes.length > LIMITS.file || (total += e.bytes.length) > LIMITS.bytes) reject('input_limit');
      if (![0o644, 0o755].includes(e.mode)) reject('unsafe_mode');
      scanText(e.path);
      if (e.path.toLowerCase().endsWith('.png')) scanPng(e.bytes, e.path, mediaReviews);
      else if (/\.jpe?g$/i.test(e.path)) scanJpeg(e.bytes, e.path, mediaReviews);
      else {
        if (!['', '.md', '.mjs', '.js', '.sh', '.json', '.txt', '.conf', '.yaml', '.yml', '.template', '.command', '.map', '.sha256', '.csv', '.py'].includes(path.extname(e.path).toLowerCase())) reject('unsupported_format');
        let text; try { text = new TextDecoder('utf-8', { fatal: true }).decode(e.bytes); } catch { reject('unsupported_binary'); }
        if (/^(?:PK\x03\x04|%PDF-|SQLite format 3)/.test(text)) reject('opaque_container');
        scanText(text, { checksum: e.path.endsWith('.sha256') || path.basename(e.path) === 'SHA256SUMS' });
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
