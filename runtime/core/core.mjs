import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {sha,canonical,fail,text,id,confined,validateRoot,readStore,mutate,evidence,recoverLock} from './store.mjs';
import {reviseRequirements,reviewRequirements,requirementReadiness} from './requirements.mjs';
import {compileTaskContext} from './context.mjs';

export const STAGES=['research_complete','draft_complete','destination_updated','save_confirmed','rendered_readback_verified'];
const ZONES=['PRIVATE','FAMILY_FRIENDS','WORK','SHARED'];
const RETENTION=['durable-personal','durable-operating','project-state','action-audit-only','no-durable-delta'];
const now=()=>new Date().toISOString();
const uuid=()=>crypto.randomUUID();
const hashValue=v=>sha(canonical(v));
const actor=v=>text(v,'actor',128);
const different=(a,b)=>a.trim().toLocaleLowerCase()!==b.trim().toLocaleLowerCase();
const direct=a=>{if(a.source!=='direct_user')fail('direct_user_source_required');};
const rootOf=(s,a)=>s.roots[id(a.root_id)]||fail('unknown_root');
const deliverableOf=(r,a)=>r.deliverables[id(a.deliverable_id||'default')]||fail('unknown_deliverable');
const freshStages=attempt=>Object.fromEntries(STAGES.map(k=>[k,{status:'pending',attempt_id:attempt,evidence:[]} ]));
function target(v) {
  if(!v||!['local','external','legacy'].includes(v.kind))fail('invalid_target');
  const t={kind:v.kind,destination:text(v.destination,'destination',1200)};
  if(v.kind==='external'){t.account=text(v.account,'account',256);t.recipient=text(v.recipient,'recipient',512);}
  return t;
}
function sameTarget(a,b){if(canonical(target(a))!==canonical(target(b)))fail('wrong_target');}
function contentHash(v){if(typeof v!=='string'||!/^[a-f0-9]{64}$/.test(v))fail('invalid_content_hash');return v;}
function ownership(r,a) {
  if(r.legacy_compatibility && a.legacy===true)return;
  if(!r.owner || r.owner.token!==a.owner_token || r.owner.expires_at<Date.now())fail('owner_required');
  if(a.actor && r.owner.actor!==a.actor)fail('wrong_owner');
}
function recordProgress(r){r.updated_at=now();r.last_progress_at=Date.now();r.recovery=null;}
function newRoot(a) {
  const intent=text(a.intent||a.title,'intent',16000), rid=id(a.root_id);
  const d={id:'default',title:text(a.title||intent,'title'),target:target(a.target||{kind:'local',destination:rid}),attempt_id:uuid(),expected_content_sha256:a.content_sha256?contentHash(a.content_sha256):sha(''),requirements:null,history:[]};d.stages=freshStages(d.attempt_id);
  return {id:rid,title:d.title,intent,intent_sha256:sha(intent),intent_revision:1,corrections:[],created_at:now(),updated_at:now(),last_progress_at:Date.now(),owner:null,deliverables:{default:d},failures:[],recovery:null,legacy_compatibility:a.legacy===true,historical_complete:false};
}
function evidenceCurrent(root,e) {
  if(sha(Buffer.from(e.bytes_base64,'base64'))!==e.sha256) return false;
  try {const file=confined(root,path.join(root,e.path));return sha(fs.readFileSync(file))===e.sha256;}catch{return false;}
}
export function readiness(root,r) {
  const details=Object.values(r.deliverables).map(d=>{
    const requirements=requirementReadiness(r,d);
    const stages=localContentCurrent(root,d)&&STAGES.every(k=>{
      const s=d.stages[k];return s.status==='validated' && s.attempt_id===d.attempt_id && s.content_sha256===d.expected_content_sha256 && s.intent_revision===r.intent_revision && (r.legacy_compatibility || s.build_sha256===buildDigest(root)) && s.evidence.length>0 && s.evidence.every(e=>different(e.producer_id,s.validator_id||'') && evidenceCurrent(root,e));
    });
    return {id:d.id,complete:stages&&requirements.ready,requirements};
  });
  return {complete:details.length>0&&details.every(d=>d.complete),historical_complete:r.historical_complete,deliverables:details,limitation:'Local record consistency and independent reviewer labels do not authenticate reviewers or independently prove external state.'};
}
function invalidate(r,d){d.history.push({attempt_id:d.attempt_id,stages:d.stages,requirements:d.requirements,content_sha256:d.expected_content_sha256});d.attempt_id=uuid();d.stages=freshStages(d.attempt_id);r.historical_complete=false;}
function localContentCurrent(root,d){if(d.target.kind!=='local')return true;try{const p=confined(root,path.resolve(root,d.target.destination));return sha(fs.readFileSync(p))===d.expected_content_sha256;}catch{return false;}}
function validateObservation(root,d,stage,a) {
  if(STAGES.indexOf(stage)<2)return;
  if(d.target.kind==='local'&&!localContentCurrent(root,d))fail('local_target_content_mismatch');
  if(d.target.kind!=='external')return;
  const o=a.observation;if(!o||o.kind!==stage||o.persisted!==true||o.unique!==true||o.failure!==false||o.attribution!==false)fail('external_observation_required');
  sameTarget(d.target,o.target);
  if(o.content_sha256!==d.expected_content_sha256)fail('wrong_observed_content');
  const stamp=Date.parse(o.observed_at);
  if(!Number.isFinite(stamp)||stamp>Date.now()+30000||Date.now()-stamp>300000)fail('stale_observation');
}
function importLegacy(root,s) {
  const dir=path.join(root,'state/objectives');if(!fs.existsSync(dir))return [];
  confined(root,dir,{directory:true});const imported=[];
  for(const name of fs.readdirSync(dir).sort()){
    id(name);if(s.legacy_imports[name])continue;
    if(s.roots[name])fail('legacy_root_conflict');
    const base=confined(root,path.join(dir,name),{directory:true});
    const read=(rel,optional=false)=>{const p=path.join(base,rel);if(optional&&!fs.existsSync(p))return null;confined(root,p);if(fs.statSync(p).size>16384)fail('legacy_field_too_large');return fs.readFileSync(p,'utf8').trim();};
    if(fs.existsSync(path.join(base,'.lock')))fail('legacy_objective_locked');
    const r=newRoot({root_id:name,title:read('title'),legacy:true,target:{kind:'legacy',destination:name}});const d=r.deliverables.default;
    let chain=true;const hashes=[];
    for(const stage of STAGES){
      const state=read(`stages/${stage}/state`);if(!['pending','reported','validated'].includes(state))fail('invalid_legacy_stage');
      if(state==='pending'){chain=false;continue;}
      const p=path.join(base,'evidence',stage,'evidence.bin');const e=evidence(root,p),expected=read(`stages/${stage}/evidence_sha256`),producer=actor(read(`stages/${stage}/producer`));
      if(e.sha256!==expected)fail('legacy_evidence_mismatch');
      const validator=read(`stages/${stage}/validator`,true);if(state==='validated'&&(!chain||!validator||!different(producer,validator)))fail('legacy_validation_invalid');
      if(state!=='validated')chain=false;
      d.stages[stage]={status:state,attempt_id:d.attempt_id,intent_revision:r.intent_revision,content_sha256:d.expected_content_sha256,evidence:[{...e,evidence_id:uuid(),producer_id:producer}],validator_id:validator,validated_at:read(`stages/${stage}/validated_at`,true)};hashes.push(expected);
    }
    const legacyState=read('state');if(!['active','complete'].includes(legacyState))fail('invalid_legacy_state');
    if(legacyState==='complete'&&!chain)fail('legacy_completion_invalid');
    r.historical_complete=legacyState==='complete';r.legacy_imported_at=now();s.roots[name]=r;s.legacy_imports[name]={source_path:path.relative(root,base),evidence_digest:hashValue(hashes),imported_at:now()};imported.push(name);
  }
  return imported;
}
const ROOT_MUTATIONS=new Set(['deliverable-add','claim','checkpoint','requirements','correct','content','evidence-add','review','failure','recover','retry']);
const READ_ACTIONS=new Set(['read','status','orphans','memory-list','queue-list','outbox-list','issue-list','capabilities','context','proof-check','export']);
export function execute(root,action,a={}){
  root=validateRoot(root);text(action,'action',60);
  if(!a||typeof a!=='object'||Array.isArray(a))fail('invalid_input');
  if(action==='recover-lock')return recoverLock(root);
  const apply=s=>{
    let r;if(ROOT_MUTATIONS.has(action)){r=rootOf(s,a);if(action!=='claim'&&action!=='review')ownership(r,a);}
    switch(action){
      case 'capabilities':return {state_schema:2,node_minimum:22,local_core:'supported-and-verified',native_project:'manual',goals:'manual',voice:'manual',computer_use:'manual',connectors:'manual',native_schedules:'manual',terminal_hooks:'unavailable',note:'Native capabilities require actual app-specific discovery. This CLI does not control apps, run a model, send messages, or intercept assistant responses.'};
      case 'read':case 'status':return a.root_id?{root:rootOf(s,a),readiness:readiness(root,rootOf(s,a)),store_revision:s.revision}:{schema:s.schema,revision:s.revision,roots:Object.values(s.roots).map(r=>({id:r.id,title:r.title,owner:r.owner?{actor:r.owner.actor,expires_at:r.owner.expires_at}:null,...readiness(root,r)})),memory_count:Object.keys(s.memory).length,issue_count:Object.keys(s.issues).length,last_tick:s.last_tick};
      case 'export':return {schema:2,exported_at:now(),root:structuredClone(rootOf(s,a)),note:'User data. Keep this export private.'};
      case 'legacy-import':return {imported:importLegacy(root,s)};
      case 'root-create':{
        direct(a);const key=id(a.root_id);if(s.roots[key])fail('root_exists');s.roots[key]=newRoot(a);return s.roots[key];}
      case 'deliverable-add':{
        const key=id(a.deliverable_id);if(r.deliverables[key])fail('deliverable_exists');const d=newRoot({...a,root_id:r.id}).deliverables.default;d.id=key;r.deliverables[key]=d;recordProgress(r);return d;}
      case 'claim':{
        const who=actor(a.actor);const ttl=a.lease_ms??300000;if(!Number.isSafeInteger(ttl)||ttl<1000||ttl>3600000)fail('invalid_lease');
        if(r.owner&&r.owner.expires_at>Date.now()){
          if(r.owner.actor!==who||r.owner.token!==a.owner_token)fail('already_owned');
          r.owner.expires_at=Date.now()+ttl;return r.owner;
        }
        r.owner={actor:who,token:uuid(),expires_at:Date.now()+ttl};return r.owner;}
      case 'checkpoint':r.checkpoint={summary:text(a.summary,'summary'),next_action:text(a.next_action,'next action'),owner:r.owner?.actor||actor(a.actor),at:now()};recordProgress(r);return r.checkpoint;
      case 'requirements':{const d=deliverableOf(r,a),prior=d.requirements?.digest,next=reviseRequirements(d.requirements,a.items,r);if(prior!==next.digest){if(STAGES.some(k=>d.stages[k].status!=='pending'))invalidate(r,d);d.requirements=next;recordProgress(r);}return d.requirements;}
      case 'correct':{
        direct(a);const intent=text(a.intent,'intent',16000);if(sha(intent)===r.intent_sha256)return {unchanged:true};
        r.corrections.push({revision:r.intent_revision,intent_sha256:r.intent_sha256,correction:text(a.reason||'User revised the requested outcome'),at:now()});r.intent=intent;r.intent_sha256=sha(intent);r.intent_revision++;
        for(const d of Object.values(r.deliverables))invalidate(r,d);recordProgress(r);return {intent_revision:r.intent_revision};}
      case 'retry':{const d=deliverableOf(r,a),reason=text(a.reason,'retry reason');if(r.recovery?.requires_new_hypothesis){const hypothesis=text(a.hypothesis,'new hypothesis');if(hypothesis===r.recovery.last_hypothesis)fail('unchanged_hypothesis');}invalidate(r,d);d.retry_reason=reason;recordProgress(r);return {attempt_id:d.attempt_id,reason};}
      case 'content':{const d=deliverableOf(r,a),h=contentHash(a.content_sha256);if(h!==d.expected_content_sha256){invalidate(r,d);d.expected_content_sha256=h;}if(a.target){sameTarget(d.target,a.target);}recordProgress(r);return {attempt_id:d.attempt_id,content_sha256:h};}
      case 'evidence-add':{
        const d=deliverableOf(r,a),stage=a.stage,idx=STAGES.indexOf(stage);if(idx<0)fail('invalid_stage');
        if(a.attempt_id!==d.attempt_id)fail('stale_attempt');if(a.content_sha256!==d.expected_content_sha256)fail('stale_content');sameTarget(d.target,a.target);
        const st=d.stages[stage];if(st.status!=='pending')fail('stage_not_pending');if(idx>0&&d.stages[STAGES[idx-1]].status!=='validated')fail('prior_stage_required');
        validateObservation(root,d,stage,a);
        const e={...evidence(root,a.file),evidence_id:uuid(),producer_id:actor(a.actor),observation:a.observation||null};
        Object.assign(st,{status:'reported',attempt_id:d.attempt_id,intent_revision:r.intent_revision,content_sha256:d.expected_content_sha256,target:d.target,evidence:[e],reported_at:now()});recordProgress(r);return {evidence_id:e.evidence_id,sha256:e.sha256};}
      case 'review':{
        const d=deliverableOf(r,a),st=d.stages[a.stage];if(!st||st.status!=='reported')fail('stage_not_reported');
        const who=actor(a.validator);if(a.attempt_id!==d.attempt_id||st.intent_revision!==r.intent_revision||a.content_sha256!==d.expected_content_sha256)fail('stale_review');
        sameTarget(d.target,a.target);if(a.result!=='validated'&&a.result!=='rejected')fail('invalid_review');
        if(st.evidence.some(e=>!different(who,e.producer_id)||!evidenceCurrent(root,e)))fail('invalid_review_evidence');
        if(a.result==='validated')validateObservation(root,d,a.stage,a);
        st.status=a.result;st.validator_id=who;st.validated_at=now();st.review_reason=text(a.reason,'review reason');st.build_sha256=buildDigest(root);
        if(d.requirements)d.requirements=reviewRequirements(d.requirements,r,d,st,{...a,validator_id:who,requirement_digest:a.requirement_digest});recordProgress(r);return readiness(root,r);}
      case 'failure':{
        const signature=hashValue([text(a.code,'failure code'),text(a.condition,'failure condition')]);const previous=r.failures.at(-1),repeat=previous?.signature===signature?(previous.repeat+1):1;
        const failure={signature,repeat,code:a.code,condition:a.condition,at:now()};r.failures.push(failure);r.failures=r.failures.slice(-32);r.recovery={needed:true,requires_new_hypothesis:repeat>=2,last_failure:failure,last_hypothesis:r.recovery?.last_hypothesis||null};return r.recovery;}
      case 'recover':{
        if(r.recovery?.requires_new_hypothesis){const hypothesis=text(a.hypothesis,'new hypothesis');if(hypothesis===r.recovery.last_hypothesis)fail('unchanged_hypothesis');r.recovery.last_hypothesis=hypothesis;}
        r.recovery={needed:false,last_hypothesis:a.hypothesis||null,recovered_at:now()};return r.recovery;}
      case 'tick':{
        const at=Date.now();for(const r of Object.values(s.roots)){if(readiness(root,r).complete||r.historical_complete)continue;if(at-r.last_progress_at>=600000)r.recovery={...(r.recovery||{}),needed:true,reason:'no_valid_progress_for_600_seconds'};}
        for(const q of Object.values(s.queue).concat(Object.values(s.outbox))){if(q.state==='claimed'&&q.claim.expires_at<at){q.state='pending';q.claim=null;}if(q.state==='dispatched'&&q.claim.expires_at<at)q.state='uncertain';}
        updateOrphanHistory(s,root);s.last_tick=now();return {heartbeat:s.last_tick,orphans:orphanView(s,root)};}
      case 'orphans':return orphanView(s,root);
      case 'settings':direct(a);try{new Intl.DateTimeFormat('en',{timeZone:a.time_zone}).format();}catch{fail('invalid_time_zone');}s.time_zone=text(a.time_zone,'time zone',80);return {time_zone:s.time_zone};
      case 'memory-put':{
        direct(a);const key=id(a.id),zone=a.zone;if(!ZONES.includes(zone))fail('invalid_zone');if(!RETENTION.includes(a.retention))fail('invalid_retention');if(!RETENTION.slice(0,3).includes(a.retention))fail('retention_not_promotable');
        const assignment=id(a.assignment),source=text(a.provenance,'provenance',1200),value=text(a.value,'memory value',8000),prior=s.memory[key];
        if(prior&&prior.assignment!==assignment)fail('memory_assignment_conflict');if(prior&&prior.zone!==zone)fail('memory_zone_conflict');
        if(prior&&prior.value===value&&prior.provenance===source)return {unchanged:true,id:key};
        if(prior&&a.supersedes_revision!==prior.revision)fail('memory_supersession_required');
        s.memory[key]={id:key,zone,assignment,value,provenance:source,retention:a.retention,revision:(prior?.revision||0)+1,updated_at:now(),history:prior?[...(prior.history||[]),{revision:prior.revision,value:prior.value,provenance:prior.provenance}]:[]};return {id:key,revision:s.memory[key].revision};}
      case 'memory-list':{
        const assignment=id(a.assignment);if(!ZONES.includes(a.zone)||a.authorized_scope!==true)fail('memory_scope_required');
        return Object.values(s.memory).filter(m=>m.zone===a.zone&&(m.assignment===assignment||a.cross_assignment_authorized===true));}
      case 'session-record':{
        direct(a);const key=id(a.id),assignment=id(a.assignment);if(!RETENTION.includes(a.retention))fail('invalid_retention');
        const row={id:key,assignment,retention:a.retention,summary:text(a.summary,'concise session summary',2000),provenance:text(a.provenance,'provenance',1200),memory_ids:a.memory_ids||[]};
        for(const mid of row.memory_ids){const m=s.memory[id(mid)];if(!m||m.assignment!==assignment)fail('session_assignment_conflict');}
        if(s.sessions[key]&&canonical(s.sessions[key])!==canonical(row))fail('session_id_conflict');s.sessions[key]=row;return row;}
      case 'issue-record':{
        const key=id(a.id),prior=s.issues[key],who=actor(a.actor);if(!['P0','P1','P2','P3'].includes(a.severity))fail('invalid_severity');
        const row={id:key,title:text(a.title),severity:a.severity,symptoms:text(a.symptoms),reproduction:text(a.reproduction),root_cause:text(a.root_cause),remediation:text(a.remediation),owner:who,status:'open',discovered_at:prior?.discovered_at||now(),affected_systems:a.affected_systems||['local workflow'],verification_criteria:text(a.verification_criteria||'Independent evidence demonstrates the repaired behavior.'),updated_at:now(),evidence:prior?.evidence||[],history:prior?[...(prior.history||[]),prior.status]:[]};if(prior){if(prior.owner!==who)fail('wrong_issue_owner');const fields=['title','severity','symptoms','reproduction','root_cause','remediation','affected_systems','verification_criteria'];if(fields.some(k=>canonical(prior[k])!==canonical(row[k])))fail('issue_id_conflict');return prior;}s.issues[key]=row;return row;}
      case 'issue-list':return Object.values(s.issues);
      case 'issue-update':{const issue=s.issues[id(a.id)]||fail('unknown_issue');if(issue.owner!==actor(a.actor))fail('wrong_issue_owner');if(!['open','investigating','remediation_in_progress','blocked','resolved'].includes(a.status))fail('invalid_issue_status');issue.status=a.status;issue.updated_at=now();issue.next_action=text(a.next_action);return issue;}
      case 'issue-verify':{
        const issue=s.issues[id(a.id)]||fail('unknown_issue');const who=actor(a.validator);if(!different(who,issue.owner))fail('independent_validator_required');if(a.result!=='passed')fail('issue_verification_failed');
        issue.evidence.push({...evidence(root,a.file),validator:who,reason:text(a.reason)});issue.status='verified';issue.updated_at=now();return issue;}
      case 'queue-enqueue':case 'outbox-enqueue':{
        direct(a);const box=action.startsWith('queue')?s.queue:s.outbox,key=id(a.id),rr=rootOf(s,a);let dest=target(a.target);
        if(action.startsWith('outbox')){if(!s.notification)fail('notification_not_configured');sameTarget(s.notification,dest);if(!readiness(root,rr).complete&&!rr.historical_complete)fail('root_not_terminal');}
        const payload=text(a.payload,'payload',12000),fingerprint=hashValue([rr.id,dest,payload]);
        if(box[key]){if(box[key].fingerprint!==fingerprint)fail('handoff_id_conflict');return box[key];}
        const duplicate=Object.values(box).find(q=>q.fingerprint===fingerprint);if(duplicate)return duplicate;
        box[key]={id:key,root_id:rr.id,target:dest,payload,payload_sha256:sha(payload),fingerprint,state:'pending',created_at:now(),claim:null};return box[key];}
      case 'notification-configure':direct(a);s.notification=a.target?target(a.target):null;return {configured:Boolean(s.notification)};
      case 'queue-claim':case 'outbox-claim':{
        const box=action.startsWith('queue')?s.queue:s.outbox,q=box[id(a.id)]||fail('unknown_handoff');if(q.state!=='pending')fail('handoff_not_pending');
        q.claim={actor:actor(a.actor),token:uuid(),expires_at:Date.now()+300000};q.state='claimed';return q;}
      case 'queue-transition':case 'outbox-transition':{
        const box=action.startsWith('queue')?s.queue:s.outbox,q=box[id(a.id)]||fail('unknown_handoff');sameTarget(q.target,a.target);if(q.payload_sha256!==a.payload_sha256)fail('wrong_payload');
        if(a.state==='dispatched'||a.state==='uncertain'){
          if(!q.claim||q.claim.token!==a.claim_token)fail('handoff_owner_required');
          if(a.state==='dispatched'&&(q.state!=='claimed'||q.claim.expires_at<Date.now()))fail('handoff_not_claimed');
          if(a.state==='uncertain'&&!['claimed','dispatched'].includes(q.state))fail('invalid_handoff_transition');q.state=a.state;return q;
        }
        if(!['dispatched','uncertain'].includes(q.state))fail('handoff_not_reconcilable');
        if(!different(actor(a.validator),q.claim.actor))fail('independent_validator_required');
        const e=evidence(root,a.file);const observed=Date.parse(a.observed_at);if(!Number.isFinite(observed)||Date.now()-observed>300000||observed>Date.now()+30000)fail('stale_observation');
        if(a.state==='verified'){if(a.unique!==true||a.persisted!==true||a.failure!==false||a.attribution!==false)fail('invalid_readback');}
        else if(a.state==='pending'){if(a.confirmed_no_action!==true)fail('no_action_proof_required');}
        else fail('invalid_handoff_transition');
        q.reconciliation={...e,validator:a.validator,observed_at:a.observed_at};q.state=a.state;if(a.state==='pending')q.claim=null;return q;}
      case 'queue-archive':case 'outbox-archive':{const q=(action.startsWith('queue')?s.queue:s.outbox)[id(a.id)]||fail('unknown_handoff');if(q.state!=='verified'||!q.reconciliation)fail('unverified_handoff');q.state='archived';return q;}
      case 'queue-list':return Object.values(s.queue);
      case 'outbox-list':return Object.values(s.outbox);
      case 'context':{
        const p=confined(root,a.file);if(fs.statSync(p).size>256000)fail('context_too_large');return compileTaskContext({taskPath:p,taskBody:fs.readFileSync(p,'utf8'),phase:a.phase,maxCapsuleUtf8Bytes:a.max_bytes??8192});}
      case 'proof-record':{
        const rr=rootOf(s,a),d=deliverableOf(rr,a);ownership(rr,a);if(!['research_complete','draft_complete'].includes(a.stage))fail('external_proof_reuse_forbidden');
        const st=d.stages[a.stage];if(!localContentCurrent(root,d)||st.status!=='validated'||st.attempt_id!==d.attempt_id||st.intent_revision!==rr.intent_revision||st.content_sha256!==d.expected_content_sha256||st.build_sha256!==buildDigest(root)||!st.evidence.every(e=>evidenceCurrent(root,e)))fail('proof_not_validated');
        d.proofs||={};d.proofs[a.stage]={stage:a.stage,intent_sha256:rr.intent_sha256,attempt_id:d.attempt_id,content_sha256:d.expected_content_sha256,build_sha256:buildDigest(root),evidence:structuredClone(st.evidence),validator_id:st.validator_id};return d.proofs[a.stage];}
      case 'proof-check':{
        const rr=rootOf(s,a),d=deliverableOf(rr,a),p=d.proofs?.[a.stage];if(!p)return {reusable:false};
        return {reusable:localContentCurrent(root,d)&&p.intent_sha256===rr.intent_sha256&&p.attempt_id===d.attempt_id&&p.content_sha256===d.expected_content_sha256&&p.build_sha256===buildDigest(root)&&d.stages[a.stage]?.status==='validated'&&d.stages[a.stage].attempt_id===p.attempt_id&&d.stages[a.stage].intent_revision===rr.intent_revision&&d.stages[a.stage].content_sha256===p.content_sha256&&d.stages[a.stage].build_sha256===p.build_sha256&&d.stages[a.stage].validator_id===p.validator_id&&canonical(d.stages[a.stage].evidence)===canonical(p.evidence)&&p.evidence.every(e=>evidenceCurrent(root,e))};}
      default:fail('unknown_action');
    }
  };
  return READ_ACTIONS.has(action)?apply(readStore(root)):mutate(root,apply,a);
}
function activeOrphans(s,root){return Object.values(s.roots).filter(r=>!r.historical_complete&&!readiness(root,r).complete&&(!r.owner||r.owner.expires_at<Date.now()||r.recovery?.needed));}
function dayKey(s){return new Intl.DateTimeFormat('en-CA',{timeZone:s.time_zone||'UTC',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date());}
function updateOrphanHistory(s,root){s.orphan_history||={};const day=dayKey(s),active=activeOrphans(s,root);for(const r of active){const old=s.orphan_history[r.id];if(!old||old.active===false)s.orphan_history[r.id]={first_seen:day,last_seen:day,consecutive_stuck_days:1,monitoring_gap:true,active:true};else if(old.last_seen!==day){const delta=Math.round((Date.parse(day)-Date.parse(old.last_seen))/86400000);old.consecutive_stuck_days=delta===1?old.consecutive_stuck_days+1:1;old.monitoring_gap||=delta!==1;old.last_seen=day;}}for(const [rid,h]of Object.entries(s.orphan_history)){if(!active.some(r=>r.id===rid))h.active=false;}}
function orphanView(s,root){const at=Date.now();return {last_tick:s.last_tick,time_zone:s.time_zone||'UTC',status:!s.last_tick?'unavailable':at-Date.parse(s.last_tick)>180000?'stale':'current',items:activeOrphans(s,root).map(r=>({root_id:r.id,reason:!r.owner?'missing_owner':r.owner.expires_at<at?'expired_owner':'stalled',consecutive_stuck_days:s.orphan_history?.[r.id]?.consecutive_stuck_days??null,history_gap:s.orphan_history?.[r.id]?.monitoring_gap??true,next_action:r.checkpoint?.next_action||'Claim the existing root and inspect current state before acting.'}))};}
function buildDigest(root){const dir=confined(root,path.join(root,'runtime/core'),{directory:true});return sha(fs.readdirSync(dir).filter(n=>n.endsWith('.mjs')).sort().map(n=>n+'\0'+sha(fs.readFileSync(confined(root,path.join(dir,n))))).join('\0'));}
