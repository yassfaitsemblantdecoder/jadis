import {searchSchools} from './directory.js';
import {installTimeline} from './timeline.js';
import {installCapsules} from './capsules.js';
import {betaConfig} from './beta-config.js';
const $ = selector => document.querySelector(selector);
let session = null, chosen = null;
const status = message => $('#status').textContent = message;

async function api(path, {method='GET', body, prefer, token=session?.access_token} = {}) {
  if (!betaConfig) throw Error('Cette version ne dispose pas d’une instance de bêta configurée.');
  const headers = {apikey:betaConfig.publishableKey, 'Content-Type':'application/json'};
  if (token) headers.Authorization = 'Bearer ' + token;
  if (prefer) headers.Prefer = prefer;
  const response = await fetch(betaConfig.url + path, {
    method, headers, body:body === undefined ? undefined : JSON.stringify(body),
  });
  if (!response.ok) throw Error('Requête refusée (' + response.status + '). Vérifie ton accès ou reconnecte-toi.');
  return response.status === 204 ? null : await response.json().catch(() => null);
}
function reset(){$('#invite').hidden=true;$('#invite').reset();$('#signup').hidden=true;$('#recover').hidden=true;$('#new-password').hidden=true;$('#toggle-recovery').hidden=false;$('#auth').hidden=false;$('#toggle-signup').hidden=false;session=null;chosen=null;$('#account-data').hidden=true;$('#account-removal').open=false;$('#delete-account').reset();timeline.reset();capsules.reset();$('#private-navigation').hidden=true;$('#private').hidden=true;$('#login').hidden=false;$('#journey').hidden=true;$('#entry').hidden=true;$('#profile').reset();clearConnections();$('#discovery').hidden=true;$('#matches').replaceChildren();$('#entries').replaceChildren();$('#beta-graph').replaceChildren();$('#results').replaceChildren();$('#query').value=''}
$('#auth').onsubmit=async e=>{e.preventDefault();const d=new FormData(e.target);try{reset();session=await api('/auth/v1/token?grant_type=password',{method:'POST',body:{email:d.get('email'),password:d.get('password')}});e.target.reset();await enterBeta()}catch(err){reset();status(err.message)}};
$('#logout').onclick=async()=>{try{await api('/auth/v1/logout',{method:'POST'})}catch{}finally{reset();status('Déconnecté.')}};
$('#profile').onsubmit=async e=>{e.preventDefault();try{await api('/rest/v1/profiles?on_conflict=id',{method:'POST',body:{id:session.user.id,display_name:new FormData(e.target).get('name').trim(),discoverable:e.target.elements.discoverable.checked},prefer:'resolution=merge-duplicates,return=minimal'});$('#journey').hidden=false;$('#private-navigation').hidden=false;$('#reconnections').hidden=false;$('#discovery').hidden=!e.target.elements.discoverable.checked;$('#matches').replaceChildren();await load();await Promise.all([timeline.show(e.target.elements.discoverable.checked),capsules.show()]);status('Profil enregistré.')}catch(err){status(err.message)}};
let controller;$('#search-beta').onclick=async()=>{controller?.abort();controller=new AbortController();const signal=controller.signal;if(!betaConfig?.externalDirectory)return;chosen=null;$('#entry').hidden=true;$('#results').replaceChildren();try{const q=$('#query').value.trim();if(q.length<3){status('Saisis au moins trois caractères.');return}const {items,failed}=await searchSchools(q,signal);if(signal.aborted||!session)return;for(const s of items){const b=document.createElement('button');b.textContent=s.name+' — '+s.city;b.onclick=()=>{chosen=s;$('#chosen').textContent=b.textContent;$('#entry').hidden=false};$('#results').append(b)}status(items.length+' résultat(s)'+(failed.length?' · certaines sources indisponibles':''))}catch(err){if(!signal.aborted)status('Recherche indisponible.')}};
$('#entry').onsubmit=async e=>{e.preventDefault();if(!chosen||!session)return;const d=new FormData(e.target);try{await api('/rest/v1/beta_school_entries',{method:'POST',body:{user_id:session.user.id,directory_id:chosen.id,school_name:chosen.name,city:chosen.city||'',year:Number(d.get('year')),level:String(d.get('level')).trim(),section:String(d.get('section')).trim().toUpperCase()},prefer:'return=minimal'});e.target.reset();$('#entry').hidden=true;chosen=null;await load();status('Parcours enregistré.')}catch(err){status(err.message)}};
async function load(){const rows=await api('/rest/v1/beta_school_entries?select=*&order=year.asc');const list=$('#entries'),graph=$('#beta-graph');list.replaceChildren();graph.replaceChildren();const ns='http://www.w3.org/2000/svg';function draw(tag,attrs,label){const n=document.createElementNS(ns,tag);for(const [k,v] of Object.entries(attrs))n.setAttribute(k,v);if(label)n.textContent=label;graph.append(n)}draw('circle',{cx:250,cy:200,r:24,fill:'var(--atlas-text)'});draw('text',{x:250,y:205,'text-anchor':'middle',fill:'var(--atlas)'},'Moi');const hubs=[...new Map(rows.map(r=>[r.directory_id,r])).values()];hubs.forEach((r,i)=>{const a=-Math.PI/2+i*2*Math.PI/hubs.length,x=250+140*Math.cos(a),y=200+140*Math.sin(a);draw('line',{x1:250,y1:200,x2:x,y2:y,stroke:'var(--graph-edge)'});draw('circle',{cx:x,cy:y,r:14,fill:'var(--graph-primary-school)'});draw('text',{x,y:y+26,'text-anchor':'middle',fill:'var(--atlas-text)','font-size':11},r.school_name.slice(0,28))});for(const r of rows){const article=document.createElement('article');article.textContent=r.school_name+' · '+r.year+'–'+(r.year+1)+' · '+r.level+' '+r.section;const b=document.createElement('button');b.textContent='Retirer';b.onclick=async()=>{try{await api('/rest/v1/beta_school_entries?id=eq.'+encodeURIComponent(r.id),{method:'DELETE'});await load()}catch(err){status(err.message)}};article.append(document.createElement('br'),b);list.append(article)}}

