import 'package:flutter/material.dart';

/// Uses the recognizer's existing partial results; no new audio processing.
class LiveTranscript extends StatelessWidget {
  const LiveTranscript({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final words = text.trim();
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 560),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF4EEE1).withValues(alpha: 0.96),
        border: Border.all(color: const Color(0xFFC4903F).withValues(alpha: 0.45)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('LIVE TRANSCRIPT',
            style: TextStyle(fontSize: 10, letterSpacing: 1.6, color: Color(0xFF2B2A28))),
        const SizedBox(height: 8),
        SizedBox(
          height: 88,
          child: SingleChildScrollView(
            reverse: true,
            child: Text(
              words.isEmpty ? 'Waiting for words... Text appears as speech is recognized.' : words,
              style: TextStyle(
                fontSize: 16,
                height: 1.4,
                fontWeight: FontWeight.w300,
                color: words.isEmpty ? Colors.black54 : const Color(0xFF2B2A28),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
