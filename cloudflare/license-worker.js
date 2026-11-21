const WEB='https://globalkey-zszhp4ii.manus.space';
const TRY='https://trystoreapi-ygszmmh4.manus.space';
const HYP='https://hyperapi-kifrqq7j.manus.space';
const SUPPORTED_STORE_PROJECTS=new Set(['trystore','apple-music','me-store']);
const J=(d,s=200)=>new Response(JSON.stringify(d),{status:s,headers:{'content-type':'application/json','cache-control':'no-store','x-content-type-options':'nosniff','x-frame-options':'DENY','referrer-policy':'no-referrer'}});
const secretMatches=(supplied,expected)=>{if(!expected)return false;const a=String(supplied??'');if(a.length!==expected.length)return false;let d=0;for(let i=0;i<expected.length;i+=1)d|=a.charCodeAt(i)^expected.charCodeAt(i);return d===0};
const safeEqual=(a,b)=>{const x=String(a??''),y=String(b??'');if(x.length!==y.length)return false;let d=0;for(let i=0;i<x.length;i+=1)d|=x.charCodeAt(i)^y.charCodeAt(i);return d===0};
const owner=(e,id)=>String(e.TELEGRAM_OWNER_ID||'')===String(id);
const now=()=>Math.floor(Date.now()/1000);
async function mac(e,text){const k=await crypto.subtle.importKey('raw',new TextEncoder().encode(e.LICENSE_SIGNING_SECRET),{name:'HMAC',hash:'SHA-256'},false,['sign']);const b=await crypto.subtle.sign('HMAC',k,new TextEncoder().encode(text));return Array.from(new Uint8Array(b),x=>x.toString(16).padStart(2,'0')).join('')}
async function tg(e,m,b){if(m==='sendMessage'&&b&&typeof b.text==='string'&&!b.parse_mode)b.parse_mode='HTML';return fetch('https://api.telegram.org/bot'+e.TELEGRAM_BOT_TOKEN+'/'+m,{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify(b)})}
async function hash(e,key){return mac(e,key.trim().toUpperCase())}
function duration(v){const d={1:86400,3:259200,7:604800,15:1296000,25:2160000,30:2592000,31:2678400,60:5184000,permanent:315360000};return d[v]||0}
async function makeKey(e,project,reseller,dur){const p=await e.DB.prepare("SELECT id,name,key_prefix FROM projects WHERE slug=?1 AND status='active'").bind(project).first();if(!p)return null;const raw=crypto.getRandomValues(new Uint8Array(18));const hex=Array.from(raw,x=>x.toString(16).padStart(2,'0')).join('').toUpperCase();const key=(p.key_prefix||'KEY')+'-'+hex.slice(0,6)+'-'+hex.slice(6,12)+'-'+hex.slice(12,18);const exp=dur==='permanent'?now()+315360000:now()+duration(dur);const h=await hash(e,key);const hint=key.replaceAll('-','').slice(-10);await e.DB.prepare("INSERT INTO global_keys(project_id,reseller_id,key_hash,key_hint,status,expires_at,max_devices,created_at,updated_at) VALUES (?1,?2,?3,?4,'active',?5,1,?6,?6)").bind(p.id,reseller,h,hint,exp,now()).run();return {key,hint,project:p.name,expiresAt:new Date(exp*1000).toISOString()}}
async function findKey(e,key){return e.DB.prepare("SELECT g.*,p.slug,p.name FROM global_keys g JOIN projects p ON p.id=g.project_id WHERE g.key_hash=?1 LIMIT 1").bind(await hash(e,key)).first()}
const SESSION_ISSUER='trystore-license';
const SESSION_AUDIENCE='trystore-feed';
const SESSION_KID='trystore-ed25519-v1';
const SESSION_TTL=900;
const TEXT=new TextEncoder();
function b64urlBytes(bytes){let s='';for(const b of new Uint8Array(bytes))s+=String.fromCharCode(b);return btoa(s).replaceAll('+','-').replaceAll('/','_').replace(/=+$/,'')}
function b64urlText(text){return b64urlBytes(TEXT.encode(text))}
async function ed25519Sign(e,bytes){
  const raw=String(e.SESSION_SIGNING_KEY||'').trim();
  if(!raw)return null;
  let der;
  try{der=Uint8Array.from(atob(raw),c=>c.charCodeAt(0))}catch{return null}
  try{
    const key=await crypto.subtle.importKey('pkcs8',der,{name:'Ed25519'},false,['sign']);
    return new Uint8Array(await crypto.subtle.sign({name:'Ed25519'},key,bytes));
  }catch{
    try{
      const key=await crypto.subtle.importKey('pkcs8',der,{name:'NODE-ED25519',namedCurve:'NODE-ED25519'},false,['sign']);
      return new Uint8Array(await crypto.subtle.sign('NODE-ED25519',key,bytes));
    }catch{return null}
  }
}
async function mintSession(e,g,device){
  const exp=Math.min(Number(g.expires_at)||now()+SESSION_TTL,now()+SESSION_TTL);
  const claims={v:1,iss:SESSION_ISSUER,aud:SESSION_AUDIENCE,kid:SESSION_KID,project:g.slug,keyId:Number(g.id),keyHint:String(g.key_hint||''),device,nonce:crypto.randomUUID().replaceAll('-',''),iat:now(),exp};
  const payload=b64urlText(JSON.stringify(claims));
  const signature=await ed25519Sign(e,TEXT.encode(payload));
  return signature?payload+'.'+b64urlBytes(signature):null;
}
const SIGNAL_WINDOW = 3600;
async function sha256Hex(text){
  const digest=await crypto.subtle.digest('SHA-256',new TextEncoder().encode(text));
  return Array.from(new Uint8Array(digest),x=>x.toString(16).padStart(2,'0')).join('');
}
async function alertOwner(e,text){
  try{
    const chat=String(e.ALERT_CHAT_ID||e.TELEGRAM_OWNER_ID||'');
    if(!chat||!e.TELEGRAM_BOT_TOKEN)return;
    await tg(e,'sendMessage',{chat_id:chat,text,disable_web_page_preview:true});
  }catch{}
}
async function noteNetwork(e,g,ip){
  const bucket=await sha256Hex(String(e.LICENSE_SIGNING_SECRET||'')+'|'+ip);
  const window=Math.floor(now()/SIGNAL_WINDOW);
  await e.DB.prepare("INSERT INTO license_signals(key_id,ip_bucket,window_start,last_seen) VALUES(?1,?2,?3,?4) ON CONFLICT(key_id,ip_bucket,window_start) DO UPDATE SET last_seen=excluded.last_seen").bind(g.id,bucket,window,now()).run();
  const row=await e.DB.prepare("SELECT COUNT(*) AS n FROM license_signals WHERE key_id=?1 AND window_start>=?2").bind(g.id,window-1).first();
  const limit=Number(e.MAX_DISTINCT_IPS||0);
  if(!(limit>=2))return false;
  if(Number(row?.n||0)<=limit)return false;
  const updated=await e.DB.prepare("UPDATE global_keys SET status='frozen',updated_at=?1 WHERE id=?2 AND status='active'").bind(now(),g.id).run();
  if(Number(updated?.meta?.changes||0)>0){
    await alertOwner(e,'🔒 Key '+String(g.key_hint||g.id)+' frozen: '+Number(row.n)+' distinct networks in one hour.');
  }
  return true;
}
async function tryValidate(r,e){const original=r.clone();let b;try{b=await r.json()}catch{return {valid:false,outcome:'invalid_request',expiresAt:null}};const device=String(b.deviceId||'').trim();if(!UUID_RE.test(device))return {valid:false,outcome:'invalid_device',expiresAt:null};const g=await findKey(e,String(b.key||''));if(!g)return {legacy:original};if(g.status==='revoked'||g.status==='frozen'||g.expires_at<=now())return {valid:false,outcome:g.status==='active'?'expired':g.status,expiresAt:new Date(g.expires_at*1000).toISOString()};if(!SUPPORTED_STORE_PROJECTS.has(g.slug))return {valid:false,outcome:'wrong_project',expiresAt:null};if(String(e.ENFORCE_DEVICE_BINDING??'1')!=='0'&&!(await bindDevice(e,g,device)))return {valid:false,outcome:'device_limit',expiresAt:null};if(await noteNetwork(e,g,clientIP(r)))return {valid:false,outcome:'frozen',expiresAt:null};const requestedProject=String(b.projectId||'').trim().toLowerCase();if(requestedProject&&g.slug!==requestedProject)return {valid:false,outcome:'wrong_project',expiresAt:null};const session=await mintSession(e,g,device);if(!session)return {valid:false,outcome:'session_unavailable',expiresAt:null};return {valid:true,outcome:'active',expiresAt:new Date(g.expires_at*1000).toISOString(),session,keyHint:String(g.key_hint||'')}}
async function patchBundleKey(r,e){const original=r.clone();let b;try{b=await r.json()}catch{return J({error:'invalid_request'},400)}const key=String(b.key||'').trim(),device=String(b.deviceId||''),project=String(b.projectId||'').trim().toLowerCase();if(!key||!device||!['trystore','apple-music'].includes(project))return J({valid:false,outcome:'invalid'},403);let authorized=false,expiresAt=null;const g=await findKey(e,key);if(g){if(g.slug!==project)return J({valid:false,outcome:'wrong_project',expiresAt:null},403);if(g.status!=='active'||g.expires_at<=now())return J({valid:false,outcome:g.status==='active'?'expired':g.status,expiresAt:new Date(g.expires_at*1000).toISOString()},403);if(!(await bindDevice(e,g,device)))return J({valid:false,outcome:'device_limit'},403);authorized=true;expiresAt=new Date(g.expires_at*1000).toISOString()}else{if(project==='apple-music')return J({valid:false,outcome:'invalid'},403);const validation=await tryValidate(original,e);const response=validation?.legacy?await fwd(validation.legacy,TRY,'/api/v1/keys/validate'):J(validation);if(!response.ok)return J({valid:false,outcome:'invalid'},403);let v;try{v=await response.json()}catch{return J({valid:false,outcome:'invalid'},403)}authorized=v.valid===true&&String(v.outcome||'').toLowerCase()==='active'&&(!v.expiresAt||Date.parse(v.expiresAt)>Date.now());expiresAt=v.expiresAt||null}if(!authorized)return J({valid:false,outcome:'inactive'},403);const requestedKeyVersion=String(b.keyVersion||'1');const keyVersion=project==='trystore'?requestedKeyVersion:'1';if(!['1','2'].includes(keyVersion))return J({error:'unsupported_key_version'},400);const secretName=project==='apple-music'?'APPLE_MUSIC_PATCH_BUNDLE_ENCRYPTION_KEY':keyVersion==='1'?'PATCH_BUNDLE_ENCRYPTION_KEY':keyVersion==='2'?'PATCH_BUNDLE_ENCRYPTION_KEY_V2':'';if(!secretName)return J({error:'unsupported_key_version'},400);const bundleKey=String(e[secretName]||'');let bytes;try{bytes=Uint8Array.from(atob(bundleKey),c=>c.charCodeAt(0))}catch{return J({error:'key_unavailable'},503)}if(bytes.length!==32)return J({error:'key_unavailable'},503);return J({valid:true,key:bundleKey,keyVersion,expiresAt})}
async function resolveLicense(r,e){let b;try{b=await r.json()}catch{return J({error:'invalid_request'},400)}const key=String(b.key||'').trim();if(!key||key.length>256)return J({error:'invalid_request'},400);const g=await findKey(e,key);if(!g)return J({valid:false,outcome:'invalid',expiresAt:null});const expired=g.status==='active'&&g.expires_at<=now();return J({valid:g.status==='active'&&!expired,outcome:expired?'expired':g.status,keyId:g.id,expiresAt:new Date(g.expires_at*1000).toISOString(),maxDevices:Number(g.max_devices||0),createdAt:new Date(g.created_at*1000).toISOString(),updatedAt:new Date(g.updated_at*1000).toISOString(),project:g.slug})}
async function sessionToken(e,g,device,target){const p=JSON.stringify({id:g.id,device,target,exp:Math.min(g.expires_at,now()+900)});const x=btoa(p).replaceAll('=','');return x+'.'+(await mac(e,x))}
async function hyperActivate(r,e){const original=r.clone();const b=await r.json(),g=await findKey(e,String(b.key||''));if(!g)return fwd(original,HYP,'/api/license/activate');if(g.slug!=='hyper-regedit'||g.status!=='active'||g.expires_at<=now())return {error:{reason:g.status==='active'?'expired':g.status,message:'License is not active'}};return {licenseToken:await sessionToken(e,g,String(b.deviceId||''),String(b.target||'hyper-regedit')),expiresAt:new Date(g.expires_at*1000).toISOString(),target:'hyper-regedit'}}
async function hyperHeartbeat(r,e){const original=r.clone();const b=await r.json();try{const [x,s]=String(b.licenseToken||'').split('.');if(!x||!safeEqual(s,await mac(e,x)))return null;const p=JSON.parse(atob(x));const g=await e.DB.prepare('SELECT * FROM global_keys WHERE id=?1').bind(p.id).first();if(!g||g.status!=='active'||g.expires_at<=now())return {active:false,expiresAt:new Date((g?.expires_at||now())*1000).toISOString()};return {active:true,expiresAt:new Date(g.expires_at*1000).toISOString()}}catch{return null}}
async function save(e,c,a,state,p){await e.DB.prepare("INSERT INTO bot_sessions(chat_id,actor_id,state,payload,updated_at) VALUES (?1,?2,?3,?4,?5) ON CONFLICT(chat_id) DO UPDATE SET state=excluded.state,payload=excluded.payload,updated_at=excluded.updated_at").bind(String(c),String(a),state,JSON.stringify(p||{}),now()).run()}
async function get(e,c){return e.DB.prepare('SELECT state,payload FROM bot_sessions WHERE chat_id=?1').bind(String(c)).first()}
const OWNER_KB=[[{text:'Crear key',callback_data:'owner:create'},{text:'Estado',callback_data:'owner:status'}],[{text:'Revendedores',callback_data:'owner:add'},{text:'Proyectos',callback_data:'owner:projects'}],[{text:'Mensualidades',callback_data:'owner:subs'},{text:'Revocar key',callback_data:'owner:revoke'}],[{text:'Congelar key',callback_data:'owner:freeze'},{text:'Descongelar key',callback_data:'owner:unfreeze'}],[{text:'Congelar todas',callback_data:'owner:freezeall'},{text:'Descongelar todas',callback_data:'owner:unfreezeall'}]]
const RESELLER_KB=[[{text:'Mis proyectos',callback_data:'reseller:projects'},{text:'Congeladas',callback_data:'reseller:frozen'}],[{text:'Congelar key',callback_data:'reseller:freeze'},{text:'Descongelar key',callback_data:'reseller:unfreeze'}],[{text:'Revocar key',callback_data:'reseller:revoke'}]]
const STATUS_ES={active:'activa',frozen:'congelada',revoked:'revocada'}
const say=(e,chat,text,kb)=>tg(e,'sendMessage',{chat_id:chat,text,parse_mode:'HTML',disable_web_page_preview:true,...(kb?{reply_markup:{inline_keyboard:kb}}:{})})
const esc=(v)=>String(v??'').replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;')
const fmtDate=(ts)=>{const d=new Date(Number(ts)*1000);return Number.isFinite(d.getTime())?d.toISOString().slice(0,10):'—'}
const MONTHS_ES=['Enero','Febrero','Marzo','Abril','Mayo','Junio','Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre']
const ownerPanel=async(e,chat)=>{const r=await statusReport(e);await say(e,chat,'<b>3105</b>\n<i>Panel de control</i>\n\nActivas       <code>'+(r.active||0)+'</code>\nCongeladas    <code>'+(r.frozen||0)+'</code>\nRevocadas     <code>'+(r.revoked||0)+'</code>',OWNER_KB)}
const resellerPanel=async(e,chat)=>{await say(e,chat,'<b>3105</b>\n<i>Panel de revendedor</i>\n\nGenera, congela o revoca tus keys.',RESELLER_KB)}
async function setKeyStatus(e,g,target){
const cur=String(g.status||'active')
if(cur===target)return {ok:false,reason:'same'}
if(target==='active'&&cur==='revoked')return {ok:false,reason:'revoked'}
if(target==='active'&&Number(g.expires_at||0)<=now())return {ok:false,reason:'expired'}
await e.DB.prepare('UPDATE global_keys SET status=?1,updated_at=?2 WHERE id=?3').bind(target,now(),g.id).run()
return {ok:true,from:cur}
}
async function resellerKey(e,key,telegramId){
const g=await findKey(e,key)
if(!g)return {error:'missing'}
const r=await e.DB.prepare("SELECT id FROM resellers WHERE id=?1 AND telegram_id=?2 AND status='active'").bind(g.reseller_id,telegramId).first()
if(!r)return {error:'foreign'}
return {key:g}
}
async function statusReport(e){
const rows=await e.DB.prepare('SELECT status,COUNT(*) AS n FROM global_keys GROUP BY status').all()
const out={}
for(const row of (rows.results||[]))out[row.status]=Number(row.n)
return out
}
async function reportStatus(e,c,keyHint,target,res){
const label=STATUS_ES[target]||target
let text
if(res.ok)text='<b>'+keyHint+'</b>\nAhora está '+label
else if(res.reason==='same')text='<b>'+keyHint+'</b>\nYa estaba '+label
else if(res.reason==='revoked')text='<b>'+keyHint+'</b>\nUna key revocada no se puede reactivar'
else if(res.reason==='expired')text='<b>'+keyHint+'</b>\nEsa key ya venció'
else text='<b>'+keyHint+'</b>\nNo se pudo cambiar'
await say(e,c,text)
}
async function webhook(r,e){if(!secretMatches(r.headers.get('X-Telegram-Bot-Api-Secret-Token'),e.TELEGRAM_WEBHOOK_SECRET))return J({error:'unauthorized'},401);const u=await r.json(),q=u.callback_query,m=u.message,id=String(q?q.from.id:m?.from?.id||''),c=String(q?q.message.chat.id:m?.chat?.id||'');const o=owner(e,id);if(q)await tg(e,'answerCallbackQuery',{callback_query_id:q.id,text:'Hecho'});if(q&&q.data==='owner:subs'&&o){
const rows=await e.DB.prepare("SELECT s.reseller_id,s.project_id,s.expires_at,s.paid_until,s.override_active,s.status,r.telegram_id,p.name FROM reseller_subscriptions s JOIN resellers r ON r.id=s.reseller_id JOIN projects p ON p.id=s.project_id ORDER BY s.status DESC,s.expires_at ASC").all()
const orphans=await e.DB.prepare("SELECT a.reseller_id,a.project_id,r.telegram_id,p.name FROM reseller_assignments a JOIN resellers r ON r.id=a.reseller_id JOIN projects p ON p.id=a.project_id LEFT JOIN reseller_subscriptions s ON s.reseller_id=a.reseller_id AND s.project_id=a.project_id WHERE s.reseller_id IS NULL AND a.status='active' ORDER BY r.telegram_id").all()
const kb=[]
let body='<b>Mensualidades</b>'
const live=(rows.results||[]).length
body+='\n<i>'+live+(live===1?' suscripción':' suscripciones')+'</i>\n'
for(const x of (rows.results||[])){
const state=x.override_active?'Override':x.status==='active'?'Activa':'Suspendida'
const when=x.override_active?'sin vencimiento':fmtDate(x.expires_at)
body+='\n<b>'+esc(x.telegram_id)+'</b> · '+esc(x.name)+'\n'+state+' · '+when+'\n'
kb.push([{text:esc(x.telegram_id)+' · '+esc(x.name),callback_data:'sub:menu:'+x.reseller_id+':'+x.project_id}])
}
for(const x of (orphans.results||[])){
body+='\n<b>'+esc(x.telegram_id)+'</b> · '+esc(x.name)+'\nSin mensualidad\n'
kb.push([{text:'Crear · '+esc(x.telegram_id)+' · '+esc(x.name),callback_data:'sub:add:'+x.reseller_id+':'+x.project_id}])
}
if(!kb.length)body+='\nSin mensualidades.'
kb.push([{text:'Panel',callback_data:'owner:help'}])
await say(e,c,body,kb)
return J({ok:true})
}
if(q&&q.data.startsWith('sub:add:')&&o){
const v=q.data.split(':'),rid=Number(v[2]),pid=Number(v[3])
if(!Number.isFinite(rid)||!Number.isFinite(pid))return J({ok:true})
const until=now()+2592000
await e.DB.prepare("INSERT INTO reseller_subscriptions(reseller_id,project_id,starts_at,expires_at,paid_until,override_active,status,updated_at) VALUES(?1,?2,?3,?4,?4,0,'active',?3) ON CONFLICT(reseller_id,project_id) DO UPDATE SET expires_at=excluded.expires_at,paid_until=excluded.paid_until,status='active',updated_at=excluded.updated_at").bind(rid,pid,now(),until).run()
await e.DB.prepare("UPDATE global_keys SET status='active',updated_at=?1 WHERE reseller_id=?2 AND project_id=?3 AND status='frozen' AND expires_at>?1").bind(now(),rid,pid).run()
await say(e,c,'<b>Mensualidad creada</b>\n\nVence    '+fmtDate(until),[[{text:'Mensualidades',callback_data:'owner:subs'},{text:'Panel',callback_data:'owner:help'}]])
return J({ok:true})
}
if(q&&q.data.startsWith('sub:menu:')&&o){
const v=q.data.split(':'),rid=Number(v[2]),pid=Number(v[3])
if(!Number.isFinite(rid)||!Number.isFinite(pid))return J({ok:true})
const s=await e.DB.prepare("SELECT s.*,r.telegram_id,p.name FROM reseller_subscriptions s JOIN resellers r ON r.id=s.reseller_id JOIN projects p ON p.id=s.project_id WHERE s.reseller_id=?1 AND s.project_id=?2").bind(rid,pid).first()
if(!s){
await say(e,c,'<b>Sin mensualidad</b>\nNo hay suscripción para ese revendedor y proyecto',[[{text:'Crear mensualidad',callback_data:'sub:add:'+rid+':'+pid}],[{text:'Mensualidades',callback_data:'owner:subs'}]])
return J({ok:true})
}
const head='<b>'+esc(s.telegram_id)+'</b> · '+esc(s.name)
const state=s.override_active?'Override':(s.status==='active'?'Activa':'Suspendida')
await say(e,c,head+'\n\nVence        '+fmtDate(s.expires_at)+'\nPagado       '+(s.paid_until?fmtDate(s.paid_until):'—')+'\nEstado       '+state,[
[{text:'+30 días',callback_data:'sub:hit:extend:'+rid+':'+pid},{text:'Días',callback_data:'sub:custom:'+rid+':'+pid}],
[{text:'Fecha',callback_data:'sub:month:'+rid+':'+pid},{text:s.override_active?'Override activo':'Override',callback_data:'sub:hit:override:'+rid+':'+pid}],
[{text:s.status==='active'?'Suspender':'Reactivar',callback_data:'sub:hit:'+(s.status==='active'?'pause':'resume')+':'+rid+':'+pid}],
[{text:'Mensualidades',callback_data:'owner:subs'},{text:'Panel',callback_data:'owner:help'}]
])
return J({ok:true})
}
if(q&&q.data.startsWith('sub:month:')&&o){
const v=q.data.split(':'),rid=Number(v[2]),pid=Number(v[3])
if(!Number.isFinite(rid)||!Number.isFinite(pid))return J({ok:true})
await e.DB.prepare('DELETE FROM bot_sessions WHERE chat_id=?1').bind(c).run()
const btns=MONTHS_ES.map((m,i)=>({text:m,callback_data:'submonth:'+rid+':'+pid+':'+(i+1)}))
const kb=[];for(let k=0;k<btns.length;k+=3)kb.push(btns.slice(k,k+3))
kb.push([{text:'Mensualidades',callback_data:'owner:subs'}])
await say(e,c,'<b>Fecha de vencimiento</b>\nSelecciona el mes',kb)
return J({ok:true})
}
if(q&&q.data.startsWith('submonth:')&&o){
const v=q.data.split(':'),rid=Number(v[1]),pid=Number(v[2]),mth=Number(v[3])
if(!Number.isFinite(rid)||!Number.isFinite(pid)||mth<1||mth>12)return J({ok:true})
const y=new Date().getUTCFullYear()
const days=new Date(Date.UTC(y,mth,0)).getUTCDate()
const nums=Array.from({length:days},(_,k)=>({text:String(k+1),callback_data:'subday:'+rid+':'+pid+':'+mth+':'+(k+1)}))
const rows=[];for(let k=0;k<nums.length;k+=7)rows.push(nums.slice(k,k+7))
rows.push([{text:'Mensualidades',callback_data:'owner:subs'}])
await say(e,c,'<b>Fecha de vencimiento</b>\n'+MONTHS_ES[mth-1]+' · selecciona el día',rows)
return J({ok:true})
}
if(q&&q.data.startsWith('subday:')&&o){
const v=q.data.split(':'),rid=Number(v[1]),pid=Number(v[2]),mth=Number(v[3]),day=Number(v[4])
const y=new Date().getUTCFullYear()
let ts=Date.UTC(y,mth-1,day,23,59,59)
if(new Date(ts).getUTCMonth()!==mth-1){await say(e,c,'Ese día no existe en el mes seleccionado');return J({ok:true})}
if(ts<=Date.now())ts=Date.UTC(y+1,mth-1,day,23,59,59)
await e.DB.prepare("UPDATE reseller_subscriptions SET paid_until=?1,expires_at=?1,status='active',updated_at=?2 WHERE reseller_id=?3 AND project_id=?4").bind(Math.floor(ts/1000),now(),rid,pid).run()
await e.DB.prepare("UPDATE global_keys SET status='active',updated_at=?1 WHERE reseller_id=?2 AND project_id=?3 AND status='frozen' AND expires_at>?1").bind(now(),rid,pid).run()
await e.DB.prepare('DELETE FROM bot_sessions WHERE chat_id=?1').bind(c).run()
await say(e,c,'<b>Vencimiento guardado</b>\n\n'+fmtDate(Math.floor(ts/1000)),[[{text:'Mensualidades',callback_data:'owner:subs'},{text:'Panel',callback_data:'owner:help'}]])
return J({ok:true})
}
if(q&&q.data.startsWith('sub:custom:')&&o){
const v=q.data.split(':'),rid=Number(v[2]),pid=Number(v[3])
await save(e,c,id,'sub_custom',{reseller_id:rid,project_id:pid})
await say(e,c,'<b>Días personalizados</b>\nEnvía un número entre 1 y 3650',[[{text:'Mensualidades',callback_data:'owner:subs'}]])
return J({ok:true})
}
if(q&&q.data.startsWith('sub:hit:')&&o){
const v=q.data.split(':'),action=v[2],rid=Number(v[3]),pid=Number(v[4])
if(!Number.isFinite(rid)||!Number.isFinite(pid))return J({ok:true})
const s=await e.DB.prepare('SELECT * FROM reseller_subscriptions WHERE reseller_id=?1 AND project_id=?2').bind(rid,pid).first()
if(!s){await say(e,c,'No hay mensualidad para ese revendedor',[[{text:'Mensualidades',callback_data:'owner:subs'}]]);return J({ok:true})}
const t=now()
if(action==='extend'){
const base=Math.max(t,Number(s.paid_until||0))
const until=base+2592000
await e.DB.prepare("UPDATE reseller_subscriptions SET paid_until=?1,expires_at=?1,status='active',updated_at=?2 WHERE reseller_id=?3 AND project_id=?4").bind(until,t,rid,pid).run()
await e.DB.prepare("UPDATE global_keys SET status='active',updated_at=?1 WHERE reseller_id=?2 AND project_id=?3 AND status='frozen' AND expires_at>?1").bind(t,rid,pid).run()
await say(e,c,'<b>Mensualidad extendida</b>\n\nVence    '+fmtDate(until),[[{text:'Mensualidades',callback_data:'owner:subs'}]])
}else if(action==='override'){
const on=Number(s.override_active)?0:1
await e.DB.prepare("UPDATE reseller_subscriptions SET override_active=?1,status='active',updated_at=?2 WHERE reseller_id=?3 AND project_id=?4").bind(on,t,rid,pid).run()
if(on)await e.DB.prepare("UPDATE global_keys SET status='active',updated_at=?1 WHERE reseller_id=?2 AND project_id=?3 AND status='frozen' AND expires_at>?1").bind(t,rid,pid).run()
await say(e,c,'<b>Override</b>\n\n'+(on?'Activo · la mensualidad ya no vence':'Desactivado'),[[{text:'Mensualidades',callback_data:'owner:subs'}]])
}else if(action==='pause'){
await e.DB.prepare("UPDATE reseller_subscriptions SET override_active=0,expires_at=?1,paid_until=NULL,status='suspended',updated_at=?1 WHERE reseller_id=?2 AND project_id=?3").bind(t,rid,pid).run()
await e.DB.prepare("UPDATE global_keys SET status='frozen',updated_at=?1 WHERE reseller_id=?2 AND project_id=?3 AND status='active'").bind(t,rid,pid).run()
await say(e,c,'<b>Mensualidad suspendida</b>\n\nKeys congeladas',[[{text:'Mensualidades',callback_data:'owner:subs'}]])
}else if(action==='resume'){
await e.DB.prepare("UPDATE reseller_subscriptions SET status='active',expires_at=?1,paid_until=?1,updated_at=?2 WHERE reseller_id=?3 AND project_id=?4").bind(t+2592000,t,rid,pid).run()
await e.DB.prepare("UPDATE global_keys SET status='active',updated_at=?1 WHERE reseller_id=?2 AND project_id=?3 AND status='frozen' AND expires_at>?1").bind(t,rid,pid).run()
await say(e,c,'<b>Mensualidad reactivada</b>\n\nVence    '+fmtDate(t+2592000),[[{text:'Mensualidades',callback_data:'owner:subs'}]])
}else{
await say(e,c,'Acción no reconocida',[[{text:'Mensualidades',callback_data:'owner:subs'}]])
}
return J({ok:true})
}
if(q&&q.data==='owner:help'&&o){await ownerPanel(e,c);return J({ok:true})}if(q&&q.data==='owner:create'&&o){const rows=await e.DB.prepare("SELECT name,slug,key_prefix FROM projects WHERE status='active' ORDER BY name").all();const kb=(rows.results||[]).map(p=>[{text:p.name+' · '+p.key_prefix,callback_data:'ogen:'+p.slug}]);await tg(e,'sendMessage',{chat_id:c,text:'<b>Crear key</b>\nElige el proyecto',reply_markup:{inline_keyboard:kb.length?kb:[[{text:'Sin proyectos activos',callback_data:'noop'}]]}});return J({ok:true})}
if(q&&q.data.startsWith('ogen:')&&o){await save(e,c,id,'ogen_duration',{slug:q.data.slice(5)});const ds=['1','3','7','15','25','30','31','60','permanent'].map(x=>({text:x==='permanent'?'Permanente':x+' días',callback_data:'odur:'+x}));await tg(e,'sendMessage',{chat_id:c,text:'<b>Generar key</b>\nElige la duración',reply_markup:{inline_keyboard:[ds.slice(0,3),ds.slice(3,6),ds.slice(6)]}});return J({ok:true})}
if(q&&q.data.startsWith('odur:')&&o){const st=await get(e,c);if(!st)return J({ok:true});const p=JSON.parse(st.payload||'{}');const slug=String(p.slug||'');if(!slug)return J({ok:true});const k=await makeKey(e,slug,null,q.data.slice(5));await e.DB.prepare('DELETE FROM bot_sessions WHERE chat_id=?1').bind(c).run();if(!k){await tg(e,'sendMessage',{chat_id:c,text:'Proyecto no encontrado'});return J({ok:true})}await say(e,c,'<b>Key generada</b>\n<code>'+esc(k.key)+'</code>\n\nProyecto    '+esc(k.project)+'\nExpira      '+esc(k.expiresAt.slice(0,10)),[[{text:'Copiar key',copy_text:{text:k.key}}],[{text:'Nueva key',callback_data:'owner:create'},{text:'Panel',callback_data:'owner:help'}]]);return J({ok:true})}
if(q&&q.data==='owner:freeze'&&o){await save(e,c,id,'owner_key',{action:'frozen'});await tg(e,'sendMessage',{chat_id:c,text:'<b>Congelar key</b>\nEnvía la key completa'});return J({ok:true})}
if(q&&q.data==='owner:unfreeze'&&o){await save(e,c,id,'owner_key',{action:'active'});await tg(e,'sendMessage',{chat_id:c,text:'<b>Descongelar key</b>\nEnvía la key completa'});return J({ok:true})}
if(q&&q.data==='owner:revoke'&&o){await save(e,c,id,'owner_key',{action:'revoked'});await tg(e,'sendMessage',{chat_id:c,text:'<b>Revocar key</b>\nEnvía la key completa'});return J({ok:true})}
if(q&&q.data==='owner:freezeall'&&o){const row=await e.DB.prepare("SELECT COUNT(*) AS n FROM global_keys WHERE status='active'").first();const n=Number(row?.n||0);await say(e,c,'<b>Congelar todas</b>\n<i>Se corta el acceso hasta que las descongeles</i>\n\nActivas    <code>'+n+'</code>',[[{text:'Congelar '+n,callback_data:'freezeall:yes'},{text:'Cancelar',callback_data:'freezeall:no'}]]);return J({ok:true})}
if(q&&q.data==='owner:unfreezeall'&&o){const row=await e.DB.prepare("SELECT COUNT(*) AS n FROM global_keys WHERE status='frozen' AND expires_at>?1").bind(now()).first();const n=Number(row?.n||0);await say(e,c,'<b>Descongelar todas</b>\n<i>Solo se reactivan las que no vencieron</i>\n\nCongeladas vigentes    <code>'+n+'</code>',[[{text:'Descongelar '+n,callback_data:'unfreezeall:yes'},{text:'Cancelar',callback_data:'freezeall:no'}]]);return J({ok:true})}
if(q&&q.data==='freezeall:yes'&&o){const res=await e.DB.prepare("UPDATE global_keys SET status='frozen',updated_at=?1 WHERE status='active'").bind(now()).run();await tg(e,'sendMessage',{chat_id:c,text:'<b>Congeladas</b>\n<code>'+Number(res?.meta?.changes||0)+'</code>'});return J({ok:true})}
if(q&&q.data==='unfreezeall:yes'&&o){const res=await e.DB.prepare("UPDATE global_keys SET status='active',updated_at=?1 WHERE status='frozen' AND expires_at>?1").bind(now()).run();await tg(e,'sendMessage',{chat_id:c,text:'<b>Descongeladas</b>\n<code>'+Number(res?.meta?.changes||0)+'</code>'});return J({ok:true})}
if(q&&q.data==='freezeall:no'){await tg(e,'sendMessage',{chat_id:c,text:'Cancelado.'});return J({ok:true})}
if(q&&q.data==='owner:status'&&o){const r=await statusReport(e);await tg(e,'sendMessage',{chat_id:c,text:'<b>Estado</b>\n\nActivas       <code>'+(r.active||0)+'</code>\nCongeladas    <code>'+(r.frozen||0)+'</code>\nRevocadas     <code>'+(r.revoked||0)+'</code>'});return J({ok:true})}
if(q&&q.data==='reseller:freeze'&&!o){await save(e,c,id,'reseller_key',{action:'frozen'});await tg(e,'sendMessage',{chat_id:c,text:'<b>Congelar key</b>\nEnvía la key'});return J({ok:true})}
if(q&&q.data==='reseller:unfreeze'&&!o){await save(e,c,id,'reseller_key',{action:'active'});await tg(e,'sendMessage',{chat_id:c,text:'<b>Descongelar key</b>\nEnvía la key'});return J({ok:true})}
if(q&&q.data==='reseller:frozen'&&!o){const rows=await e.DB.prepare("SELECT g.key_hint,g.expires_at FROM global_keys g JOIN resellers r ON r.id=g.reseller_id WHERE r.telegram_id=?1 AND g.status='frozen' ORDER BY g.updated_at DESC LIMIT 20").bind(id).all();const list=(rows.results||[]).map(x=>'<code>'+x.key_hint+'</code>  '+fmtDate(x.expires_at)).join('\n');await say(e,c,'<b>Congeladas</b>\n'+(list?'\n'+list:'\nSin keys congeladas'));return J({ok:true})}
if(q&&q.data==='owner:projects'&&o){const rows=await e.DB.prepare("SELECT name,key_prefix FROM projects WHERE status='active' ORDER BY name").all();await tg(e,'sendMessage',{chat_id:c,text:'<b>Proyectos</b>\n\n'+(rows.results||[]).map(x=>esc(x.name)+' · '+esc(x.key_prefix)).join('\n')});return J({ok:true})}if(q&&q.data==='owner:add'&&o){const rows=await e.DB.prepare("SELECT name,slug,key_prefix FROM projects WHERE status='active' ORDER BY name").all();const kb=(rows.results||[]).map(p=>[{text:p.name+' · '+p.key_prefix,callback_data:'assign:'+p.slug}]);await tg(e,'sendMessage',{chat_id:c,text:'<b>Agregar revendedor</b>\nElige el proyecto',reply_markup:{inline_keyboard:kb}});return J({ok:true})}if(q&&q.data.startsWith('assign:')&&o){await save(e,c,id,'assign_id',{slug:q.data.slice(7)});await tg(e,'sendMessage',{chat_id:c,text:'<b>Telegram ID</b>\nEnvía el ID numérico del revendedor'});return J({ok:true})}if(q&&q.data==='reseller:revoke'&&!o){await save(e,c,id,'reseller_key',{action:'revoked'});await tg(e,'sendMessage',{chat_id:c,text:'<b>Revocar key</b>\nEnvía la key completa'});return J({ok:true})}if(q&&q.data==='reseller:projects'&&!o){const rows=await e.DB.prepare("SELECT p.name,p.slug,a.key_prefix FROM reseller_assignments a JOIN resellers r ON r.id=a.reseller_id JOIN projects p ON p.id=a.project_id WHERE r.telegram_id=?1 AND a.status='active'").bind(id).all();const kb=(rows.results||[]).map(p=>[{text:'Generar · '+p.name+' · '+p.key_prefix,callback_data:'gen:'+p.slug}]);await tg(e,'sendMessage',{chat_id:c,text:'<b>Mis proyectos</b>\nElige un proyecto',reply_markup:{inline_keyboard:kb}});return J({ok:true})}if(q&&q.data.startsWith('gen:')&&!o){await save(e,c,id,'gen_duration',{slug:q.data.slice(4)});const ds=['1','3','7','15','25','30','31','60','permanent'].map(x=>({text:x==='permanent'?'Permanente':x+' días',callback_data:'dur:'+x}));await tg(e,'sendMessage',{chat_id:c,text:'<b>Generar key</b>\nElige la duración',reply_markup:{inline_keyboard:[ds.slice(0,3),ds.slice(3,6),ds.slice(6)]}});return J({ok:true})}if(q&&q.data.startsWith('dur:')&&!o){const s=await get(e,c);if(!s)return J({ok:true});const p=JSON.parse(s.payload||'{}');const rr=await e.DB.prepare("SELECT r.id FROM resellers r JOIN reseller_assignments a ON a.reseller_id=r.id JOIN projects p ON p.id=a.project_id WHERE r.telegram_id=?1 AND p.slug=?2 AND r.status='active' AND a.status='active'").bind(id,p.slug).first();if(!rr)return J({error:'forbidden'},403);const k=await makeKey(e,p.slug,rr.id,q.data.slice(4));if(!k)return J({error:'project_not_found'},404);await say(e,c,'<b>Key generada</b>\n<code>'+esc(k.key)+'</code>\n\nProyecto    '+esc(k.project)+'\nExpira      '+esc(k.expiresAt.slice(0,10)),[[{text:'Copiar key',copy_text:{text:k.key}}],[{text:'Mis proyectos',callback_data:'reseller:projects'}]]);return J({ok:true})}const stxt=String(m?.text||'').trim();if(m&&(stxt==='/start'||stxt.startsWith('/start '))){await e.DB.prepare('DELETE FROM bot_sessions WHERE chat_id=?1').bind(c).run();if(o){await ownerPanel(e,c)}else{await resellerPanel(e,c)}return J({ok:true})}if(m&&o){const st=await get(e,c);const p=st?JSON.parse(st.payload||'{}'):{};const t=String(m?.text||'').trim();if(!st){await ownerPanel(e,c);return J({ok:true})}if(st.state==='owner_key'){const g=await findKey(e,t);if(!g){await tg(e,'sendMessage',{chat_id:c,text:'Esa key no existe'})}else{const target=String(p.action||'');const res=await setKeyStatus(e,g,target);await reportStatus(e,c,g.key_hint,target,res)}await e.DB.prepare('DELETE FROM bot_sessions WHERE chat_id=?1').bind(c).run();return J({ok:true})}
if(st.state==='sub_custom'){const d=Number(t);if(!Number.isInteger(d)||d<1||d>3650){await tg(e,'sendMessage',{chat_id:c,text:'Envía un número entre 1 y 3650'});return J({ok:true})}const r=Number(p.reseller_id),i=Number(p.project_id),z=await e.DB.prepare('SELECT * FROM reseller_subscriptions WHERE reseller_id=?1 AND project_id=?2').bind(r,i).first();if(!z){await say(e,c,'<b>Sin mensualidad</b>\nCrea la mensualidad antes de extenderla',[[{text:'Mensualidades',callback_data:'owner:subs'}]]);await e.DB.prepare('DELETE FROM bot_sessions WHERE chat_id=?1').bind(c).run();return J({ok:true})}const u=Math.max(now(),Number(z.paid_until||0))+d*86400;await e.DB.prepare("UPDATE reseller_subscriptions SET paid_until=?1,expires_at=?1,status='active',updated_at=?2 WHERE reseller_id=?3 AND project_id=?4").bind(u,now(),r,i).run();await e.DB.prepare("UPDATE global_keys SET status='active',updated_at=?1 WHERE reseller_id=?2 AND project_id=?3 AND status='frozen'").bind(now(),r,i).run();await tg(e,'sendMessage',{chat_id:c,text:'<b>Mensualidad extendida</b>\n<code>'+d+' días</code>'});return J({ok:true})}if(st.state==='assign_id'){const v=t.split(/\s+/);if(v.length!==2){await tg(e,'sendMessage',{chat_id:c,text:'<b>Formato</b>\nID e iniciales · ejemplo <code>123456789 JV</code>'});return J({ok:true})}const pr=await e.DB.prepare("SELECT id,name FROM projects WHERE slug=?1 AND status='active'").bind(p.slug).first();if(!pr)return J({error:'project_not_found'},404);await e.DB.prepare("INSERT INTO resellers(telegram_id,display_name,role,status,created_at) VALUES (?1,?2,'reseller','active',?3) ON CONFLICT(telegram_id) DO UPDATE SET status='active'").bind(v[0],'Reseller '+v[0],now()).run();const rr=await e.DB.prepare('SELECT id FROM resellers WHERE telegram_id=?1').bind(v[0]).first();await e.DB.prepare("INSERT INTO reseller_assignments(reseller_id,project_id,key_prefix,created_at) VALUES (?1,?2,?3,?4) ON CONFLICT(reseller_id,project_id) DO UPDATE SET key_prefix=excluded.key_prefix,status='active'").bind(rr.id,pr.id,v[1].toUpperCase(),now()).run();await say(e,c,'<b>Revendedor añadido</b>\n\nID           <code>'+esc(v[0])+'</code>\nProyecto     '+esc(pr.name)+'\nIniciales    <code>'+esc(v[1].toUpperCase())+'</code>',[[{text:'Añadir otro',callback_data:'owner:add'}],[{text:'Panel',callback_data:'owner:help'}]]);return J({ok:true})}return J({ok:true})}
if(m&&!o){const st=await get(e,c);let target='';try{target=st?String(JSON.parse(st.payload||'{}').action||''):''}catch{target=''}if(!['revoked','frozen','active'].includes(target))target='';const key=String(m?.text||'').trim();if(key&&target){const found=await resellerKey(e,key,id);if(found.error==='missing'){await tg(e,'sendMessage',{chat_id:c,text:'Esa key no existe'})}else if(found.error==='foreign'){await tg(e,'sendMessage',{chat_id:c,text:'Solo puedes gestionar tus propias keys'})}else{const res=await setKeyStatus(e,found.key,target);await reportStatus(e,c,found.key.key_hint,target,res)}await e.DB.prepare('DELETE FROM bot_sessions WHERE chat_id=?1').bind(c).run();return J({ok:true})}await tg(e,'sendMessage',{chat_id:c,text:'<b>3105</b>\n<i>Panel de revendedor</i>\n\nGenera, congela o revoca tus keys.',reply_markup:{inline_keyboard:RESELLER_KB}});return J({ok:true})}return J({ok:true})}
async function fwd(r,base,path){const u=new URL(r.url),h=new Headers(r.headers);h.delete('host');return fetch(new Request(base+path+u.search,{method:r.method,headers:h,body:r.method==='GET'||r.method==='HEAD'?undefined:r.body,redirect:'follow'}))}
async function proxy(r,e){const u=new URL(r.url);if(u.pathname.includes('..'))return J({error:'invalid_path'},400);if(!(await allow(e,'proxy',clientIP(r),120,60)))return J({error:'rate_limited'},429);let p=u.pathname;if(p==='/panel'||p==='/panel/')p='/';else if(p.startsWith('/panel/'))p=p.slice(6)||'/';return fwd(r,WEB,p)}
async function subscriptionSweep(e){const rows=await e.DB.prepare("SELECT reseller_id,project_id FROM reseller_subscriptions WHERE override_active=0 AND (paid_until IS NULL OR paid_until<?1) AND status!='suspended'").bind(now()).all();for(const r of (rows.results||[])){await e.DB.prepare("UPDATE reseller_subscriptions SET status='suspended',updated_at=?1 WHERE reseller_id=?2 AND project_id=?3").bind(now(),r.reseller_id,r.project_id).run();await e.DB.prepare("UPDATE global_keys SET status='frozen',updated_at=?1 WHERE reseller_id=?2 AND project_id=?3 AND status='active'").bind(now(),r.reseller_id,r.project_id).run()}}

