import 'package:flutter_test/flutter_test.dart';
import 'package:voino/logic.dart';

void main() {
  test('cleanWhisperText keeps gap markers but strips non-speech tags', () {
    expect(cleanWhisperText('hello [gap 0:00-1:06 not transcribed] world'), 'hello [gap 0:00-1:06 not transcribed] world');
    expect(cleanWhisperText('hello [BLANK_AUDIO] world'), 'hello world');
    expect(cleanWhisperText('hello (music) world'), 'hello world');
  });

  test('gap markers lead the note and are not buried under long points', () {
    final longPoint = List.filled(40, 'tutorial').join(' ');
    final note = makeNotes('$longPoint. [gap 0:00-1:06 not transcribed]');
    expect(note.points.first, '[gap 0:00-1:06 not transcribed]');
    expect(note.topics.first.points, [0]);
    expect(note.topics.first.name, isNot('Other'));
  });

  test('note with only a gap marker still shows it under Key points', () {
    final note = makeNotes('[gap 0:00-0:40 not transcribed]');
    expect(note.points, ['[gap 0:00-0:40 not transcribed]']);
    expect(note.topics.first.name, 'Key points');
    expect(note.topics.first.points, [0]);
  });

  test('gap marker text is excluded from extracted sentences', () {
    final note = makeNotes('The deadline is Friday. [gap 0:03-0:09 not transcribed]');
    expect(note.points.where((p) => p.contains('gap') && !p.startsWith('[gap ')), isEmpty);
    expect(note.points.first, '[gap 0:03-0:09 not transcribed]');
  });

  test('replaceNthOccurrence rewrites exactly the targeted marker', () {
    const m = '[gap 0:00-0:08 not transcribed]';
    final t = 'alpha $m beta $m gamma';
    expect(replaceNthOccurrence(t, m, 0, 'X'), 'alpha X beta $m gamma');
    expect(replaceNthOccurrence(t, m, 1, 'Y'), 'alpha $m beta Y gamma');
    expect(replaceNthOccurrence(t, m, 2, 'Z'), t); // occurrence missing: unchanged
    expect(replaceNthOccurrence(t, '[gap 9:99', 0, 'Z'), t); // needle missing: unchanged
    expect(replaceNthOccurrence('only $m here', m, 0, ''), 'only  here');
  });
}
