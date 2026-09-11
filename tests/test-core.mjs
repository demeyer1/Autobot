#!/usr/bin/env node
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawn} from 'node:child_process';
import {execute,STAGES} from '../runtime/core/core.mjs';
import {sha,readStore,mutate,atomicWrite} from '../runtime/core/store.mjs';
const source=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const base=fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()),'autobot-core-test-'));let checks=0;
const ok=(v,m)=>{assert.ok(v,m);checks++;};
const equal=(a,b,m)=>{assert.deepEqual(a,b,m);checks++;};
const rejects=(fn,code)=>{assert.throws(fn,e=>e.code===code);checks++;};
function fixture(name){const root=path.join(base,name);fs.mkdirSync(path.join(root,'runtime'),{recursive:true});fs.cpSync(path.join(source,'runtime/core'),path.join(root,'runtime/core'),{recursive:true});fs.mkdirSync(path.join(root,'03_OUTPUTS'));return root;}
function call(root,action,a={}){return execute(root,action,a);}
function start(root,id='task-one',dest={kind:'local',destination:'03_OUTPUTS/result.txt'}){
 const content='Synthetic final artifact';if(dest.kind==='local')fs.writeFileSync(path.resolve(root,dest.destination),content);
 const r=call(root,'root-create',{root_id:id,title:'Synthetic report',intent:'Produce and verify the synthetic report.',source:'direct_user',target:dest,content_sha256:sha(content)});
 const owner=call(root,'claim',{root_id:id,actor:'producer'});return {root_id:id,owner_token:owner.token,actor:'producer'};
}
function stateBytes(root){const p=path.join(root,'state/core.json');return fs.existsSync(p)?fs.readFileSync(p,'utf8'):null;}
function current(root,key='task-one'){return call(root,'read',{root_id:key}).root.deliverables.default;}
function report(root,ctx,stage,extra={}){
 const d=current(root,ctx.root_id),file=path.join(root,'03_OUTPUTS',stage+'.txt');fs.writeFileSync(file,'Synthetic '+stage);
 return call(root,'evidence-add',{...ctx,stage,file,attempt_id:d.attempt_id,content_sha256:d.expected_content_sha256,target:d.target,...extra});
}
function review(root,ctx,stage,extra={}){const d=current(root,ctx.root_id);return call(root,'review',{root_id:ctx.root_id,stage,validator:'reviewer',attempt_id:d.attempt_id,content_sha256:d.expected_content_sha256,target:d.target,result:'validated',reason:'Inspected exact synthetic output and target.',...extra});}
try{
 const root=fixture('account home/Autobot Workspace');equal(call(root,'read').roots,[]);ok(!fs.existsSync(path.join(root,'state')),'read does not initialize state');
 rejects(()=>call(root,'root-create',{root_id:'not-authorized',title:'No provenance'}),'direct_user_source_required');
 const ctx=start(root);equal(call(root,'read').roots.length,1);rejects(()=>call(root,'claim',{root_id:ctx.root_id,actor:'other'}),'already_owned');
 rejects(()=>call(root,'checkpoint',{...ctx,owner_token:'wrong',summary:'x',next_action:'y'}),'owner_required');
 const before=stateBytes(root);rejects(()=>call(root,'checkpoint',{...ctx,summary:'x',next_action:'y',expected_revision:0}),'stale_store_revision');equal(stateBytes(root),before);
 call(root,'requirements',{...ctx,items:[{id:'r1',summary:'Correct report',target:'result'},{id:'r2',summary:'Retain source',target:'source',depends_on:['r1']}]});
 const noOp=stateBytes(root);call(root,'requirements',{...ctx,items:[{id:'r1',summary:'Correct report',target:'result'},{id:'r2',summary:'Retain source',target:'source',depends_on:['r1']}]});equal(stateBytes(root),noOp,'identical contract is no-op');
 assert.throws(()=>call(root,'requirements',{...ctx,items:[{id:'r1',summary:'Correct report',target:'result'}]}));checks++;
 assert.throws(()=>call(root,'requirements',{...ctx,items:[{id:'a',summary:'a',target:'a',depends_on:['b']},{id:'b',summary:'b',target:'b',depends_on:['a']}]}));checks++;
 let d=current(root);rejects(()=>report(root,ctx,'draft_complete'),'prior_stage_required');rejects(()=>report(root,ctx,'research_complete',{attempt_id:'old'}),'stale_attempt');rejects(()=>report(root,ctx,'research_complete',{target:{kind:'local',destination:'elsewhere'}}),'wrong_target');
 for(const stage of STAGES){
  const e=report(root,ctx,stage);d=current(root);
  rejects(()=>review(root,ctx,stage,{validator:'PRODUCER'}),'invalid_review_evidence');
  review(root,ctx,stage,{requirement_digest:d.requirements.digest,requirement_support:stage===STAGES.at(-1)?d.requirements.items.map(i=>({requirement_id:i.id,evidence_id:e.evidence_id,result:'supported',reason:'Exact clause verified in final artifact.'})):[],requirement_coverage:{all_requested_clauses_covered:true,reason:'All original clauses accounted for.'}});
 }
 ok(call(root,'read',{root_id:ctx.root_id}).readiness.complete);fs.appendFileSync(path.join(root,'03_OUTPUTS/result.txt'),' changed');ok(!call(root,'read',{root_id:ctx.root_id}).readiness.complete,'actual target edit invalidates completion');fs.writeFileSync(path.join(root,'03_OUTPUTS/result.txt'),'Synthetic final artifact');equal(call(root,'orphans').items,[],'completed roots are not orphans');
 call(root,'proof-record',{...ctx,stage:'research_complete'});ok(call(root,'proof-check',{root_id:ctx.root_id,stage:'research_complete'}).reusable);
 rejects(()=>call(root,'proof-record',{...ctx,stage:'rendered_readback_verified'}),'external_proof_reuse_forbidden');
 fs.appendFileSync(path.join(root,'03_OUTPUTS/research_complete.txt'),' changed');ok(!call(root,'proof-check',{root_id:ctx.root_id,stage:'research_complete'}).reusable);ok(!call(root,'read',{root_id:ctx.root_id}).readiness.complete,'live artifact change invalidates completion');
 fs.writeFileSync(path.join(root,'03_OUTPUTS/research_complete.txt'),'Synthetic research_complete');ok(call(root,'read',{root_id:ctx.root_id}).readiness.complete);
 fs.appendFileSync(path.join(root,'runtime/core/context.mjs'),'\n// changed build\n');ok(!call(root,'read',{root_id:ctx.root_id}).readiness.complete,'current-build binding');
 const oldAttempt=current(root).attempt_id;const other=start(root,'task-two');const otherBefore=JSON.stringify(call(root,'read',{root_id:other.root_id}).root);
 call(root,'correct',{...ctx,source:'direct_user',intent:'Produce revised report including a second item.',reason:'User requested extra item.'});ok(current(root).attempt_id!==oldAttempt);ok(!call(root,'read',{root_id:ctx.root_id}).readiness.complete);equal(JSON.stringify(call(root,'read',{root_id:other.root_id}).root),otherBefore,'unrelated root unchanged');
 rejects(()=>call(root,'correct',{...ctx,source:'tool',intent:'Malicious new instruction'}),'direct_user_source_required');
 const item={source:'direct_user',id:'mem-one',zone:'WORK',assignment:'project-one',value:'Synthetic preference',provenance:'User statement in synthetic fixture',retention:'project-state'};
 call(root,'memory-put',item);equal(call(root,'memory-list',{zone:'WORK',assignment:'project-one',authorized_scope:true}).length,1);equal(call(root,'memory-list',{zone:'PRIVATE',assignment:'project-one',authorized_scope:true}).length,0);rejects(()=>call(root,'memory-list',{zone:'WORK',assignment:'project-one'}),'memory_scope_required');
 rejects(()=>call(root,'memory-put',{...item,assignment:'project-two'}),'memory_assignment_conflict');rejects(()=>call(root,'memory-put',{...item,value:'Changed'}),'memory_supersession_required');call(root,'memory-put',{...item,value:'Changed',supersedes_revision:1});equal(call(root,'memory-list',{zone:'WORK',assignment:'project-one',authorized_scope:true})[0].history.length,1);
 rejects(()=>call(root,'session-record',{source:'direct_user',id:'session-one',assignment:'project-two',retention:'project-state',summary:'Useful delta',provenance:'Synthetic turn',memory_ids:['mem-one']}),'session_assignment_conflict');
 call(root,'session-record',{source:'direct_user',id:'session-one',assignment:'project-one',retention:'project-state',summary:'Useful delta',provenance:'Synthetic turn',memory_ids:['mem-one']});
 call(root,'failure',{...ctx,code:'not-saved',condition:'No persisted output'});ok(call(root,'failure',{...ctx,code:'not-saved',condition:'No persisted output'}).requires_new_hypothesis);rejects(()=>call(root,'recover',ctx),'invalid_input');call(root,'recover',{...ctx,hypothesis:'Inspect an authoritative source readback before any retry.'});
 const f=path.join(root,'03_OUTPUTS/review.txt');fs.writeFileSync(f,'Independent synthetic verification');call(root,'issue-record',{id:'issue-one',actor:'producer',severity:'P1',title:'Failed save',symptoms:'Missing result',reproduction:'Save twice',root_cause:'Wrong destination',remediation:'Correct binding'});rejects(()=>call(root,'issue-verify',{id:'issue-one',validator:'producer',result:'passed',file:f,reason:'Checked'}),'independent_validator_required');call(root,'issue-verify',{id:'issue-one',validator:'reviewer',result:'passed',file:f,reason:'Reproduced then independently verified repair'});
 const qTarget={kind:'external',destination:'https://example.invalid/inbox',account:'test-account',recipient:'synthetic-recipient'};
 rejects(()=>call(root,'outbox-enqueue',{source:'direct_user',root_id:ctx.root_id,id:'notice-one',target:qTarget,payload:'Finished'}),'notification_not_configured');
 const q=call(root,'queue-enqueue',{source:'direct_user',root_id:ctx.root_id,id:'handoff-one',target:qTarget,payload:'Synthetic payload'});equal(call(root,'queue-enqueue',{source:'direct_user',root_id:ctx.root_id,id:'another-key',target:qTarget,payload:'Synthetic payload'}).id,q.id,'semantic duplicate suppressed');
 const claimed=call(root,'queue-claim',{id:q.id,actor:'producer'});const binding={id:q.id,target:qTarget,payload_sha256:q.payload_sha256,claim_token:claimed.claim.token};call(root,'queue-transition',{...binding,state:'dispatched'});call(root,'queue-transition',{...binding,state:'uncertain'});rejects(()=>call(root,'queue-claim',{id:q.id,actor:'producer'}),'handoff_not_pending');rejects(()=>call(root,'queue-archive',{id:q.id}),'unverified_handoff');
 rejects(()=>call(root,'queue-transition',{...binding,state:'pending',validator:'reviewer',file:f,observed_at:new Date().toISOString()}),'no_action_proof_required');call(root,'queue-transition',{...binding,state:'verified',validator:'reviewer',file:f,observed_at:new Date().toISOString(),unique:true,persisted:true,failure:false,attribution:false});call(root,'queue-archive',{id:q.id});equal(call(root,'queue-list')[0].state,'archived');
 const context=path.join(root,'03_OUTPUTS/contract.md');fs.writeFileSync(context,'x'.repeat(20000)+'\n<!-- AUTOBOT_CONTEXT_CAPSULE_V1:producer -->\nExact short task.\n<!-- /AUTOBOT_CONTEXT_CAPSULE_V1:producer -->');equal(call(root,'context',{file:context,phase:'producer'}).mode,'capsule');equal(call(root,'context',{file:context,phase:'validator'}).mode,'full');
 const outside=path.join(base,'outside');fs.writeFileSync(outside,'outside');rejects(()=>call(root,'context',{file:outside,phase:'producer'}),'path_outside_installation');fs.symlinkSync(outside,path.join(root,'03_OUTPUTS/link'));rejects(()=>call(root,'context',{file:path.join(root,'03_OUTPUTS/link'),phase:'producer'}),'symlink_rejected');
 fs.mkdirSync(path.join(root,'.install-state'),{recursive:true});fs.mkdirSync(path.join(root,'.install-state/migration.lock'));rejects(()=>call(root,'tick'),'installation_migrating');fs.rmdirSync(path.join(root,'.install-state/migration.lock'));
 call(root,'tick');equal(call(root,'orphans').status,'current');
 // External stages need fresh exact account, recipient, content and persisted unique readback.
 const er=fixture('external'),ec=start(er,'external-one',qTarget);for(const stage of STAGES.slice(0,2)){report(er,ec,stage);review(er,ec,stage);}
 rejects(()=>report(er,ec,'destination_updated'),'external_observation_required');const ed=current(er,ec.root_id);const observation={kind:'destination_updated',persisted:true,unique:true,failure:false,attribution:false,target:qTarget,content_sha256:ed.expected_content_sha256,observed_at:new Date().toISOString()};rejects(()=>report(er,ec,'destination_updated',{observation:{...observation,target:{...qTarget,account:'wrong'}}}),'wrong_target');rejects(()=>report(er,ec,'destination_updated',{observation:{...observation,observed_at:'2000-01-01T00:00:00Z'}}),'stale_observation');report(er,ec,'destination_updated',{observation});review(er,ec,'destination_updated',{observation});
 // Proofs bind actual target bytes, not only the expected hash stored in the ledger.
 const ar=fixture('proof-artifact'),ac=start(ar);report(ar,ac,'research_complete');review(ar,ac,'research_complete');call(ar,'proof-record',{...ac,stage:'research_complete'});fs.writeFileSync(path.join(ar,'03_OUTPUTS/result.txt'),'changed artifact');ok(!call(ar,'proof-check',{root_id:ac.root_id,stage:'research_complete'}).reusable);rejects(()=>call(ar,'proof-record',{...ac,stage:'research_complete'}),'proof_not_validated');fs.unlinkSync(path.join(ar,'03_OUTPUTS/result.txt'));ok(!call(ar,'proof-check',{root_id:ac.root_id,stage:'research_complete'}).reusable);rejects(()=>call(ar,'proof-record',{...ac,stage:'research_complete'}),'proof_not_validated');
 // Existing issue IDs never transfer ownership or overwrite a different report.
 const ir=fixture('issue-collision'),issueInput={id:'collision',actor:'owner',title:'Original issue',severity:'P2',symptoms:'Original symptom',reproduction:'Original reproduction',root_cause:'Original cause',remediation:'Original repair'};call(ir,'issue-record',issueInput);const issueBefore=stateBytes(ir);call(ir,'issue-record',issueInput);equal(stateBytes(ir),issueBefore);rejects(()=>call(ir,'issue-record',{...issueInput,actor:'other',title:'Replacement'}),'wrong_issue_owner');rejects(()=>call(ir,'issue-record',{...issueInput,title:'Replacement'}),'issue_id_conflict');equal(stateBytes(ir),issueBefore);
 // A validated old-build stage must not be laundered into a fresh reusable proof.
 const pr=fixture('proof-build'),pc=start(pr);report(pr,pc,'research_complete');review(pr,pc,'research_complete');fs.appendFileSync(path.join(pr,'runtime/core/context.mjs'),'\n// new build\n');rejects(()=>call(pr,'proof-record',{...pc,stage:'research_complete'}),'proof_not_validated');ok(!call(pr,'proof-check',{root_id:pc.root_id,stage:'research_complete'}).reusable);
 // Refining requirements after all stages pass opens a legitimate same-artifact re-review.
 const rr=fixture('requirement-refine'),rc=start(rr);for(const stage of STAGES){report(rr,rc,stage);review(rr,rc,stage);}ok(call(rr,'read',{root_id:rc.root_id}).readiness.complete);const attempt=current(rr).attempt_id;
 call(rr,'requirements',{...rc,items:[{id:'r1',summary:'Output still correct',target:'03_OUTPUTS/result.txt'}]});ok(current(rr).attempt_id!==attempt);equal(current(rr).stages.research_complete.status,'pending');
 const contractNoOp=stateBytes(rr);call(rr,'requirements',{...rc,items:[{id:'r1',summary:'Output still correct',target:'03_OUTPUTS/result.txt'}]});equal(stateBytes(rr),contractNoOp);
 for(const stage of STAGES){const e=report(rr,rc,stage),d=current(rr);review(rr,rc,stage,{requirement_digest:d.requirements.digest,requirement_support:stage===STAGES.at(-1)?[{requirement_id:'r1',evidence_id:e.evidence_id,result:'supported',reason:'Unchanged actual artifact independently inspected.'}]:[],requirement_coverage:{all_requested_clauses_covered:true,reason:'Full requested clause retained.'}});}ok(call(rr,'read',{root_id:rc.root_id}).readiness.complete);
 // A rejected evidence report can be replaced without inventing new user intent or output.
 const jr=fixture('rejected-evidence'),jc=start(jr);report(jr,jc,'research_complete');review(jr,jc,'research_complete',{result:'rejected'});const priorIntent=call(jr,'read',{root_id:jc.root_id}).root.intent_sha256,priorContent=current(jr).expected_content_sha256;
 call(jr,'retry',{...jc,reason:'Replace insufficient evidence with an independent source readback.'});equal(call(jr,'read',{root_id:jc.root_id}).root.intent_sha256,priorIntent);equal(current(jr).expected_content_sha256,priorContent);report(jr,jc,'research_complete');review(jr,jc,'research_complete');equal(current(jr).stages.research_complete.status,'validated');
 // Crash between lock directory creation and owner write has explicit bounded recovery.
 const lr=fixture('empty-lock');fs.mkdirSync(path.join(lr,'state/.core.lock'),{recursive:true});rejects(()=>call(lr,'recover-lock'),'lock_not_recoverable');fs.utimesSync(path.join(lr,'state/.core.lock'),new Date(0),new Date(0));ok(call(lr,'recover-lock').recovered);ok(!fs.existsSync(path.join(lr,'state/.core.lock')));
 // Multiple processes update one store without losing an independently created root.
 const cr=fixture('concurrent');const script=`import {execute} from ${JSON.stringify(new URL('../runtime/core/core.mjs',import.meta.url).href)};execute(process.argv[1],'root-create',{root_id:process.argv[2],title:'Parallel root',source:'direct_user'});`;
 const jobs=Array.from({length:8},(_,i)=>new Promise((resolve,reject)=>{const p=spawn(process.execPath,['--input-type=module','-e',script,cr,'parallel-'+i],{stdio:'pipe'});let err='';p.stderr.on('data',x=>err+=x);p.on('exit',code=>code===0?resolve():reject(new Error(err)));}));await Promise.all(jobs);equal(call(cr,'read').roots.length,8);
 // Crash before commit leaves the last JSON intact; a fresh dead lock is not stolen.
 const crashScript=`import {mutate} from ${JSON.stringify(new URL('../runtime/core/store.mjs',import.meta.url).href)};mutate(process.argv[1],s=>{s.revision=999;process.exit(77)});`;
 const preCrash=stateBytes(cr);await new Promise(resolve=>{const p=spawn(process.execPath,['--input-type=module','-e',crashScript,cr]);p.on('exit',resolve);});equal(stateBytes(cr),preCrash);rejects(()=>call(cr,'recover-lock'),'lock_not_recoverable');const owner=path.join(cr,'state/.core.lock/owner.json');fs.utimesSync(owner,new Date(0),new Date(0));ok(call(cr,'recover-lock').recovered);equal(call(cr,'read').roots.length,8);
 console.log(JSON.stringify({status:'passed',checks,scenarios:['single-store','legacy-boundaries','requirements','independent-review','wrong-target','stale-content-attempt-build','memory-scope-provenance','bounded-recovery','issues','uncertain-handoff','capsules-proofs','migration-lock','concurrency','crash-lock-recovery'],isolation:'Disposable explicit filesystem roots; no installer, native UI, model, network or live scheduler.'}));
}finally{fs.rmSync(base,{recursive:true,force:true});}
