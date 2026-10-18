import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:livekit_client/livekit_client.dart';

import 'logic.dart';

/// "Ask your notes" - talk to the current notes through Vaani's voice agents.
///
/// Privacy contract (enforced again on the server in api/_lib/vaani.js):
/// only the consented note fields (title, points, actions) leave the device.
/// The raw transcript is never sent. Consent is per session and names Vaani
/// (Vaani Research Labs) as the third-party voice service.
const List<String> kAskAllowedFields = ['title', 'points', 'actions'];

/// Builds the dispatch request body. Never includes the raw transcript.
Map<String, dynamic> buildAskPayload(Note note,
    {List<String> fields = kAskAllowedFields}) {
  final noteOut = <String, dynamic>{};
  if (fields.contains('title')) noteOut['title'] = note.title;
  if (fields.contains('points')) noteOut['points'] = note.points;
  if (fields.contains('actions')) noteOut['actions'] = note.actions;
  return {
    'consent': {
      'per_session': true,
      'third_party_voice_service': true,
      'fields': List<String>.from(fields),
    },
    'note': noteOut,
  };
}

/// User-facing text for server error codes. Never shows internals.
String askErrorText(String code) {
  switch (code) {
    case 'not_configured':
      return 'Ask your notes is not configured on this deployment yet.';
    case 'consent_required':
      return 'Consent is required before anything is sent.';
    case 'notes_too_large':
      return 'This note is too large for one voice session.';
    case 'rate_limited':
      return 'Too many sessions just now. Try again in a minute.';
    case 'vaani_quota':
      return 'The voice service is out of credit for now.';
    case 'vaani_unavailable':
    case 'vaani_rejected':
    case 'bad_vaani_output':
    case 'vaani_auth':
      return 'The voice service could not start the session. Try again.';
    default:
      return 'Could not reach the voice service. Check your connection and try again.';
  }
}

class AskSession {
  AskSession(this.token, this.roomName, this.connectionUrl, this.captionsUrl);
  final String token, roomName, connectionUrl;
  final String? captionsUrl;
  factory AskSession.fromJson(Map<String, dynamic> j) {
    final token = j['token'], url = j['connection_url'];
    if (token is! String || url is! String) {
      throw const FormatException('bad_session');
    }
    return AskSession(token, j['room_name']?.toString() ?? '', url,
        j['live_captions_url']?.toString());
  }
}

class AskException implements Exception {
  AskException(this.code);
  final String code;
  @override
  String toString() => code;
}

/// POSTs the consented note fields to the Voino server, which adds the Vaani
/// key server-side and starts the WebRTC session. Throws AskException.
Future<AskSession> startAskSession(Uri endpoint, Note note,
    {http.Client? client}) async {
  final c = client ?? http.Client();
  try {
    final res = await c
        .post(endpoint,
            headers: {'content-type': 'application/json'},
            body: jsonEncode(buildAskPayload(note)))
        .timeout(const Duration(seconds: 25));
    if (res.statusCode == 200) {
      return AskSession.fromJson(
          jsonDecode(res.body) as Map<String, dynamic>);
    }
    String code = 'unknown';
    try {
      code = (jsonDecode(res.body) as Map<String, dynamic>)['error']
              ?.toString() ??
          'unknown';
    } catch (_) {}
    throw AskException(code);
  } on TimeoutException {
    throw AskException('vaani_unavailable');
  } on http.ClientException {
    throw AskException('vaani_unavailable');
  } finally {
    if (client == null) c.close();
  }
}

enum AskPhase { consent, connecting, live, error }

class AskNotesSheet extends StatefulWidget {
  const AskNotesSheet({super.key, required this.note});
  final Note note;

  static const ink = Color(0xFF2B2A28), paper = Color(0xFFF4EEE1);

  static Future<void> show(BuildContext context, Note note) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: paper,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => AskNotesSheet(note: note),
    );
  }

  @override
  State<AskNotesSheet> createState() => _AskNotesSheetState();
}

