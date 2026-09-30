const normalize = value => String(value || '').replace(/\s+/g, ' ').trim();
const splitSentences = text => normalize(text).match(/[^.!?]+[.!?]?/g)?.map(x => x.trim()).filter(Boolean) ?? [];
const actionPattern = /\b(?:need to|have to|should|must|remember to|assignment|deadline|submit|send|finish|prepare|review|complete|due)\b/i;
const unique = list => [...new Set(list.map(normalize).filter(Boolean))];
export function makeNotes(transcript, title = 'New note') {
  const source = normalize(transcript);
  if (!source) return { title: normalize(title) || 'New note', points: [], actions: [], transcript: '' };
  const sentences = splitSentences(source);
  const actions = unique(sentences.filter(s => actionPattern.test(s)));
  const points = unique(sentences.filter(s => !actions.includes(s)));
  return { title: normalize(title) || 'New note', points: points.length ? points : unique(sentences.filter(s => !actions.includes(s))), actions, transcript: source };
}
export function exportText(note) {
  return `${note.title}\n\nKey points\n${note.points.length ? note.points.map(p => `• ${p}`).join('\n') : '(none yet)'}\n\nThings to do\n${note.actions.length ? note.actions.map(a => `☐ ${a}`).join('\n') : '(none yet)'}\n\nOriginal transcript\n${note.transcript || '(empty)'}\n`;
}
