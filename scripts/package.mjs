#!/usr/bin/env node
/** Reproducible, uncompressed ZIP packaging with strict, bounded verification. */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { ScanError, reject, LIMITS, hash, crc32, safeRelative, safeAbsolute, readBounded, parseAllowlist, scanEntries, scanTree, readMediaReviews } from './publication-scan.mjs';
const ZIP_LIMIT = 72 * 1024 * 1024;
const SOURCE_MODES = new Set([0o600, 0o644, 0o700, 0o755]);
const comparePath = (a,b) => a.path < b.path ? -1 : a.path > b.path ? 1 : 0;
const ROOT = 'AutoAssist/';
// Private release staging is owner-only; GitHub web commits may record source
// files as nonexecutable. The ZIP has its own deterministic, name-based mode
// policy; passive benchmark files stay 644 in the distributable archive.
export function canonicalArchiveMode(relative) {
  if (!safeRelative(relative)) reject('zip_path');
  if (relative.startsWith('benchmarks/')) return 0o644;
  return /\.(?:sh|command)$/i.test(relative) || relative === 'runtime/bin/autoassist' ? 0o755 : 0o644;
}
export function makeZip(input) {
  if (!Array.isArray(input) || input.some(e => !SOURCE_MODES.has(e.mode) || (e.path.startsWith('benchmarks/') && ![0o600,0o644].includes(e.mode)))) reject('source_mode');
  const entries = input.map(e => ({ ...e, mode: canonicalArchiveMode(e.path) })).sort(comparePath); const locals = []; const central = []; let offset = 0;
  if (!entries.length || entries.length > LIMITS.files || new Set(entries.map(x=>x.path)).size !== entries.length) reject('zip_entries');
  for (const e of entries) {
    if (!safeRelative(e.path) || !Buffer.isBuffer(e.bytes) || !SOURCE_MODES.has(e.mode) || e.bytes.length > LIMITS.file) reject('zip_entry');
    const name = Buffer.from(ROOT + e.path); const crc = crc32(e.bytes); const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50,0); local.writeUInt16LE(20,4); local.writeUInt16LE(0x0800,6); local.writeUInt16LE(0,8); local.writeUInt16LE(0,10); local.writeUInt16LE(33,12);
    local.writeUInt32LE(crc,14); local.writeUInt32LE(e.bytes.length,18); local.writeUInt32LE(e.bytes.length,22); local.writeUInt16LE(name.length,26);
    const c = Buffer.alloc(46); c.writeUInt32LE(0x02014b50,0); c.writeUInt16LE(0x0314,4); c.writeUInt16LE(20,6); c.writeUInt16LE(0x0800,8); c.writeUInt16LE(0,10); c.writeUInt16LE(0,12); c.writeUInt16LE(33,14);
    c.writeUInt32LE(crc,16); c.writeUInt32LE(e.bytes.length,20); c.writeUInt32LE(e.bytes.length,24); c.writeUInt16LE(name.length,28); c.writeUInt32LE(((0o100000 | e.mode) * 65536) >>> 0,38); c.writeUInt32LE(offset,42);
    locals.push(local,name,e.bytes); central.push(c,name); offset += local.length + name.length + e.bytes.length;
    if (offset > ZIP_LIMIT) reject('zip_limit');
  }
  const directory = Buffer.concat(central); const end = Buffer.alloc(22); end.writeUInt32LE(0x06054b50,0); end.writeUInt16LE(entries.length,8); end.writeUInt16LE(entries.length,10); end.writeUInt32LE(directory.length,12); end.writeUInt32LE(offset,16);
  return Buffer.concat([...locals,directory,end]);
}
function requireRange(bytes, offset, size) { if (!Number.isSafeInteger(offset) || offset<0 || offset+size>bytes.length) reject('zip_truncated'); }
export function readZip(bytes) {
  if (!Buffer.isBuffer(bytes) || bytes.length < 22 || bytes.length > ZIP_LIMIT) reject('zip_limit');
  const end = bytes.length-22;
  if (bytes.readUInt32LE(end)!==0x06054b50 || bytes.readUInt16LE(end+4)!==0 || bytes.readUInt16LE(end+6)!==0 || bytes.readUInt16LE(end+20)!==0) reject('zip_footer');
  const count=bytes.readUInt16LE(end+10); const size=bytes.readUInt32LE(end+12); const start=bytes.readUInt32LE(end+16);
  if (!count || count>LIMITS.files || bytes.readUInt16LE(end+8)!==count || start+size!==end) reject('zip_directory');
  const result=[]; const names=new Set(); let cursor=start; let nextLocal=0; let total=0;
  for (let n=0;n<count;n++) {
    requireRange(bytes,cursor,46);
    if(bytes.readUInt32LE(cursor)!==0x02014b50)reject('zip_directory');
    const made=bytes.readUInt16LE(cursor+4), version=bytes.readUInt16LE(cursor+6), flags=bytes.readUInt16LE(cursor+8), method=bytes.readUInt16LE(cursor+10), time=bytes.readUInt16LE(cursor+12), date=bytes.readUInt16LE(cursor+14);
    const crc=bytes.readUInt32LE(cursor+16), packed=bytes.readUInt32LE(cursor+20), expanded=bytes.readUInt32LE(cursor+24), len=bytes.readUInt16LE(cursor+28), extra=bytes.readUInt16LE(cursor+30), comment=bytes.readUInt16LE(cursor+32), disk=bytes.readUInt16LE(cursor+34), internal=bytes.readUInt16LE(cursor+36), attrs=bytes.readUInt32LE(cursor+38), localOffset=bytes.readUInt32LE(cursor+42);
    if(made!==0x0314 || version!==20 || flags!==0x0800 || method!==0 || time!==0 || date!==33 || extra || comment || disk || internal || packed!==expanded || expanded>LIMITS.file || (total+=expanded)>LIMITS.bytes || localOffset!==nextLocal || (attrs & 0xffff)!==0)reject('zip_metadata');
    const unix=attrs>>>16; const mode=unix&0o7777;
    if((unix&0o170000)!==0o100000 || ![0o644,0o755].includes(mode))reject('zip_mode');
    requireRange(bytes,cursor+46,len);
    const nameBytes=bytes.subarray(cursor+46,cursor+46+len); let name;try{name=new TextDecoder('utf-8',{fatal:true}).decode(nameBytes);}catch{reject('zip_name');}
    if(!name.startsWith(ROOT) || !safeRelative(name.slice(ROOT.length)) || names.has(name))reject('zip_path'); names.add(name);
    requireRange(bytes,localOffset,30+len+expanded);
    if(bytes.readUInt32LE(localOffset)!==0x04034b50 || bytes.readUInt16LE(localOffset+4)!==version || bytes.readUInt16LE(localOffset+6)!==flags || bytes.readUInt16LE(localOffset+8)!==method || bytes.readUInt16LE(localOffset+10)!==time || bytes.readUInt16LE(localOffset+12)!==date || bytes.readUInt32LE(localOffset+14)!==crc || bytes.readUInt32LE(localOffset+18)!==packed || bytes.readUInt32LE(localOffset+22)!==expanded || bytes.readUInt16LE(localOffset+26)!==len || bytes.readUInt16LE(localOffset+28)!==0 || !bytes.subarray(localOffset+30,localOffset+30+len).equals(nameBytes))reject('zip_header_mismatch');
    const payload=bytes.subarray(localOffset+30+len,localOffset+30+len+expanded);
    if(crc32(payload)!==crc)reject('zip_crc');
    nextLocal=localOffset+30+len+expanded;
    if(mode!==canonicalArchiveMode(name.slice(ROOT.length)))reject('zip_mode_policy');
    result.push({path:name.slice(ROOT.length),mode,bytes:Buffer.from(payload)});cursor+=46+len;
  }
  if(cursor!==end || nextLocal!==start || result.map(e=>e.path).join('\n')!==[...result].sort(comparePath).map(e=>e.path).join('\n'))reject('zip_layout');
  return result;
}
export const manifestFor = entries => [...entries].sort(comparePath).map(e=>`${hash(e.bytes)}  ${e.path}\n`).join('');
export function verifyEntries(entries,{mediaReviews=[]}={}) {
  const list=entries.find(e=>e.path==='config/release-allowlist.txt'); if(!list)reject('allowlist_missing');
  const allowlist=parseAllowlist(list.bytes); const result=scanEntries(entries,allowlist,{mediaReviews});
  if(!result.ok)reject('payload_scan_failed');
  const version=entries.find(e=>e.path==='VERSION')?.bytes.toString('utf8');
  if(!version || !/^(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\n$/.test(version))reject('version_invalid');
  if(!entries.some(e=>e.path==='LICENSE' && hash(e.bytes)==='a8323253d2ae9e1eb82372f057ecb64f7f9892bcb2e53db758e7097e2da1270b'))reject('license_mismatch');
  return {version:version.trim(),files:entries.length};
}
function newOutputDirectory(value) {
  if(typeof value!=='string' || !path.isAbsolute(value))reject('output_path');
  const parent=safeAbsolute(path.dirname(value),{directory:true}); const base=path.basename(value);
  if(!safeRelative(base))reject('output_path');const resolved=path.join(parent,base);
  if(fs.existsSync(resolved))reject('output_exists');fs.mkdirSync(resolved,{mode:0o700});return resolved;
}
function exclusiveFile(file,bytes,mode=0o600) { const fd=fs.openSync(file,'wx',mode);try{fs.writeFileSync(fd,bytes);fs.fsyncSync(fd);}finally{fs.closeSync(fd);} }
export function buildRelease(root,out,{mediaReviews=[]}={}) {
  root=safeAbsolute(root,{directory:true});out=path.resolve(out);
  if(out===root || out.startsWith(root+path.sep) || root.startsWith(out+path.sep))reject('output_overlap');
  const source=scanTree(root,{mediaReviews}); if(!source.ok)reject('source_scan_failed');
  const meta=verifyEntries(source.entries,{mediaReviews});const zip=makeZip(source.entries);const reopened=readZip(zip);
  verifyEntries(reopened,{mediaReviews});
  if(manifestFor(reopened)!==manifestFor(source.entries) || reopened.some(e=>e.mode!==canonicalArchiveMode(e.path)))reject('roundtrip_mismatch');
  // Recheck before materializing output; package immutable in-memory bytes from this exact read.
  const current=scanTree(root,{mediaReviews});if(!current.ok || manifestFor(current.entries)!==manifestFor(source.entries) || current.entries.some((e,i)=>e.mode!==source.entries[i].mode))reject('source_changed');
  const dest=newOutputDirectory(out);const name=`AutoAssist-v${meta.version}.zip`;const manifestName=`AutoAssist-v${meta.version}.manifest.sha256`;const checksum=`${hash(zip)}  ${name}\n`;const manifest=manifestFor(reopened);
  exclusiveFile(path.join(dest,name),zip);exclusiveFile(path.join(dest,manifestName),manifest);exclusiveFile(path.join(dest,`${name}.sha256`),checksum);
  return {ok:true,version:meta.version,files:meta.files,archive:name,sha256:hash(zip),manifest_sha256:hash(Buffer.from(manifest)),limitation:'Packaging and deterministic checks only; independent review and installed tests are separate.'};
}
export function verifyRelease(archive,manifest,checksum,{mediaReviews=[]}={}) {
  const bytes=readBounded(archive,ZIP_LIMIT);const entries=readZip(bytes);const meta=verifyEntries(entries,{mediaReviews});const name=`AutoAssist-v${meta.version}.zip`;
  if(path.basename(archive)!==name || readBounded(checksum).toString('utf8')!==`${hash(bytes)}  ${name}\n` || readBounded(manifest).toString('utf8')!==manifestFor(entries))reject('release_integrity');
  return {ok:true,...meta,sha256:hash(bytes),entries};
}
export function extractRelease(entries,destination) {
  // Destination is created exclusively. Never merge into or overwrite any existing installation.
  if (!Array.isArray(entries) || !entries.length || entries.length > LIMITS.files) reject('extract_entry');
  parseAllowlist(Buffer.from([...entries].sort(comparePath).map(e => e.path).join('\n') + '\n'));
  if (entries.some(e => !Buffer.isBuffer(e.bytes) || e.bytes.length > LIMITS.file || ![0o644,0o755].includes(e.mode)) || entries.reduce((sum,e) => sum+e.bytes.length,0) > LIMITS.bytes) reject('extract_entry');
  const root=newOutputDirectory(destination);const payload=path.join(root,'AutoAssist');fs.mkdirSync(payload,{mode:0o700});
  for(const e of entries) {
    if(!safeRelative(e.path) || ![0o644,0o755].includes(e.mode))reject('extract_entry');
    // These descendants belong to the exclusive output root. The scanner's
    // broad-input-root exclusions do not apply to ordinary nested containers.
    let directory=payload;
    for (const segment of e.path.split('/').slice(0,-1)) {
      directory=path.join(directory,segment);
      try { fs.mkdirSync(directory,{mode:0o755}); }
      catch (error) { if (error.code!=='EEXIST') throw error; }
      const entry=fs.lstatSync(directory);
      if (!entry.isDirectory() || entry.isSymbolicLink()) reject('extract_directory');
    }
    const p=path.join(payload,e.path);exclusiveFile(p,e.bytes,e.mode);fs.chmodSync(p,e.mode);
  }
  return {extracted:true,files:entries.length};
}
export function main(args) {
  if (Number(process.versions.node.split('.')[0]) < 22) reject('node_version');
  if(args.length===1 && ['--help','-h'].includes(args[0])){console.log('Usage: package.mjs build --root ABS --out NEW_ABS [--media-review ABS]\n       package.mjs verify --archive ABS --manifest ABS --checksum ABS [--media-review ABS] [--extract NEW_ABS]\n       package.mjs check --root ABS [--media-review ABS]');return;}
  const command=args.shift();const permitted=command==='build'?['--root','--out','--media-review']:command==='verify'?['--archive','--manifest','--checksum','--media-review','--extract']:command==='check'?['--root','--media-review']:[];const opts={};
  for(let i=0;i<args.length;i+=2){if(!permitted.includes(args[i]) || !args[i+1] || opts[args[i]])reject('arguments');opts[args[i]]=args[i+1];}
  const mediaReviews=readMediaReviews(opts['--media-review']);let result;
  if(command==='build' && opts['--root'] && opts['--out'])result=buildRelease(opts['--root'],opts['--out'],{mediaReviews});
  else if(command==='verify' && opts['--archive'] && opts['--manifest'] && opts['--checksum']){const {entries,...report}=verifyRelease(opts['--archive'],opts['--manifest'],opts['--checksum'],{mediaReviews});result=report;if(opts['--extract'])result={...result,...extractRelease(entries,opts['--extract'])};}
  else if(command==='check' && opts['--root']){const scan=scanTree(opts['--root'],{mediaReviews});if(!scan.ok)reject('source_scan_failed');result={ok:true,...verifyEntries(scan.entries,{mediaReviews})};}
  else reject('arguments');
  console.log(JSON.stringify(result));
}
if(process.argv[1] && path.resolve(process.argv[1])===fileURLToPath(import.meta.url)) {try{main(process.argv.slice(2));}catch(err){console.error(JSON.stringify({ok:false,rule:err instanceof ScanError?err.rule:'package_failed'}));process.exitCode=1;}}
