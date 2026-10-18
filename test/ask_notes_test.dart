import 'package:flutter_test/flutter_test.dart';
import 'package:voino/ask_notes.dart';
import 'package:voino/logic.dart';

Note sample() => Note(
      'Product sync',
      ['Launch moved to Tuesday.', 'Budget stays at 5000 rupees.'],
      ['Send the deck to Aisha.'],
      'RAW TRANSCRIPT THAT MUST NEVER LEAVE',
      summary: 'Not a consented field.',
    );

void main() {
  test('payload carries per-session consent naming the third-party service', () {
    final p = buildAskPayload(sample());
    final consent = p['consent'] as Map<String, dynamic>;
    expect(consent['per_session'], isTrue);
    expect(consent['third_party_voice_service'], isTrue);
    expect(consent['fields'], kAskAllowedFields);
  });

  test('payload sends only title, points and actions - never the transcript', () {
    final p = buildAskPayload(sample());
    final note = p['note'] as Map<String, dynamic>;
    expect(note.keys.toSet(), {'title', 'points', 'actions'});
    expect(note['title'], 'Product sync');
    expect(note['points'], hasLength(2));
    expect(note['actions'], hasLength(1));
    expect(p.toString(), isNot(contains('RAW TRANSCRIPT')));
    expect(p.toString(), isNot(contains('Not a consented field')));
  });

  test('field subset is honored', () {
    final p = buildAskPayload(sample(), fields: const ['points']);
    final note = p['note'] as Map<String, dynamic>;
    expect(note.keys.toSet(), {'points'});
    final consent = p['consent'] as Map<String, dynamic>;
    expect(consent['fields'], ['points']);
  });

  test('server error codes map to calm user text', () {
    expect(askErrorText('not_configured'), contains('not configured'));
    expect(askErrorText('vaani_quota'), contains('credit'));
    expect(askErrorText('rate_limited'), contains('Try again'));
    expect(askErrorText('something_new'), contains('voice service'));
  });
}
