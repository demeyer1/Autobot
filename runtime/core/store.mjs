import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';

export const MAX_STORE_BYTES = 16 * 1024 * 1024;
export const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
export const canonical = value => JSON.stringify(value, (_, v) => v && !Array.isArray(v) && typeof v === 'object' ? Object.fromEntries(Object.entries(v).sort(([a],[b]) => a.localeCompare(b))) : v);
export const fail = (code, message = code) => { const e = new Error(message); e.code = code; throw e; };
export function text(value, name = 'text', max = 4000) {
  if (typeof value !== 'string' || !value.trim() || value.length > max || value.includes('\0')) fail('invalid_input', `Invalid ${name}`);
  return value.trim();
}
export function id(value) { const v = text(value, 'id', 100); if (!/^[a-zA-Z0-9][a-zA-Z0-9._-]*$/.test(v) || ['__proto__','constructor','prototype'].includes(v)) fail('invalid_id'); return v; }
export function confined(root, value, { exists = true, directory = false } = {}) {
  if (!path.isAbsolute(value)) fail('absolute_path_required');
  const p = path.resolve(value), rel = path.relative(root, p);
  if (rel.startsWith('..') || path.isAbsolute(rel)) fail('path_outside_installation');
  let part = path.parse(p).root;
  for (const name of p.split(path.sep).filter(Boolean)) {
    part = path.join(part, name);
    if (!fs.existsSync(part)) { if (exists) fail('path_missing'); else continue; }
    const s = fs.lstatSync(part);
    if (s.isSymbolicLink()) fail('symlink_rejected');
    if (part !== p && !s.isDirectory()) fail('unsafe_ancestor');
  }
  if (exists) {
    const s = fs.lstatSync(p);
    if (directory ? !s.isDirectory() : (!s.isFile() || s.nlink !== 1)) fail('unsafe_file');
  }
  return p;
}
export function validateRoot(value) {
  const root = path.resolve(text(value, 'root'));
  if (!path.isAbsolute(value) || root === path.parse(root).root) fail('invalid_root');
  confined(root, root, {directory:true});
  if (fs.statSync(root).uid !== process.getuid()) fail('wrong_owner');
  return root;
}
export function emptyStore() { return { schema:2, revision:0, roots:{}, memory:{}, sessions:{}, issues:{}, queue:{}, outbox:{}, notification:null, legacy_imports:{}, orphan_history:{}, time_zone:'UTC', last_tick:null }; }
export function validateStore(s) {
  if (!s || s.schema !== 2 || !Number.isSafeInteger(s.revision) || s.revision < 0) fail('unsupported_state_schema');
  for (const k of ['roots','memory','sessions','issues','queue','outbox','legacy_imports']) if (!s[k] || typeof s[k] !== 'object' || Array.isArray(s[k])) fail('invalid_store');
  return s;
}
export function readStore(root) {
  const file = path.join(root,'state/core.json');
  if (!fs.existsSync(file)) return emptyStore();
  confined(root,file);
  if (fs.statSync(file).size > MAX_STORE_BYTES) fail('store_too_large');
  return validateStore(JSON.parse(fs.readFileSync(file,'utf8')));
}
export function atomicWrite(file, value) {
  const data = Buffer.from(JSON.stringify(value,null,2)+'\n');
  if (data.length > MAX_STORE_BYTES) fail('store_too_large');
  const tmp = `${file}.${process.pid}.${crypto.randomUUID()}.tmp`;
  let fd;
  try {
    fd=fs.openSync(tmp,'wx',0o600);fs.writeFileSync(fd,data);fs.fsyncSync(fd);fs.closeSync(fd);fd=undefined;
    fs.renameSync(tmp,file);
    const dir=fs.openSync(path.dirname(file),'r');try {fs.fsyncSync(dir);} finally {fs.closeSync(dir);}
  } finally {if(fd!==undefined) fs.closeSync(fd);if(fs.existsSync(tmp)) fs.unlinkSync(tmp);}
}
export function mutate(root, operation, {expected_revision}={}) {
  root=validateRoot(root);
  const migration=path.join(root,'.install-state/migration.lock');
  if (fs.existsSync(migration)) fail('installation_migrating');
  const dir=path.join(root,'state');confined(root,dir,{exists:false});
  fs.mkdirSync(dir,{recursive:true,mode:0o700});fs.chmodSync(dir,0o700);
  const lock=path.join(dir,'.core.lock'), token=crypto.randomUUID();
  const deadline=Date.now()+2000;
  while (true) {
    try {fs.mkdirSync(lock,{mode:0o700});break;} catch(e) {
      if(e.code!=='EEXIST') throw e;
      if(Date.now()>=deadline) fail('state_locked');
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)),0,0,20);
    }
  }
  fs.writeFileSync(path.join(lock,'owner.json'),JSON.stringify({pid:process.pid,token,created_at:new Date().toISOString()}),{mode:0o600,flag:'wx'});
  try {
    if(fs.existsSync(migration)) fail('installation_migrating');
    const current=readStore(root);
    if(expected_revision!==undefined && expected_revision!==current.revision) fail('stale_store_revision');
    const before=JSON.stringify(current);
    const result=operation(current);
    if(result && typeof result.then==='function') fail('async_transaction_forbidden');
    validateStore(current);if(JSON.stringify(current)===before)return result;current.revision++;
    atomicWrite(path.join(dir,'core.json'),current);
    return result;
  } finally {
    const owner=JSON.parse(fs.readFileSync(path.join(lock,'owner.json'),'utf8'));
    if(owner.token!==token || owner.pid!==process.pid) fail('lock_owner_changed');
    fs.unlinkSync(path.join(lock,'owner.json'));fs.rmdirSync(lock);
  }
}
// Explicit recovery only: never steal a fresh lock or a live process's lock.
export function recoverLock(root) {
  validateRoot(root);
  const lock=path.join(root,'state/.core.lock'), file=path.join(lock,'owner.json');
  confined(root,lock,{directory:true});
  if(!fs.existsSync(file)){
    const snapshot=fs.lstatSync(lock);
    if(snapshot.uid!==process.getuid()||Date.now()-snapshot.mtimeMs<300000||fs.readdirSync(lock).length!==0)fail('lock_not_recoverable');
    const check=fs.lstatSync(lock);
    if(check.dev!==snapshot.dev||check.ino!==snapshot.ino||check.mtimeMs!==snapshot.mtimeMs||fs.readdirSync(lock).length!==0)fail('lock_changed');
    // rmdir is atomic and refuses a lock whose owner file appeared meanwhile.
    fs.rmdirSync(lock);return {recovered:true,kind:'stale_empty_incomplete_claim'};
  }
  confined(root,file);const s=fs.statSync(file),o=JSON.parse(fs.readFileSync(file,'utf8'));
  if(Date.now()-s.mtimeMs<300000 || !Number.isSafeInteger(o.pid) || o.pid<2 || typeof o.token!=='string') fail('lock_not_recoverable');
  try {process.kill(o.pid,0);fail('lock_owner_alive');} catch(e) {if(e.code!=='ESRCH') throw e;}
  if(fs.readFileSync(file,'utf8')!==JSON.stringify(o)) fail('lock_changed');
  fs.unlinkSync(file);fs.rmdirSync(lock);return {recovered:true};
}
export function evidence(root, file) {
  const p=confined(root,file);const s=fs.statSync(p);
  if(s.size>1024*1024) fail('evidence_too_large');
  const bytes=fs.readFileSync(p);
  return {path:path.relative(root,p),sha256:sha(bytes),bytes_base64:bytes.toString('base64'),size:bytes.length};
}
