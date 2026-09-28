export function toCards(note) {
  const entries=[...note.points.map(text=>({type:'point',text})),...note.actions.map(text=>({type:'action',text}))];
  return entries.map((entry,i)=>({...entry,id:`card-${Date.now()}-${i}`,x:24+(i%2)*285,y:26+Math.floor(i/2)*168}));
}
export function safeCards(value) {
  if(!Array.isArray(value))return [];
  return value.slice(0,40).filter(c=>c&&typeof c.text==='string'&&['point','action','idea'].includes(c.type)).map((c,i)=>({id:String(c.id||`card-${i}`),type:c.type,color:['mint','sand','lavender','rose'].includes(c.color)?c.color:'mint',text:c.text.slice(0,1400),x:Number.isFinite(c.x)?Math.max(0,Math.min(4000,c.x)):24,y:Number.isFinite(c.y)?Math.max(0,Math.min(4000,c.y)):24}));
}

export function safeConnections(value,cards){const ids=new Set(cards.map(c=>c.id));return Array.isArray(value)?value.filter(x=>x&&ids.has(x.from)&&ids.has(x.to)&&x.from!==x.to).slice(0,30).map(x=>({from:String(x.from),to:String(x.to)})):[]}