$('#discover').onclick=async()=>{const box=$('#matches');box.replaceChildren();try{const rows=await api('/rest/v1/rpc/beta_discover',{method:'POST',body:{}});if(!session)return;if(!rows.length){box.textContent='Pas encore de correspondance. Ta constellation grandira avec les inscriptions.';return}for(const r of rows){const a=document.createElement('article');a.textContent=r.display_name+' · '+r.school_name+' · '+r.school_year+' · '+r.match_type;for(const [label,action] of [['Se reconnecter',async()=>{await reconnect('request',{target:r.person_id});status('Demande traitée. Consulte tes retrouvailles.');await loadConnections()}],['Bloquer',async()=>{await api('/rest/v1/blocks',{method:'POST',body:{owner:session.user.id,target:r.person_id},prefer:'return=minimal'});a.remove()}],['Signaler',async()=>{const reason=prompt('Motif du signalement (sans données sensibles)');if(!reason?.trim())return;await api('/rest/v1/reports',{method:'POST',body:{reporter:session.user.id,target:r.person_id,reason:reason.trim().slice(0,2000)},prefer:'return=minimal'});status('Signalement transmis.')} ]]){const b=document.createElement('button');b.textContent=label;b.onclick=async()=>{try{await action()}catch(err){status(err.message)}};a.append(document.createElement('br'),b)}box.append(a)}}catch(err){status(err.message)}};

