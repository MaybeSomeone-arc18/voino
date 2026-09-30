import {makeNotes,exportText} from './notes.js';
import {toCards,safeCards,safeConnections} from './board.js';
import {safeShapes,drawShapes} from './draw.js';
import {speechSnapshot,stitchSpeech} from './speech.js';
// Raw GitHub Pages has no npm resolver. Load native SDKs only inside Capacitor.
const isNative = !!window.Capacitor?.isNativePlatform?.();
let NativeSpeechRecognition, Purchases, LOG_LEVEL;
const nativeReady = isNative ? Promise.all([import('@capacitor-community/speech-recognition'), import('@revenuecat/purchases-capacitor')]).then(([speech, purchases]) => { NativeSpeechRecognition=speech.SpeechRecognition; Purchases=purchases.Purchases; LOG_LEVEL=purchases.LOG_LEVEL; }) : Promise.resolve();

const $ = id => document.getElementById(id);
const WebSpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;

let webRecognition, recording = false, startedAt = 0, clock, beforeSession = '', listening = false;
let speechSessionId = 0;
let boardEdited=false, lastGeneratedSource="", stopTimer, stopping=false;
let retryTimer, networkRetries=0, networkRetryPending=false;
const recognitionFailure=(reason,retries,active)=>active&&reason==='network'&&retries<2?{retry:true,delay:750*(retries+1)}:{retry:false,delay:0};
const fields=['title','transcript','noteTitle','points','actions'];
// Guest sessions are deliberately ephemeral. Never restore another visitor's words
// from this browser, including drafts written by older versions of Voino.
try{localStorage.removeItem('voino-draft-v1')}catch{}
let cards=[];let connections=[];let shapes=[];let connectingFrom=null;let drawMode=null;
const save=()=>{};
const saveBoard=()=>{boardEdited=true};
function clearSession(){
 for(const k of fields)$(k).value='';
 cards=[];connections=[];shapes=[];connectingFrom=null;drawMode=null;boardEdited=false;lastGeneratedSource='';$('boardStatus').textContent='Stop listening or tap Make editable board to create your cards.';
 document.querySelectorAll('.drawTool').forEach(x=>x.classList.remove('selected'));
 $('board').classList.remove('drawing');renderBoard();
 $('timer').textContent='00:00';$('saveState').textContent='Guest session - not saved';error('');
}
function drawConnections(){const svg=$('connections');svg.replaceChildren();svg.setAttribute('viewBox',`0 0 ${$('board').scrollWidth} ${$('board').scrollHeight}`);for(const link of connections){const a=bounds(link.from),b=bounds(link.to);if(!a||!b)continue;const line=document.createElementNS('http://www.w3.org/2000/svg','line');for(const [k,v] of Object.entries({x1:a.x,y1:a.y,x2:b.x,y2:b.y}))line.setAttribute(k,v);line.setAttribute('stroke','#49705a');line.setAttribute('stroke-width','2.5');line.setAttribute('marker-end','url(#arrow)');svg.append(line)}if(connections.length){const defs=document.createElementNS('http://www.w3.org/2000/svg','defs');defs.innerHTML='<marker id="arrow" markerWidth="9" markerHeight="9" refX="8" refY="3" orient="auto"><path d="M0 0 L8 3 L0 6" fill="none" stroke="#49705a" stroke-width="1.5"/></marker>';svg.prepend(defs)}drawShapes($('shapes'),shapes);$('shapes').setAttribute('viewBox',`0 0 ${$('board').scrollWidth} ${$('board').scrollHeight}`)}
function bounds(id){const el=[...document.querySelectorAll('.card')].find(x=>x.dataset.id===id);if(!el)return null;const a=el.getBoundingClientRect(),b=$('board').getBoundingClientRect();return {x:a.left-b.left+$('board').scrollLeft+a.width/2,y:a.top-b.top+$('board').scrollTop+a.height/2}}
function renderBoard(){const b=$('board');b.querySelectorAll('.card').forEach(el=>el.remove());$('boardEmpty').hidden=cards.length>0;for(const card of cards){const el=document.createElement('article');el.className='card '+card.type+' '+(card.color||'mint');el.style.left=card.x+'px';el.style.top=card.y+'px';el.dataset.id=card.id;const bar=document.createElement('div');bar.className='cardbar';const move=document.createElement('button');move.className='move';move.type='button';move.setAttribute('aria-label','Move card with drag or arrow keys');move.textContent='⠿';const type=document.createElement('span');type.textContent=card.type==='action'?'TO DO':card.type==='point'?'KEY POINT':'MY IDEA';const color=document.createElement('button');color.className='color';color.type='button';color.setAttribute('aria-label','Change card color');color.title='Change card color';color.textContent='◐';color.addEventListener('click',()=>{const palette=['mint','sand','lavender','rose'];card.color=palette[(palette.indexOf(card.color||'mint')+1)%palette.length];el.classList.remove(...palette);el.classList.add(card.color);saveBoard()});const remove=document.createElement('button');remove.className='remove';remove.type='button';remove.setAttribute('aria-label','Delete card');remove.textContent='×';remove.addEventListener('click',()=>{cards=cards.filter(c=>c.id!==card.id);connections=connections.filter(c=>c.from!==card.id&&c.to!==card.id);renderBoard();saveBoard()});bar.append(move,type,color,remove);const content=document.createElement('div');content.contentEditable='true';content.className='cardtext';content.setAttribute('aria-label','Edit card text');content.textContent=card.text;content.addEventListener('input',()=>{card.text=content.textContent.slice(0,1400);saveBoard()});move.addEventListener('pointerdown',event=>{event.preventDefault();move.setPointerCapture(event.pointerId);const origin={x:event.clientX,y:event.clientY,left:card.x,top:card.y};const onMove=e=>{card.x=Math.max(0,origin.left+e.clientX-origin.x);card.y=Math.max(0,origin.top+e.clientY-origin.y);el.style.left=card.x+'px';el.style.top=card.y+'px';drawConnections()};move.addEventListener('pointermove',onMove);move.addEventListener('pointerup',()=>{move.removeEventListener('pointermove',onMove);saveBoard()},{once:true})});move.addEventListener('keydown',e=>{const delta={ArrowLeft:[-10,0],ArrowRight:[10,0],ArrowUp:[0,-10],ArrowDown:[0,10]}[e.key];if(delta){e.preventDefault();card.x=Math.max(0,card.x+delta[0]);card.y=Math.max(0,card.y+delta[1]);el.style.left=card.x+'px';el.style.top=card.y+'px';drawConnections();saveBoard()}});el.addEventListener('click',e=>{if(!connectingFrom||e.target.closest('button'))return;if(connectingFrom==='select'){connectingFrom=card.id;$('connectCards').textContent='Now click the second card';return}if(connectingFrom===card.id){connectingFrom=null;$('connectCards').textContent='Connect two cards';return}if(!connections.some(c=>c.from===connectingFrom&&c.to===card.id))connections.push({from:connectingFrom,to:card.id});connectingFrom=null;$('connectCards').textContent='Connect two cards';drawConnections();saveBoard()});el.append(bar,content);b.append(el)}layoutCards();drawConnections()}
function layoutCards(){if(window.innerWidth<=600)return;let y=26;for(let i=0;i<cards.length;i+=2){let height=0;for(const c of cards.slice(i,i+2)){const el=[...document.querySelectorAll('.card')].find(x=>x.dataset.id===c.id);c.y=y;el.style.top=y+'px';height=Math.max(height,el.offsetHeight)}y+=height+24}$('board').style.minHeight=Math.max(540,y)+'px'}
renderBoard();window.addEventListener('resize',drawConnections);
for(const [id,type] of [['circleTool','circle'],['boxTool','box']])$(id).addEventListener('click',()=>{drawMode=drawMode===type?null:type;document.querySelectorAll('.drawTool').forEach(x=>x.classList.toggle('selected',x.id===id&&drawMode===type));$('board').classList.toggle('drawing',!!drawMode)});
$('undoShape').addEventListener('click',()=>{shapes.pop();drawConnections();saveBoard()});
$('board').addEventListener('pointerdown',e=>{if(!drawMode||e.target.closest('.card')||e.target.closest('button'))return;const board=$('board'),rect=board.getBoundingClientRect(),x=e.clientX-rect.left+board.scrollLeft,y=e.clientY-rect.top+board.scrollTop;const shape={type:drawMode,x,y,w:8,h:8};shapes.push(shape);board.setPointerCapture(e.pointerId);const move=ev=>{shape.w=Math.max(8,Math.abs(ev.clientX-e.clientX));shape.h=Math.max(8,Math.abs(ev.clientY-e.clientY));shape.x=Math.min(x,ev.clientX-rect.left+board.scrollLeft);shape.y=Math.min(y,ev.clientY-rect.top+board.scrollTop);drawConnections()};board.addEventListener('pointermove',move);board.addEventListener('pointerup',()=>{board.removeEventListener('pointermove',move);saveBoard()},{once:true});drawConnections()});
$('connectCards').addEventListener('click',()=>{connectingFrom='select';$('connectCards').textContent='Click the first card, then the second'});
$('addCard').addEventListener('click',()=>{const i=cards.length;cards.push({id:`idea-${Date.now()}`,type:'idea',text:'Type your idea here',x:24+(i%2)*285,y:26+Math.floor(i/2)*168});renderBoard();saveBoard();$('board').lastElementChild.querySelector('.cardtext').focus()});
$('downloadBoard').addEventListener('click',()=>{const blob=new Blob([JSON.stringify({app:'Voino',version:1,title:$('noteTitle').value,transcript:$('transcript').value,cards,connections,shapes},null,2)],{type:'application/json'});const url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download='voino-board.json';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000)});

