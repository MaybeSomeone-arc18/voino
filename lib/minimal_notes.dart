import 'package:flutter/material.dart';
import 'logic.dart';

/// Presentation only: exports and extraction keep their existing source data.
class MinimalNotes extends StatelessWidget {
  const MinimalNotes({
    super.key,
    required this.note,
    required this.source,
    required this.capture,
    required this.onCopy,
    required this.onBoard,
    required this.onFile,
    required this.busy,
    this.saveStatus = 'Guest notes are not saved automatically.',
  });
  final Note note;
  final String source, saveStatus;
  final Widget capture;
  final VoidCallback onCopy, onBoard;
  final ValueChanged<String> onFile;
  final bool busy;

  @override
  Widget build(BuildContext context) => AnimatedSize(
    duration: const Duration(milliseconds: 280),
    curve: Curves.easeOut,
    alignment: Alignment.topCenter,
    child: Card(
      elevation: 0,
      color: const Color(0xFFF4EEE1).withValues(alpha: 0.93),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: const Color(0xFF2B2A28).withValues(alpha: 0.10),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    note.title,
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w300,
                      color: Color(0xFF2B2A28),
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Board files',
                  onSelected: onFile,
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'copy',
                      child: Text('Copy board JSON'),
                    ),
                    PopupMenuItem(
                      value: 'save',
                      child: Text('Save board JSON'),
                    ),
                    PopupMenuItem(
                      value: 'open',
                      child: Text('Open board file'),
                    ),
                    PopupMenuItem(
                      value: 'paste',
                      child: Text('Paste board JSON'),
                    ),
                  ],
                ),
              ],
            ),
            if (source.isNotEmpty)
              Text(
                source,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.black54,
                  letterSpacing: 0.4,
                ),
              ),
            const SizedBox(height: 14),
            Container(width: 28, height: 2, color: const Color(0xFFC4903F)),
            const SizedBox(height: 20),
            if (note.summary.isNotEmpty) ...[
              Text(note.summary),
              const SizedBox(height: 18),
            ],
            if (note.points.isNotEmpty) ...[
              const Text(
                'Key points',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              for (final point in note.points)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('• $point'),
                ),
              const SizedBox(height: 10),
            ],
            if (note.actions.isNotEmpty) ...[
              const Text(
                'Things to do',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              for (final action in note.actions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.check_box_outline_blank,
                        size: 18,
                        color: Colors.black54,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(action)),
                    ],
                  ),
                ),
            ],
            if (note.points.isEmpty &&
                note.actions.isEmpty &&
                note.summary.isEmpty)
              const Text(
                'Your notes will appear here. Add words in Transcript, then make a board.',
                style: TextStyle(color: Colors.black54),
              ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(onPressed: onCopy, child: const Text('Copy notes')),
                FilledButton.tonal(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2B2A28),
                    foregroundColor: const Color(0xFFF4EEE1),
                  ),
                  onPressed: busy ? null : onBoard,
                  child: Text(busy ? 'Working...' : 'Make board'),
                ),
              ],
            ),
            const Divider(height: 28),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: const Text('Transcript', style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                'Review or edit what Voino heard',
                style: TextStyle(fontSize: 11),
              ),
              children: [capture],
            ),
            const SizedBox(height: 8),
            Text(
              'Check extracts against the transcript. $saveStatus',
              style: const TextStyle(fontSize: 11, color: Colors.black54),
            ),
          ],
        ),
      ),
    ),
  );
}
