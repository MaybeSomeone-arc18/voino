import re

with open('src/app.js', 'r') as f:
    content = f.read()

# Fix the first conflict block
content = re.sub(
    r'<<<<<<< HEAD\nconst SpeechRecognition.*?=======\nconst WebSpeechRecognition.*?>>>>>>>[^\n]*\n',
    """const WebSpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
const isNative = Capacitor.isNativePlatform();
let webRecognition, recording = false, startedAt = 0, clock, beforeSession = '', listening = false;
let speechSessionId = 0;
let retryTimer, networkRetries=0, networkRetryPending=false;
const recognitionFailure=(reason,retries,active)=>active&&reason==='network'&&retries<2?{retry:true,delay:750*(retries+1)}:{retry:false,delay:0};
""",
    content,
    flags=re.DOTALL
)

# Fix the second conflict block
second_block_replacement = """function finish(){recording=false;clearTimeout(retryTimer);networkRetryPending=false;clearInterval(clock);$('record').textContent='Start speaking';$('record').classList.remove('active');$('recorder').classList.remove('listening');$('recordStatus').textContent='Paused. Your transcript is editable.';save();if(isNative){NativeSpeechRecognition.stop().catch(()=>{});}}
function beginWeb(resume=false, automatic=false){
 if(!WebSpeechRecognition){error('This browser does not offer speech recognition. Use a supported Chrome browser, or paste a transcript to make notes.');return}
 if(!resume){const typedName=$('title').value;clearSession();$('title').value=typedName;networkRetries=0}
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
 webRecognition.onend=()=>{if(webRecognition!==current)return;listening=false;if(recording&&!networkRetryPending){error('Speech recognition stopped. Press Continue listening to resume this session.');finish();$('record').textContent='Continue listening'}};
 try{webRecognition.start();listening=true;recording=true;startedAt=Date.now();$('record').textContent='Stop listening';$('record').classList.add('active');$('recorder').classList.add('listening');$('recordStatus').textContent='Listening for words...';clock=setInterval(()=>$('timer').textContent=formatTime(Math.floor((Date.now()-startedAt)/1000)),1000)}catch{error('Could not start the microphone. Try again or paste a transcript.');finish()}
}
async function beginNative(resume=false){
  try {
    const { available } = await NativeSpeechRecognition.available();
    if (!available) { error('Native speech recognition is not available on this device.'); return; }
    let perm = await NativeSpeechRecognition.checkPermissions();
    if (perm.speechRecognition !== 'granted') {
       perm = await NativeSpeechRecognition.requestPermissions();
       if (perm.speechRecognition !== 'granted') { error('Microphone access was denied. Allow it in Android settings, or paste a transcript.'); return; }
    }
    if(!resume){ const typedName=$('title').value; clearSession(); $('title').value=typedName; }
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
        error('Speech recognition stopped. Press Continue listening to resume.');
        finish();
        $('record').textContent='Continue listening';
      }
    });
    
    await NativeSpeechRecognition.start({ language: "en-US", partialResults: true, popup: false });
    
    listening=true; recording=true; startedAt=Date.now();
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

$('support').textContent=isNative ? 'Native Android Speech available' : (WebSpeechRecognition?'Speech recognition available':'Manual transcript mode');
$('record').addEventListener('click',()=>{if(recording){recording=false;clearTimeout(retryTimer);if(listening&&!isNative&&webRecognition)webRecognition.stop();finish()}else begin($('record').textContent==='Continue listening')});
"""

content = re.sub(
    r'<<<<<<< HEAD\nfunction finish\(\).*?=======\nfunction finish\(\).*?>>>>>>>[^\n]*\n',
    second_block_replacement,
    content,
    flags=re.DOTALL
)

with open('src/app.js', 'w') as f:
    f.write(content)
