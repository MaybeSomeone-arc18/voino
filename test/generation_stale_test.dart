import 'package:flutter_test/flutter_test.dart';
import 'package:voino/logic.dart';

void main() {
  // Regression for the Clear-during-drain race: generate() snapshots the
  // transcript, then awaits (consent dialogs, a network summary). If the
  // user clears or replaces the note in that window, the generated notes
  // must be discarded, not written over the new (possibly empty) state.
  //
  // Identity is the document revision (transcriptUserRev), not the text:
  // Clear-then-restore of the SAME text must still count as stale.
  test('generationStale flags any revision movement in the await window', () {
    expect(generationStale(5, 6), isTrue); // one user edit
    expect(generationStale(5, 9), isTrue); // several mutations
  });

  test('same-text lifecycle: Clear then restore identical text is still stale', () {
    // Lifecycle at the token level: snapshot rev 5 -> Clear bumps to 6 ->
    // restoring the same text from Recent notes bumps to 7. Text equality
    // would compare 'same' == 'same' and wrongly apply; the token must not.
    const revAtSnapshot = 5;
    var rev = revAtSnapshot;
    rev++; // Clear (transcript.text = '')
    rev++; // restore identical text from a saved draft
    expect(generationStale(revAtSnapshot, rev), isTrue);
  });

  test('same-text lifecycle: Clear then retype identical text is still stale', () {
    const revAtSnapshot = 5;
    var rev = revAtSnapshot;
    rev++; // Clear
    rev++; // first keystroke of the retyped (identical) text
    expect(generationStale(revAtSnapshot, rev), isTrue);
  });

  test('generationStale accepts an untouched document', () {
    expect(generationStale(5, 5), isFalse);
    // Programmatic writes (ASR appends, recovery rewrite) do not bump the
    // user revision, so a stop-time auto generate still applies normally.
  });
}