const error=text=>{ $('error').textContent=text;$('error').hidden=!text };
const formatTime=seconds=>`${String(Math.floor(seconds/60)).padStart(2,'0')}:${String(seconds%60).padStart(2,'0')}`;
function finish(){ stopping=false;$('record').disabled=false;clearTimeout(stopTimer);recording=false;listening=false;clearTimeout(retryTimer);networkRetryPending=false;clearInterval(clock);$('record').textContent='Start speaking';$('record').classList.remove('active');$('recorder').classList.remove('listening');$('recordStatus').textContent='Paused. Your transcript is editable.';save();if(isNative&&NativeSpeechRecognition){NativeSpeechRecognition.stop().catch(()=>{});}generateNotes(false);}
function beginWeb(resume=false, automatic=false){
 if(!WebSpeechRecognition){error('This browser does not offer speech recognition. Use a supported Chrome browser, or paste a transcript to make notes.');return}
 if(!resume){networkRetries=0}
 if(!automatic)networkRetries=0;
 clearTimeout(retryTimer);networkRetryPending=false;
 error('');const before=$('transcript').value.trim();beforeSession=resume&&before ? before+' ' : '';
 webRecognition=new WebSpeechRecognition();const current=webRecognition;webRecognition.lang=document.documentElement.lang||'en-US';webRecognition.continuous=true;webRecognition.interimResults=true;
 webRecognition.onresult=e=>{if(!recording||webRecognition!==current)return;networkRetries=0;const words=speechSnapshot(e.results);$('transcript').value=stitchSpeech(beforeSession,words);save()};
 webRecognition.onerror=e=>{
  if(!recording||webRecognition!==current)return;
  const decision=recognitionFailure(e.error,networkRetries,recording);
  if(decision.retry){
    networkRetries++;networkRetryPending=true;listening=false;clearInterval(clock);
    $('recordStatus').textContent=`Speech service disconnected. Retrying ${networkRetries}/2...`;
    error('Browser speech service is unreachable right now. Retrying briefly; your words are kept.');
    retryTimer=setTimeout(()=>{if(!recording||webRecognition!==current)return;beforeSession=$('transcript').value.trim();begin(true,true)},decision.delay);
    return;
  }
  const denied=e.error==='not-allowed'||e.error==='service-not-allowed';
  const network=e.error==='network';
  error(denied?'Microphone access was denied. Allow it in your browser, or paste a transcript.':network?"The browser's online speech service could not connect after three attempts. Check your connection, Chrome microphone permission and VPN/firewall, or type/paste the transcript.":`Speech recognition stopped (${e.error}). Press Continue listening to resume this session.`);
  finish();$('recordStatus').textContent=network?'Speech service unavailable. Your transcript is safe to edit.':'Speech paused. Your transcript is editable.';
  if(!denied)$('record').textContent='Continue listening';
 };
 webRecognition.onend=()=>{if(webRecognition!==current)return;listening=false;if(recording&&!networkRetryPending){if(!stopping)error('Speech recognition stopped. Press Continue listening to resume this session.');finish();$('record').textContent='Continue listening'}};
 try{webRecognition.start();listening=true;recording=true;startedAt=Date.now();$('record').textContent='Stop listening';$('record').classList.add('active');$('recorder').classList.add('listening');$('recordStatus').textContent='Listening for words...';clock=setInterval(()=>$('timer').textContent=formatTime(Math.floor((Date.now()-startedAt)/1000)),1000)}catch{error('Could not start the microphone. Try again or paste a transcript.');finish()}
}
async function beginNative(resume=false){
  try {
    await nativeReady;
    const { available } = await NativeSpeechRecognition.available();
    if (!available) { showManualMode('Native speech is unavailable. Type, paste, or use your keyboard microphone.'); return; }
    let perm = await NativeSpeechRecognition.checkPermissions();
    if (perm.speechRecognition !== 'granted') {
       perm = await NativeSpeechRecognition.requestPermissions();
       if (perm.speechRecognition !== 'granted') { error('Microphone access was denied. Allow it in Android settings, or paste a transcript.'); return; }
    }
    error('');
    const before=$('transcript').value.trim();
    beforeSession=resume&&before ? before+' ' : '';
    
    speechSessionId++;
    const currentSession = speechSessionId;
    
    await NativeSpeechRecognition.removeAllListeners();
    await NativeSpeechRecognition.addListener('partialResults', (data) => {
      if (!recording || speechSessionId !== currentSession) return;
      if (data.matches && data.matches.length > 0) {
        $('transcript').value = stitchSpeech(beforeSession, data.matches[0]);
        save();
      }
    });
    await NativeSpeechRecognition.addListener('listeningState', (data) => {
      if (speechSessionId !== currentSession) return;
      if (data.status === 'stopped' && recording) {
        listening = false;
        if(!stopping)error('Speech recognition stopped. Press Continue listening to resume.');
        finish();
        $('record').textContent='Continue listening';
      }
    });
    
    recording=true;
    await NativeSpeechRecognition.start({ language: "en-US", partialResults: true, popup: false });
    
    if(!recording)return;
    listening=true; startedAt=Date.now();
    $('record').textContent='Stop listening'; $('record').classList.add('active');
    $('recorder').classList.add('listening'); $('recordStatus').textContent='Listening for words...';
    clock=setInterval(()=>$('timer').textContent=formatTime(Math.floor((Date.now()-startedAt)/1000)),1000);
  } catch(e) {
    error('Could not start the microphone (' + e.message + '). Try again or paste a transcript.');
    finish();
  }
}
async function begin(resume=false, automatic=false) {
  if (isNative) { await beginNative(resume); } else { beginWeb(resume, automatic); }
}