let activeThread=null, activePeer=null, socialEpoch=0;
const reconnect=(action,params={})=>api('/rest/v1/rpc/beta_reconnect',{method:'POST',body:{action,...params}});
function clearConnections(){socialEpoch++;activeThread=null;activePeer=null;$('#reconnections').hidden=true;$('#connections').replaceChildren();$('#messages').replaceChildren();$('#conversation').hidden=true;$('#send-message').reset()}
function socialButton(parent,label,action){const b=document.createElement('button');b.type='button';b.textContent=label;b.onclick=async()=>{b.disabled=true;try{await action()}catch(e){status(e.message)}finally{b.disabled=false}};parent.append(b)}
async function loadConnections(){const epoch=socialEpoch;const rows=await reconnect('list');if(epoch!==socialEpoch||!session)return;const box=$('#connections');box.replaceChildren();if(!rows.length)box.textContent='Tes futures retrouvailles apparaîtront ici.';for(const r of rows){const a=document.createElement('article');a.textContent=r.display_name+' · '+({accepted:'Reconnectés',declined:'Demande refusée',pending:r.outgoing?'Demande envoyée':'Invitation reçue'}[r.status]);if(r.status==='pending'&&!r.outgoing){for(const [label,action] of [['Accepter','accept'],['Refuser','decline']])socialButton(a,label,async()=>{await reconnect(action,{thread:r.id});await loadConnections()})}if(r.status==='accepted')socialButton(a,'Ouvrir la conversation',async()=>{activeThread=r.id;activePeer=r.person_id;$('#conversation-title').textContent=r.display_name;$('#conversation').hidden=false;await loadMessages()});socialButton(a,'Bloquer',async()=>{await api('/rest/v1/blocks',{method:'POST',body:{owner:session.user.id,target:r.person_id},prefer:'return=minimal'});closeConversation();await loadConnections()});box.append(a)}}
function closeConversation(){activeThread=null;activePeer=null;$('#conversation').hidden=true;$('#messages').replaceChildren();$('#send-message').reset()}
async function loadMessages(){const thread=activeThread,epoch=socialEpoch;if(!thread)return;try{const rows=await reconnect('messages',{thread});if(epoch!==socialEpoch||thread!==activeThread)return;const box=$('#messages');box.replaceChildren();for(const r of rows){const a=document.createElement('article');const name=document.createElement('strong');name.textContent=r.outgoing?'Moi':'Mon contact';const body=document.createElement('p');body.style.whiteSpace='pre-wrap';body.textContent=r.body;a.append(name,body);box.append(a)}}catch(e){closeConversation();throw e}}
$('#refresh-connections').onclick=()=>loadConnections().catch(e=>status(e.message));
$('#refresh-messages').onclick=()=>loadMessages().catch(e=>status(e.message));
$('#close-conversation').onclick=closeConversation;
$('#report-conversation').onclick=()=>{
  if (activePeer) reportPerson(activePeer).catch(error=>status(error.message));
};
$('#send-message').onsubmit=async e=>{e.preventDefault();const thread=activeThread,epoch=socialEpoch;if(!thread)return;const b=e.target.querySelector('button');b.disabled=true;try{await reconnect('send',{thread,content:new FormData(e.target).get('body')});if(epoch===socialEpoch&&activeThread===thread){e.target.reset();await loadMessages()}}catch(err){status(err.message)}finally{b.disabled=false}};

async function enterBeta(){$('#account-data').hidden=false;const members=await api('/rest/v1/beta_members?select=user_id');if(!members?.length){$('#invite').hidden=false;$('#auth').hidden=true;$('#signup').hidden=true;$('#toggle-signup').hidden=true;$('#toggle-recovery').hidden=true;$('#recover').hidden=true;status('Entre ton code d’invitation pour activer la bêta.');return}$('#invite').hidden=true;const p=await api('/rest/v1/profiles?select=display_name,discoverable');$('#private').hidden=false;$('#login').hidden=true;if(p.length){$('#profile input').value=p[0].display_name;$('#profile [name=discoverable]').checked=p[0].discoverable;$('#discovery').hidden=!p[0].discoverable;$('#journey').hidden=false;$('#private-navigation').hidden=false;$('#reconnections').hidden=false;await load();await Promise.all([timeline.show(p[0].discoverable),capsules.show()])}status('Connecté à la bêta privée.')}
$('#toggle-signup').onclick=()=>{$('#signup').hidden=!$('#signup').hidden;$('#toggle-signup').textContent=$('#signup').hidden?'Créer un compte':'Annuler l’inscription'};
$('#signup').onsubmit=async e=>{e.preventDefault();const d=new FormData(e.target),button=e.target.querySelector('button');button.disabled=true;try{await api('/auth/v1/signup',{method:'POST',body:{email:d.get('email'),password:d.get('password')}});e.target.reset();e.target.hidden=true;$('#toggle-signup').textContent='Créer un compte';status('Vérifie ta boîte mail, confirme ton adresse puis reviens ici pour te connecter.')}catch(err){status(err.message)}finally{button.disabled=false}};
$('#invite').onsubmit=async e=>{e.preventDefault();const d=new FormData(e.target),button=e.target.querySelector('button');button.disabled=true;try{const ok=await api('/rest/v1/rpc/beta_redeem_invite',{method:'POST',body:{code:d.get('code'),adult:d.get('adult')==='on'}});if(!ok){status('Code invalide, expiré, utilisé ou trop de tentatives. Vérifie aussi ton email.');return}e.target.reset();await enterBeta()}catch(err){status(err.message)}finally{button.disabled=false}};
$('#cancel-invite').onclick=()=>$('#logout').click();

async function reportPerson(personId) {
  const reason = prompt('Motif du signalement (sans données sensibles)');
  if (!reason?.trim()) return;
  await api('/rest/v1/reports', {method:'POST',body:{reporter:session.user.id,target:personId,reason:reason.trim().slice(0,2000)},prefer:'return=minimal'});
  status('Signalement transmis.');
}