const UUID_RE=/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const clientIP=r=>String(r.headers.get('cf-connecting-ip')||'unknown');
async function allow(e,bucket,subject,limit,window){const w=Math.floor(now()/window);const row=await e.DB.prepare('SELECT count FROM api_rate_limits WHERE bucket=?1 AND subject=?2 AND window_start=?3').bind(bucket,subject,w).first();if(row&&Number(row.count)>=limit)return false;await e.DB.prepare('INSERT INTO api_rate_limits(bucket,subject,window_start,count) VALUES(?1,?2,?3,1) ON CONFLICT(bucket,subject,window_start) DO UPDATE SET count=count+1').bind(bucket,subject,w).run();return true}
async function bindDevice(e,g,device){if(!UUID_RE.test(String(device||'')))return false;const rows=await e.DB.prepare('SELECT device_id FROM license_devices WHERE key_id=?1').bind(g.id).all();const list=(rows.results||[]).map(x=>String(x.device_id));if(list.includes(device)){await e.DB.prepare('UPDATE license_devices SET last_seen=?1 WHERE key_id=?2 AND device_id=?3').bind(now(),g.id,device).run();return true}const max=Math.max(1,Number(g.max_devices)||1);if(list.length>=max)return false;await e.DB.prepare('INSERT INTO license_devices(key_id,device_id,first_seen,last_seen) VALUES(?1,?2,?3,?3) ON CONFLICT(key_id,device_id) DO UPDATE SET last_seen=excluded.last_seen').bind(g.id,device,now()).run();return true}
export default{async scheduled(ev,e){try{await subscriptionSweep(e)}catch{}},async fetch(r,e){try{const u=new URL(r.url);if(u.pathname==='/health')return J({status:'ok',service:'Global Key Control'});if(u.pathname==='/api/telegram/webhook'&&r.method==='POST')return webhook(r,e);if(u.pathname==='/api/v1/keys/resolve'&&r.method==='POST'){if(!(await allow(e,'resolve',clientIP(r),30,60)))return J({valid:false,outcome:'rate_limited'},429);return resolveLicense(r,e)}if(u.pathname==='/api/v1/keys/patch-bundle-key'&&r.method==='POST'){if(!(await allow(e,'bundle-key',clientIP(r),10,60)))return J({valid:false,outcome:'rate_limited'},429);return patchBundleKey(r,e)}if(u.pathname==='/api/v1/keys/validate'&&r.method==='POST'){if(!(await allow(e,'validate',clientIP(r),30,60)))return J({valid:false,outcome:'rate_limited'},429);const x=await tryValidate(r,e);return x?.legacy?fwd(x.legacy,TRY,u.pathname):J(x)}if(u.pathname==='/api/license/activate'&&r.method==='POST'){const x=await hyperActivate(r,e);return x?.legacy?fwd(x.legacy,HYP,u.pathname):J(x)}if(u.pathname==='/api/license/heartbeat'&&r.method==='POST'){const x=await hyperHeartbeat(r,e);return x?.legacy?fwd(x.legacy,HYP,u.pathname):J(x)}return proxy(r,e)}catch(x){return J({error:'server_error'},500)}}};
