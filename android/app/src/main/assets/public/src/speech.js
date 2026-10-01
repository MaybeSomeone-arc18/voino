// Chrome may report the full result list on every event, and some Android builds
// revise interim hypotheses rather than appending a new spoken segment.
export const cleanSpeech = value => String(value || '').replace(/\s+/g,' ').trim();
const tokens = text => cleanSpeech(text).split(' ').filter(Boolean);
export function stitchSpeech(previous, incoming) {
  const a=tokens(previous), b=tokens(incoming);
  if(!a.length)return b.join(' ');
  if(!b.length)return a.join(' ');
  const equal=(x,y)=>x.toLocaleLowerCase()===y.toLocaleLowerCase();
  if(b.length>=a.length && a.every((t,i)=>equal(t,b[i])))return b.join(' ');
  if(a.length>=b.length && b.every((t,i)=>equal(t,a[i])))return a.join(' ');
  for(let overlap=Math.min(a.length,b.length);overlap>0;overlap--){
    if(a.slice(-overlap).every((t,i)=>equal(t,b[i])))return [...a,...b.slice(overlap)].join(' ');
  }
  return [...a,...b].join(' ');
}
export function speechSnapshot(results) {
  let finalText='',interim='';
  for(let i=0;i<results.length;i++){
    const r=results[i],text=cleanSpeech(r?.[0]?.transcript);
    if(!text)continue;
    if(r.isFinal)finalText=stitchSpeech(finalText,text);
    else interim=text; // latest hypothesis, not a new independent utterance
  }
  return stitchSpeech(finalText,interim);
}