const capsules = installCapsules({ api, status, connections: () => reconnect('list'), report: reportPerson });
const timeline = installTimeline({
  api,
  status,
  onEntries: rows => capsules.setEntries(rows),
  async reconnect(personId) {
    await reconnect('request', {target: personId});
    status('Demande traitée. Consulte tes retrouvailles.');
    await loadConnections();
  },
  block(personId) {
    return api('/rest/v1/blocks', {method:'POST', body:{owner:session.user.id,target:personId}, prefer:'return=minimal'});
  },
  report: reportPerson,
});

let recoveryToken = null;
$('#toggle-recovery').onclick = () => {
  $('#recover').hidden = !$('#recover').hidden;
  if (!$('#recover').hidden) $('#recover input').focus();
};
$('#recover').onsubmit = async event => {
  event.preventDefault();
  const form = event.target;
  const submit = form.querySelector('button');
  submit.disabled = true;
  try {
    const redirect = new URL('./beta.html', window.location.href);
    await api('/auth/v1/recover?redirect_to=' + encodeURIComponent(redirect.href), {
      method: 'POST', body: {email: form.elements.email.value},
    });
    form.reset();
    form.hidden = true;
    status('Si un compte correspond, un email de récupération va être envoyé.');
  } catch (error) {
    status(error.message);
  } finally {
    submit.disabled = false;
  }
};
$('#new-password').onsubmit = async event => {
  event.preventDefault();
  const form = event.target;
  const submit = form.querySelector('button');
  if (!recoveryToken) return;
  submit.disabled = true;
  try {
    await api('/auth/v1/user', {
      method: 'PUT', token: recoveryToken, body: {password: form.elements.password.value},
    });
    recoveryToken = null;
    form.reset();
    reset();
    status('Mot de passe mis à jour. Tu peux te reconnecter.');
    $('#auth input').focus();
  } catch (error) {
    status(error.message);
  } finally {
    submit.disabled = false;
  }
};
function readAuthCallback() {
  const params = new URLSearchParams(window.location.hash.slice(1));
  if (!params.has('access_token') && !params.has('error_code')) return;
  history.replaceState(null, '', window.location.pathname + window.location.search);
  if (!betaConfig || params.get('type') !== 'recovery' || !params.has('access_token')) return;
  reset();
  recoveryToken = params.get('access_token');
  $('#auth').hidden = true;
  $('#toggle-signup').hidden = true;
  $('#toggle-recovery').hidden = true;
  $('#new-password').hidden = false;
}
if (betaConfig) {
  $('#auth').hidden = false;
  $('#toggle-signup').hidden = false;
  $('#toggle-recovery').hidden = false;
  $('#beta-instructions').hidden = false;
  $('#beta-directory').hidden = !betaConfig.externalDirectory;
} else {
  status('La bêta n’est pas configurée sur ce site. La démo reste disponible.');
}
window.addEventListener('hashchange', readAuthCallback);
readAuthCallback();

$('#download-data').onclick = async event => {
  const button = event.target;
  const activeSession = session;
  button.disabled = true;
  try {
    const data = await api('/rest/v1/rpc/beta_account_data', {method:'POST', body:{action:'export'}});
    if (activeSession !== session) return;
    const file = new Blob([JSON.stringify(data, null, 2)], {type:'application/json'});
    const link = document.createElement('a');
    link.href = URL.createObjectURL(file);
    link.download = 'mes-donnees-jadis.json';
    document.body.append(link);
    link.click();
    link.remove();
    setTimeout(() => URL.revokeObjectURL(link.href), 0);
  } catch (error) {
    if (activeSession === session) status(error.message);
  } finally {
    button.disabled = false;
  }
};

$('#delete-account').onsubmit = async event => {
  event.preventDefault();
  const form = event.target;
  const activeSession = session;
  if (!activeSession?.user?.email || form.elements.confirmation.value !== 'SUPPRIMER') return;
  const button = form.querySelector('button');
  button.disabled = true;
  try {
    const proof = await api('/auth/v1/token?grant_type=password', {
      method:'POST', token:null, body:{email:activeSession.user.email,password:form.elements.password.value},
    });
    if (activeSession !== session || proof?.user?.id !== activeSession.user.id) return;
    const result = await api('/rest/v1/rpc/beta_account_data', {
      method:'POST', token:proof.access_token, body:{action:'delete',confirm:true},
    });
    if (!result?.deleted) throw Error('La suppression du compte n’a pas été confirmée.');
    if (activeSession === session) {
      reset();
      status('Compte supprimé.');
    }
  } catch (error) {
    if (activeSession === session) status(error.message);
  } finally {
    form.elements.password.value = '';
    button.disabled = false;
  }
};
