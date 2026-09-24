#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {execute,STAGES} from './core.mjs';
import {fail,sha} from './store.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
export const ACTIONS=['read','status','capabilities','heartbeat','root-create','deliverable-add','claim','checkpoint','requirements','correct','content','evidence-add','review','failure','recover','retry','tick','orphans','settings','legacy-import','memory-put','memory-list','session-record','issue-record','issue-update','issue-list','issue-verify','notification-configure','queue-enqueue','queue-claim','queue-transition','queue-archive','queue-list','outbox-enqueue','outbox-claim','outbox-transition','outbox-archive','outbox-list','context','proof-record','proof-check','export','recover-lock'];
function readInput(){const chunks=[];let size=0;while(true){const b=Buffer.alloc(16384),n=fs.readSync(0,b,0,b.length,null);if(!n)break;size+=n;if(size>1024*1024)fail('input_too_large');chunks.push(b.subarray(0,n));}const bytes=Buffer.concat(chunks);return bytes.length?JSON.parse(bytes.toString('utf8')):{};}
function legacy(cmd,args){
  if(cmd==='objective-status'){
    // Import is an explicit write. Status never silently migrates an old store.
    if(!fs.existsSync(path.join(root,'state/core.json'))&&fs.existsSync(path.join(root,'state/objectives'))){
      return {migration_required:true,next_command:'autoassist core legacy-import',note:'Legacy objective files are preserved. Import before advancing them.'};
    }
    return execute(root,'status',args[0]?{root_id:args[0]}:{});
  }
  execute(root,'legacy-import');
  if(cmd==='objective-create')return execute(root,'root-create',{root_id:args[0],title:args[1],intent:args[1],source:'direct_user',legacy:true,target:{kind:'legacy',destination:args[0]}});
  if(cmd==='supervisor-tick')return execute(root,'tick');
  const [rid,stage]=args,r=execute(root,'read',{root_id:rid}).root,d=r.deliverables.default;
  if(!r.legacy_compatibility)fail('advanced_root_requires_core_commands');
  if(cmd==='checkpoint')return execute(root,'evidence-add',{root_id:rid,stage,file:path.resolve(args[2]),actor:args[3],legacy:true,attempt_id:d.attempt_id,content_sha256:d.expected_content_sha256,target:d.target});
  if(cmd==='validate-stage')return execute(root,'review',{root_id:rid,stage,validator:args[2],attempt_id:d.attempt_id,content_sha256:d.expected_content_sha256,target:d.target,result:'validated',reason:'Legacy CLI review. Reviewer label separation and evidence integrity only; external persistence requires separate native readback.'});
  fail('unknown_legacy_command');
}
try {
  const [mode,...args]=process.argv.slice(2);let result;
  if(mode==='--help'||mode==='help'||!mode){result={usage:'autoassist core ACTION < request.json',actions:ACTIONS,stages:STAGES,state:'state/core.json',privacy:'All supplied state is private local user data. Do not publish exports.',limitations:'Reviewer/source labels are claimed provenance, not authentication. Native action and terminal hooks are not installed.'};}
  else if(mode==='legacy'){if(!args[0])fail('missing_command');result=legacy(args[0],args.slice(1));}
  else {if(args.length||!ACTIONS.includes(mode))fail('unknown_action');result=execute(root,mode,readInput());}
  process.stdout.write(JSON.stringify({ok:true,result})+'\n');
}catch(e){process.stderr.write(JSON.stringify({ok:false,error:e.code||'invalid_request'})+'\n');process.exitCode=1;}
