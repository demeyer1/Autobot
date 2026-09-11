import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { hash, crc32, LIMITS, readBounded, inspectJpeg, scanText, scanEntries, scanTree, parseAllowlist } from '../scripts/publication-scan.mjs';
import { makeZip, readZip, canonicalArchiveMode, manifestFor, buildRelease, verifyRelease, extractRelease } from '../scripts/package.mjs';
const email = ['scanner-fixture', 'example.invalid'].join('@');
const b64 = text => Buffer.from(text).toString('base64');
const tree = () => fs.realpathSync(fs.mkdtempSync(path.join(os.tmpdir(), 'autobot-publication-test-')));
const put = (root,name,text,mode=0o644) => { const p=path.join(root,name);fs.mkdirSync(path.dirname(p),{recursive:true});fs.writeFileSync(p,text,{mode});fs.chmodSync(p,mode);return p; };
function seed(root) {
  put(root,'LICENSE',fs.readFileSync(new URL('../LICENSE',import.meta.url))); put(root,'VERSION','0.2.0\n');put(root,'run.sh','#!/bin/sh\nexit 0\n',0o755);
  put(root,'config/release-allowlist.txt',['LICENSE','VERSION','config/release-allowlist.txt','run.sh'].join('\n')+'\n');
}
const fixture = (name,bytes,mode=0o644) => [{path:name,bytes:Buffer.from(bytes),mode}];
function chunk(type,body) { const b=Buffer.alloc(12+body.length);b.writeUInt32BE(body.length);b.write(type,4);body.copy(b,8);b.writeUInt32BE(crc32(b.subarray(4,8+body.length)),8+body.length);return b; }
function png(extra=[]) { const header=Buffer.alloc(13);header.writeUInt32BE(1);header.writeUInt32BE(1,4);header[8]=8;header[9]=2;return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',header),...extra,chunk('IDAT',Buffer.from([120,156,99,96,96,96,0,0,0,4,0,1])),chunk('IEND',Buffer.alloc(0))]); }

test('generic text controls and nested encoding',()=>{
  scanText('General task instructions. Local schemas and empty user defaults.');
  for(const payload of [email,b64(email),b64(b64(email)),email.replace(/./g,c=>'%'+c.charCodeAt(0).toString(16))]) assert.throws(()=>scanText(payload),/email/);
  for(const payload of [['pass'+'word', '=','"','synthetic-secret','"'].join(''),['Authoriz'+'ation:','Bearer','fixturetoken012345'].join(' '),['https:/','/user:synthetic-secret','@example.invalid'].join(''),['https:/','/docs.google.com','/document/d/','synthetic-resource'].join(''),['https:/','/example.invalid/callback?','code=synthetic-once'].join('')])assert.throws(()=>scanText(payload));
  assert.throws(()=>scanText(['pass'+'word', 'synthetic-secret'].join('=')), /credential_assignment/);
  assert.throws(()=>scanText('safe'+String.fromCodePoint(0x202e)+'unsafe'),/hidden_unicode/);
  assert.throws(()=>scanText('x'.repeat(LIMITS.line+1)),/line_limit/);
  let encoded=email;for(let i=0;i<8;i++)encoded=b64(encoded);assert.throws(()=>scanText(encoded),/decode_depth/);
});
test('realistic checksum digest is data, but path is scanned',()=>{
  scanText('1234567890'+'a'.repeat(54)+'  safe.txt\n',{checksum:true});
  assert.throws(()=>scanText('a'.repeat(64)+'  '+email+'\n',{checksum:true}),/checksum_grammar/);
  assert.throws(()=>scanText('a'.repeat(64)+'  ../safe\n',{checksum:true}),/checksum_grammar/);
});
test('allowlist is sorted unique exact per-file schema',()=>{
  assert.deepEqual(parseAllowlist(Buffer.from('a\nb\n')),['a','b']);
  for(const value of ['a\na\n','A\na\n','a\na/b\n','b\na\n','../a\n','a','a\r\n','a b\n','/a\n'])assert.throws(()=>parseAllowlist(Buffer.from(value)));
});
test('text content, names, hidden paths and unsupported objects',()=>{
  for(const [name,bytes] of [['safe.txt',email],[email,'safe'],['.hidden','safe'],['dist/safe','safe'],['state/safe','safe'],['secret.log','safe'],['payload.txt',Buffer.from([0,1,2])],['payload.bin',Buffer.from([255,254])],['photo.jpg','printable unknown media'],['document.txt','%PDF-1.4'],['nested.zip','PK'],['symbolic.txt','safe']]) {
    const mode=name==='symbolic.txt'?0o777:0o644;
    assert.equal(scanEntries(fixture(name,bytes,mode),[name]).ok,false);
  }
  assert.throws(()=>scanEntries(fixture('a','safe'),['b']),/inventory_mismatch/);
});
test('media requires exact reviewed hash and metadata-free PNG',()=>{
  const bytes=png();const review=[{path:'image.png',sha256:hash(bytes),kind:'png',reviewed:true,reviewer:'independent-fixture-review'}];
  assert.equal(scanEntries(fixture('image.png',bytes),['image.png']).ok,false);
  assert.equal(scanEntries(fixture('image.png',bytes),['image.png'],{mediaReviews:review}).ok,true);
  const extra=png([chunk('tEXt',Buffer.from('Author'+String.fromCharCode(0)+'Synthetic'))]);
  assert.equal(scanEntries(fixture('image.png',extra),['image.png'],{mediaReviews:[{...review[0],sha256:hash(extra)}]}).ok,false);
  const bad=Buffer.from(bytes);bad[20]^=1;
  assert.equal(scanEntries(fixture('image.png',bad),['image.png'],{mediaReviews:[{...review[0],sha256:hash(bad)}]}).ok,false);
});
test('complete tree rejects unexpected files and directories without skips',()=>{
  const root=tree();try{seed(root);assert.equal(scanTree(root).ok,true);put(root,'state/private.txt',email);assert.throws(()=>scanTree(root),/private_or_generated_path/);fs.rmSync(path.join(root,'state'),{recursive:true});put(root,'surprise.txt','safe');assert.throws(()=>scanTree(root),/unlisted_file/);fs.unlinkSync(path.join(root,'surprise.txt'));fs.symlinkSync(path.join(root,'VERSION'),path.join(root,'surprise'));assert.throws(()=>scanTree(root),/symlink/);fs.unlinkSync(path.join(root,'surprise'));fs.linkSync(path.join(root,'VERSION'),path.join(root,'surprise'));assert.throws(()=>scanTree(root),/nonregular/);}finally{fs.rmSync(root,{recursive:true,force:true});}
});
test('fixed CLI diagnostics contain no payload or input path',()=>{
  const root=tree();try{seed(root);put(root,'run.sh',email,0o755);const cli=fileURLToPath(new URL('../scripts/publication-scan.mjs',import.meta.url));const r=spawnSync(process.execPath,[cli,'--root',root],{encoding:'utf8'});assert.equal(r.status,1);assert.ok(!r.stdout.includes(email)&&!r.stderr.includes(email));assert.ok(!r.stdout.includes(root)&&!r.stderr.includes(root));const value=JSON.parse(r.stdout);assert.equal(value.findings[0].rule,'email');}finally{fs.rmSync(root,{recursive:true,force:true});}
});
test('ZIP is reproducible, no extras, exact bytes/modes and strict headers',()=>{
  const entries=[{path:'b.sh',mode:0o755,bytes:Buffer.from('run')},{path:'a',mode:0o644,bytes:Buffer.from('text')}];const a=makeZip(entries);assert.deepEqual(a,makeZip([...entries].reverse()));const decoded=readZip(a);assert.equal(decoded[0].path,'a');assert.equal(decoded[1].mode,0o755);assert.equal(manifestFor(decoded),manifestFor(entries));
  for(const offset of [0,6,8,12,14,28,a.length-22,a.length-2]){const bad=Buffer.from(a);bad[offset]^=1;assert.throws(()=>readZip(bad));}
  assert.throws(()=>readZip(Buffer.concat([a,Buffer.from([0])])));
  assert.throws(()=>makeZip([{path:'../escape',mode:0o644,bytes:Buffer.from('bad')}]));assert.throws(()=>makeZip([...entries,entries[0]]));
});
test('actual package build, reread, extract, checksum failure and output nonoverwrite',()=>{
  const temp=tree();try{const root=path.join(temp,'candidate with spaces');fs.mkdirSync(root);seed(root);const one=path.join(temp,'one');const two=path.join(temp,'two');const a=buildRelease(root,one);const b=buildRelease(root,two);assert.equal(a.sha256,b.sha256);const archive=path.join(one,a.archive),manifest=path.join(one,'AutoAssist-v0.2.0.manifest.sha256'),checksum=archive+'.sha256';const verified=verifyRelease(archive,manifest,checksum);const dest=path.join(temp,'extracted');extractRelease(verified.entries,dest);assert.equal(scanTree(path.join(dest,'AutoAssist')).ok,true);assert.equal(fs.statSync(path.join(dest,'AutoAssist/run.sh')).mode&0o777,0o755);assert.throws(()=>buildRelease(root,one),/output_exists/);assert.throws(()=>extractRelease(verified.entries,dest),/output_exists/);fs.appendFileSync(checksum,'extra\n');assert.throws(()=>verifyRelease(archive,manifest,checksum),/release_integrity/);}finally{fs.rmSync(temp,{recursive:true,force:true});}
});

test('bounded reads reject growth without consuming unbounded bytes',()=>{
  const root=tree();const file=put(root,'growth.txt','abc');const original=fs.readSync;let largest=0,total=0,injected=false;
  try {fs.readSync=function(fd,buffer,offset,length,position){largest=Math.max(largest,length);if(!injected){injected=true;fs.appendFileSync(file,Buffer.alloc(1024*1024));}const got=original(fd,buffer,offset,length,position);total+=got;return got;};assert.throws(()=>readBounded(file),/input_changed/);assert.ok(largest<=3);assert.ok(total<=4);}finally{fs.readSync=original;fs.rmSync(root,{recursive:true,force:true});}
});
test('aggregate stat budget rejects before retaining file payloads',()=>{
  const root=tree();const original=fs.readSync;let readBytes=0;
  try {const names=[];for(let i=0;i<33;i++){const name='f'+String(i).padStart(2,'0')+'.txt';names.push(name);const f=put(root,name,'');fs.truncateSync(f,LIMITS.file);}names.push('config/release-allowlist.txt');put(root,'config/release-allowlist.txt',names.sort().join('\n')+'\n');fs.readSync=function(...args){const count=original(...args);readBytes+=count;return count;};assert.throws(()=>scanTree(root),/input_limit/);assert.ok(readBytes<2048);}finally{fs.readSync=original;fs.rmSync(root,{recursive:true,force:true});}
});
test('canonical archive modes are independent of web source modes',()=>{
  const names=['Install.command','install.sh','runtime/bin/autoassist','runtime/core/main.mjs','README.md','benchmarks/reference.py'];const entries=names.map(p=>({path:p,mode:0o644,bytes:Buffer.from('synthetic fixture')}));const decoded=readZip(makeZip(entries));for(const e of decoded)assert.equal(e.mode,canonicalArchiveMode(e.path));assert.equal(decoded.find(e=>e.path==='install.sh').mode,0o755);assert.equal(decoded.find(e=>e.path==='benchmarks/reference.py').mode,0o644);assert.deepEqual(makeZip(entries),makeZip(entries.map(e=>({...e,mode:e.path.startsWith('benchmarks/')?0o644:0o755}))));assert.throws(()=>makeZip([{path:'benchmarks/reference.py',mode:0o755,bytes:Buffer.from('safe')}]),/source_mode/);
  const zip=makeZip([{path:'install.sh',mode:0o644,bytes:Buffer.from('safe')}]);const end=zip.length-22;const central=zip.readUInt32LE(end+16);zip.writeUInt32LE((0o100644*65536)>>>0,central+38);assert.throws(()=>readZip(zip),/zip_mode_policy/);
});
function jpegSegment(marker,body){const b=Buffer.alloc(body.length+4);b[0]=255;b[1]=marker;b.writeUInt16BE(body.length+2,2);body.copy(b,4);return b;}
function jpegFixture(metadata=[]){return Buffer.concat([Buffer.from([255,216]),...metadata,jpegSegment(0xc0,Buffer.from([8,0,1,0,1,3,1,17,0,2,17,0,3,17,0])),jpegSegment(0xda,Buffer.from([3,1,0,2,0,3,0,0,63,0])),Buffer.from([1,255,0,2,255,208,3,255,217])]);}
test('JPEG requires exact image and separately reviewed APP segment hashes',()=>{
  const app=jpegSegment(0xe0,Buffer.from([74,70,73,70,0,1,1,0,0,72,0,72,0,0]));const bytes=jpegFixture([app]);const name='chart.jpg';const metadata=inspectJpeg(bytes).metadataSegments;const review={path:name,sha256:hash(bytes),kind:'jpeg',reviewed:true,reviewer:'fixture-review',metadataReviewed:true,metadataReviewer:'fixture-metadata-review',metadataSegments:metadata};
  assert.equal(scanEntries(fixture(name,bytes),[name],{mediaReviews:[review]}).ok,true);assert.equal(scanEntries(fixture(name,bytes),[name],{mediaReviews:[{...review,metadataSegments:[]}]}).ok,false);assert.equal(scanEntries(fixture(name,bytes),[name],{mediaReviews:[{...review,metadataReviewed:false}]}).ok,false);
  const secret=jpegFixture([app,jpegSegment(0xfe,Buffer.from(email))]);assert.equal(scanEntries(fixture(name,secret),[name],{mediaReviews:[{...review,sha256:hash(secret)}]}).ok,false);assert.throws(()=>inspectJpeg(Buffer.concat([bytes,Buffer.from('hidden')])));const changed=Buffer.from(bytes);changed[15]^=1;assert.equal(scanEntries(fixture(name,changed),[name],{mediaReviews:[review]}).ok,false);
});
test('passive CSV Python and checksum names remain scanned text',()=>{
  for(const name of ['data.csv','reference.py']){assert.equal(scanEntries(fixture(name,'synthetic,public\n'),[name]).ok,true);assert.equal(scanEntries(fixture(name,email),[name]).ok,false);}
  assert.equal(scanEntries(fixture('SHA256SUMS','a'.repeat(64)+'  safe.csv\n'),['SHA256SUMS']).ok,true);assert.equal(scanEntries(fixture('SHA256SUMS','a'.repeat(64)+'  ../private\n'),['SHA256SUMS']).ok,false);
});


test('standard context containers extract within the exclusive output root',()=>{
  const temp=tree();
  try {
    const root=path.join(temp,'candidate');fs.mkdirSync(root);seed(root);
    put(root,'00_CONTEXT/MEMORY.md','# Memory\n\nEmpty user context.\n');
    const list=path.join(root,'config/release-allowlist.txt');
    fs.writeFileSync(list,['00_CONTEXT/MEMORY.md',...fs.readFileSync(list,'utf8').trim().split('\n')].sort().join('\n')+'\n');
    const out=path.join(temp,'package'),built=buildRelease(root,out);
    const archive=path.join(out,built.archive);
    const verified=verifyRelease(archive,path.join(out,'AutoAssist-v0.2.0.manifest.sha256'),archive+'.sha256');
    const dest=path.join(temp,'extracted');extractRelease(verified.entries,dest);
    assert.equal(fs.readFileSync(path.join(dest,'AutoAssist/00_CONTEXT/MEMORY.md'),'utf8'),'# Memory\n\nEmpty user context.\n');
    assert.equal(scanTree(path.join(dest,'AutoAssist')).ok,true);
    assert.throws(()=>scanTree(path.join(root,'00_CONTEXT')),/unsafe_root/);
  } finally { fs.rmSync(temp,{recursive:true,force:true}); }
});
