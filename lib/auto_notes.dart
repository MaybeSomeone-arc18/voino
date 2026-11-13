import 'package:flutter/material.dart';

/// Decides when live notes should refresh during an active listening
/// session: enough new words since the last refresh, and enough time
/// between refreshes so updates feel steady instead of jumpy.
class AutoNotes {
  AutoNotes({this.minNewWords = 100, this.minInterval = const Duration(seconds: 90), DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final int minNewWords;
  final Duration minInterval;
  final DateTime Function() _now;

  int _wordsAtLastRun = 0;
  DateTime _lastRun = DateTime.fromMillisecondsSinceEpoch(0);
  bool _primed = false;

  static int wordCount(String s) => RegExp(r'\S+').allMatches(s).length;

  /// The first refresh primes on a smaller amount of speech so short
  /// discussions still get early notes.
  bool due(String transcript) {
    final words = wordCount(transcript);
    final threshold = _primed ? minNewWords : 60;
    if (words - _wordsAtLastRun < threshold) return false;
    return _now().difference(_lastRun) >= minInterval;
  }

  void markRun(String transcript) {
    _primed = true;
    _wordsAtLastRun = wordCount(transcript);
    _lastRun = _now();
  }

  void reset() {
    _primed = false;
    _wordsAtLastRun = 0;
    _lastRun = DateTime.fromMillisecondsSinceEpoch(0);
  }
}

/// Persistent indicator shown outside the listen view while the mic is on,
/// so recording never happens invisibly. Tapping returns to the listen view.
class ListeningBanner extends StatelessWidget {
  const ListeningBanner({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: const Color(0xFFFFF4E8),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.fiber_manual_record, color: Color(0xFFC64A2E), size: 12),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text('Listening - notes update as you speak. Tap to view.',
                        style: TextStyle(fontSize: 13, height: 1.4)),
                  ),
                  Icon(Icons.mic, size: 16, color: Colors.black54),
                ],
              ),
            ),
          ),
        ),
      );
}

/// Shown when a restored draft carries an open-capture marker: the previous
/// session ended without a clean stop (crash, kill, power loss), so speech
/// captured near the end may never have reached the note.
class InterruptedCaptureBanner extends StatelessWidget {
  const InterruptedCaptureBanner({super.key, required this.onDismiss});
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Material(
          color: const Color(0xFFFFF4E8),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Color(0xFFC64A2E), size: 16),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Your last capture ended unexpectedly. This note was restored from this device, but the most recent speech may be missing.',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                ),
                InkResponse(
                  onTap: onDismiss,
                  radius: 18,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close, size: 16, color: Colors.black54),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
