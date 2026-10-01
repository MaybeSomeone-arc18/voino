import 'package:flutter/material.dart';
import 'logic.dart';

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
    this.showActions = true,
  });
  final Note note;
  final String source, saveStatus;
  final Widget capture;
  final VoidCallback onCopy, onBoard;
  final ValueChanged<String> onFile;
  final bool busy, showActions;
  static const ink = Color(0xFF2B2A28), paper = Color(0xFFF4EEE1);

  Widget section(String title, List<Widget> rows) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
      ),
      const SizedBox(height: 16),
      ...rows,
      const Divider(height: 32, color: Color(0xFFDCD5C8)),
    ],
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Text(
                note.title,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.5,
                  color: ink,
                ),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Board files',
              onSelected: onFile,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'copy', child: Text('Copy board JSON')),
                PopupMenuItem(value: 'save', child: Text('Save board JSON')),
                PopupMenuItem(value: 'open', child: Text('Open board file')),
                PopupMenuItem(value: 'paste', child: Text('Paste board JSON')),
              ],
            ),
          ],
        ),
        if (source.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              source,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
        const SizedBox(height: 28),
        if (note.summary.isNotEmpty) ...[
          Text(note.summary, style: const TextStyle(height: 1.55)),
          const Divider(height: 32),
        ],
        if (note.points.isNotEmpty)
          section('Key points', [
            for (final p in note.points)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ', style: TextStyle(height: 1.55)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(p, style: const TextStyle(height: 1.55)),
                    ),
                  ],
                ),
              ),
          ]),
        if (note.actions.isNotEmpty)
          section('Things to do', [
            for (final a in note.actions)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 3),
                      child: Icon(
                        Icons.check_box_outline_blank,
                        size: 17,
                        color: Colors.black45,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(a, style: const TextStyle(height: 1.55)),
                    ),
                  ],
                ),
              ),
          ]),
        if (note.points.isEmpty && note.actions.isEmpty && note.summary.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 24),
            child: Text(
              'Your notes will appear here. Add words in Transcript, then make a board.',
              style: TextStyle(height: 1.55, color: Colors.black54),
            ),
          ),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(top: 12, bottom: 16),
            title: const Text(
              'Transcript',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'Review or edit what Voino heard',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            children: [capture],
          ),
        ),
        const Divider(height: 1, color: Color(0xFFDCD5C8)),
        const SizedBox(height: 16),
        const Text(
          'Check extracts against the transcript.',
          style: TextStyle(fontSize: 11, color: Colors.black54),
        ),
        if (showActions) ...[
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onCopy,
                  child: const Text('Copy notes'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: busy ? null : onBoard,
                  child: Text(busy ? 'Working...' : 'Make board'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            saveStatus,
            style: const TextStyle(fontSize: 11, color: Colors.black54),
          ),
        ],
        const SizedBox(height: 24),
      ],
    ),
  );
}