function showManualMode(message='This browser has no built-in speech recognition. Type or paste below. If your phone keyboard has a microphone, use it to dictate here.') {
 $('support').textContent='Type / paste mode';$('record').hidden=true;$('timer').hidden=true;
 $('recordStatus').textContent='Your words still become editable cards.';
 $('captureHint').textContent=message;$('transcriptLabel').textContent='Type, paste or dictate your words';
 $('transcript').placeholder='Type or paste a lecture or meeting transcript here. You can also use your phone keyboard microphone if available.';
 $('manualInput').textContent='Enter words';
}
$('support').textContent=isNative?'Android speech':WebSpeechRecognition?'Browser speech available':'Type / paste mode';
if(!isNative&&!WebSpeechRecognition)showManualMode();
$('manualInput').addEventListener('click',()=>{$('transcript').focus();$('transcript').scrollIntoView({block:'center',behavior:'smooth'})});
function stopCapture(){
 stopping=true;
 clearTimeout(retryTimer);networkRetryPending=false;
 if(isNative){finish();return}
 if(listening&&webRecognition){$('recordStatus').textContent='Finishing transcript...';$('record').disabled=true;stopTimer=setTimeout(()=>{finish();$('record').disabled=false},1500);try{webRecognition.stop()}catch{finish();$('record').disabled=false}}
 else finish();
}
$('record').addEventListener('click',()=>{if(recording)stopCapture();else begin(!!$('transcript').value.trim())});
function generateNotes(manual=true){
 const source=$('transcript').value.trim();
 if(!source){if(manual)error('Speak, paste or type some words first.');return false}
 if(!manual&&(boardEdited||source===lastGeneratedSource))return false;
 if(manual&&(cards.length||shapes.length)&&boardEdited&&!confirm('Replace your edited board with new notes? Export it first if you want to keep it.'))return false;
 const n=makeNotes(source,$('title').value);$('noteTitle').value=n.title;$('points').value=n.points.join('\n\n');$('actions').value=n.actions.join('\n\n');
 cards=toCards(n);connections=[];shapes=[];boardEdited=false;lastGeneratedSource=source;renderBoard();save();
 $('boardStatus').textContent=`${cards.length} editable ${cards.length===1?'card':'cards'} made from your transcript.`;
 if(manual)$('board').scrollIntoView({block:'start',behavior:'smooth'});
 return true;
}
$('generate').addEventListener('click',()=>{error('');generateNotes(true)});
for(const id of ['noteTitle','points','actions'])$(id).addEventListener('input',()=>{boardEdited=true});
const currentNote=()=>({title:$('noteTitle').value.trim()||'New note',points:$('points').value.split(/\n\s*\n|\n/).map(x=>x.trim()).filter(Boolean),actions:$('actions').value.split(/\n\s*\n|\n/).map(x=>x.trim()).filter(Boolean),transcript:$('transcript').value.trim()});
$('copy').addEventListener('click',async()=>{try{await navigator.clipboard.writeText(exportText(currentNote()));$('copy').textContent='Copied';setTimeout(()=>$('copy').textContent='Copy notes',1800)}catch{error('Clipboard unavailable. Download the note instead.')}});
$('download').addEventListener('click',()=>{const n=currentNote(),blob=new Blob([exportText(n)],{type:'text/plain;charset=utf-8'}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=(n.title.replace(/[^a-z0-9-]+/gi,'-').slice(0,45)||'voino')+'.txt';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000)});
$('reset').addEventListener('click',()=>{if(!confirm('Clear this guest session? Download notes or the board first if you want to keep them.'))return;speechSessionId++;if(recording){recording=false;if(!isNative&&webRecognition){webRecognition.onresult=null;webRecognition.onend=null;try{webRecognition.abort()}catch{}}finish()}clearSession();$('record').textContent='Start speaking';$('recordStatus').textContent='Ready when you are'});