class _AskNotesSheetState extends State<AskNotesSheet> {
  AskPhase phase = AskPhase.consent;
  String errorText = '';
  bool micOk = true;
  Room? _room;
  StreamSubscription<RoomEvent>? _events;

  @override
  void dispose() {
    _events?.cancel();
    _room?.disconnect();
    _room?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      phase = AskPhase.connecting;
      errorText = '';
    });
    try {
      final session =
          await startAskSession(Uri.base.resolve('/api/vaani-dispatch'), widget.note);
      final room = Room();
      _room = room;
      _events = room.events.listen((event) async {
        if (event is TrackSubscribedEvent && event.track is RemoteAudioTrack) {
          // Web needs an explicit start for remote audio playback.
          try {
            await (event.track as RemoteAudioTrack).start();
          } catch (_) {}
        }
        if (event is RoomDisconnectedEvent && mounted) {
          Navigator.of(context).maybePop();
        }
      });
      await room
          .connect(session.connectionUrl, session.token)
          .timeout(const Duration(seconds: 20));
      var mic = true;
      try {
        await room.localParticipant?.setMicrophoneEnabled(true);
      } catch (_) {
        mic = false; // no mic (or denied): still connected, listen-only
      }
      if (!mounted) return;
      setState(() {
        phase = AskPhase.live;
        micOk = mic;
      });
    } on AskException catch (e) {
      if (!mounted) return;
      setState(() {
        phase = AskPhase.error;
        errorText = askErrorText(e.code);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        phase = AskPhase.error;
        errorText = askErrorText('unknown');
      });
    }
  }

  Future<void> _end() async {
    await _room?.disconnect();
    if (mounted) Navigator.of(context).maybePop();
  }

  Widget _consentView() {
    final t = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ask your notes', style: t.headlineSmall),
        const SizedBox(height: 6),
        Text('Talk to these notes by voice - Hindi, English or a mix.',
            style: t.bodyMedium),
        const SizedBox(height: 18),
        Text('This session sends to Vaani (voice AI by Vaani Research Labs):',
            style: t.titleSmall),
        const SizedBox(height: 8),
        for (final line in const [
          'Note title',
          'Key points',
          'Things to do',
          'Your voice while you talk',
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              const Icon(Icons.check, size: 16, color: Colors.black54),
              const SizedBox(width: 8),
              Text(line, style: t.bodyMedium),
            ]),
          ),
        const SizedBox(height: 10),
        Text(
          'Never sent: the raw transcript, board files, or anything else on this device. '
          'Answers come only from these notes - if it is not in them, the assistant says it does not know.',
          style: t.bodySmall,
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Not now'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: _start,
                icon: const Icon(Icons.mic, size: 18),
                label: const Text('Agree and start'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _connectingView() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 20),
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text('Starting a secure voice session...',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 20),
        ],
      );

  Widget _liveView() {
    final t = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        Icon(Icons.graphic_eq, size: 40, color: t.headlineSmall?.color),
        const SizedBox(height: 12),
        Text(
          micOk
              ? 'Live - ask anything about these notes.'
              : 'Live, listen-only: no microphone was available.',
          style: t.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          'Answers come only from these notes. If it is not in them, the assistant says it does not know.',
          style: t.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _end,
            icon: const Icon(Icons.call_end, size: 18),
            label: const Text('End call'),
          ),
        ),
      ],
    );
  }

  Widget _errorView() => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Could not start', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          Text(errorText, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Close'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _start,
                  child: const Text('Try again'),
                ),
              ),
            ],
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final view = switch (phase) {
      AskPhase.consent => _consentView(),
      AskPhase.connecting => _connectingView(),
      AskPhase.live => _liveView(),
      AskPhase.error => _errorView(),
    };
    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: view,
    );
  }
}