function activatePro() {
  const badge = $('proBadge');
  if (badge) {
    badge.textContent = 'TEST PRO · HISTORY NOT AVAILABLE';
    badge.style.background = '#dbeafe';
    badge.style.color = '#1e40af';
    badge.style.borderColor = '#93c5fd';
  }
  const buyBtn = $('buyPro');
  if (buyBtn) buyBtn.style.display = 'none';
  const saveState = $('saveState');
  if (saveState) saveState.textContent = 'Test Pro - history unavailable';
}

if (isNative) {
 nativeReady.then(async()=>{
  $('buyPro').style.display = 'inline-block';
  Purchases.setLogLevel({ level: LOG_LEVEL.DEBUG });
  
  console.log('RevenueCat: Configuring SDK with API key ending in', String(process.env.REVENUECAT_KEY).slice(-4));
  await Purchases.configure({ apiKey: process.env.REVENUECAT_KEY });
  
  console.log('RevenueCat: Fetching initial CustomerInfo...');
  Purchases.getCustomerInfo().then(info => {
    console.log('RevenueCat: CustomerInfo retrieved', info);
    if (info.entitlements.active['voino_pro']) {
      console.log('RevenueCat: voino_pro entitlement is ACTIVE at startup');
      activatePro();
    } else {
      console.log('RevenueCat: voino_pro entitlement is NOT active at startup');
    }
  }).catch(e => console.error('RevenueCat Error getting customer info:', e));

  $('buyPro').addEventListener('click', async () => {
    try {
      console.log('RevenueCat: Fetching offerings...');
      const offerings = await Purchases.getOfferings();
      console.log('RevenueCat: Offerings received', offerings);
      
      if (offerings.current !== null && offerings.current.availablePackages.length !== 0) {
        console.log('RevenueCat: Starting purchase for package', offerings.current.availablePackages[0].identifier);
        const { customerInfo } = await Purchases.purchasePackage({ aPackage: offerings.current.availablePackages[0] });
        
        console.log('RevenueCat: Purchase successful, checking updated CustomerInfo:', customerInfo);
        if (customerInfo.entitlements.active['voino_pro']) {
          console.log('RevenueCat: voino_pro entitlement UNLOCKED via purchase!');
          activatePro();
        } else {
          console.log('RevenueCat: Purchase succeeded but voino_pro entitlement missing in result');
        }
      } else {
        console.warn('RevenueCat: No current offerings or packages available in Test Store');
        alert("No offerings available from Test Store.");
      }
    } catch (e) {
      if (e.userCancelled) {
         console.log('RevenueCat: Purchase cancelled by user, Pro not unlocked.');
      } else {
         console.error('RevenueCat: Purchase failed', e);
         alert("Purchase error: " + e.message);
      }
    }
  });
 }).catch(()=>{error('Native purchases unavailable. Notes still work.');});
}
