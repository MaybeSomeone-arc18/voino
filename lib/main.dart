import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'board.dart';
import 'gemini.dart';
import 'settings.dart';
import 'logic.dart';

void main() => runApp(const VoinoApp());

class VoinoApp extends StatelessWidget {
  const VoinoApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Voino',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
            colorSchemeSeed: const Color(0xFF3F6F5A),
            scaffoldBackgroundColor: const Color(0xFFF4F2EC),
            useMaterial3: true),
        home: const Home(),
      );
}

const idleStatus = 'Stop listening or tap Make editable board to create your cards.';

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final title = TextEditingController(), transcript = TextEditingController();
  final speech = SpeechToText();
  bool speechReady = false, listening = false, boardEdited = false, connecting = false, busy = false;
  Settings settings = Settings();
  String summary = '', noteSource = '';
  String before = '', lastSource = '', status = idleStatus;
  String? drawMode, connectFrom;
  List<CardModel> cards = [];
  List<Link> links = [];
  List<ShapeModel> shapes = [];
  Offset? dragStart;
  ShapeModel? liveShape;

  @override
  void initState() {
    super.initState();
    Settings.load().then((v) => setState(() => settings = v));
    speech
        .initialize(
          onStatus: (s) {
            if ((s == 'done' || s == 'notListening') && listening) setState(() => listening = false);
          },
          onError: (e) => _msg('Speech error: ${e.errorMsg}. You can type or paste instead.'),
        )
        .then((ok) => setState(() => speechReady = ok));
  }

  void _msg(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> toggleListen() async {
    if (listening) {
      await speech.stop();
      setState(() => listening = false);
      generate(manual: false);
      return;
    }
    before = transcript.text.trim().isEmpty ? '' : '${transcript.text.trim()} ';
    setState(() => listening = true);
    await speech.listen(
      onResult: (r) => setState(() => transcript.text = stitchSpeech(before, r.recognizedWords)),
      listenOptions: SpeechListenOptions(partialResults: true, listenMode: ListenMode.dictation),
    );
  }

  Future<bool> confirm(String q) async =>
      await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(content: Text(q), actions: [
                TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('OK')),
              ])) ??
      false;

  Future<void> generate({bool manual = true}) async {
    final src = transcript.text.trim();
    if (src.isEmpty) {
      if (manual) _msg('Speak, paste or type some words first.');
      return;
    }
    if (!manual && (boardEdited || src == lastSource)) return;
    if (manual &&
        (cards.isNotEmpty || shapes.isNotEmpty) &&
        boardEdited &&
        !await confirm('Replace your edited board with new notes? Export it first if you want to keep it.')) {
      return;
    }
    Note n;
    var how = 'Rule-based extract';
    if (settings.useAi && settings.keys.isNotEmpty) {
      if (!settings.consented) {
        if (!await confirm('Send this transcript to Google Gemini using your API key to write a summary? '
            'It leaves your device. Choose Cancel to use the local extractor instead.')) {
          _apply(makeNotes(src, title.text), src, how);
          return;
        }
        settings.consented = true;
        await settings.save();
      }
      setState(() {
        busy = true;
        status = 'Summarizing with Gemini...';
      });
      try {
        n = await GeminiClient(settings.keys).summarize(src, title: title.text);
        how = 'AI summary (Gemini)';
      } catch (e) {
        n = makeNotes(src, title.text);
        how = 'Rule-based extract (Gemini failed: $e)';
      }
      if (mounted) setState(() => busy = false);
    } else {
      n = makeNotes(src, title.text);
    }
    _apply(n, src, how);
  }

  void _apply(Note n, String src, String how) {
    final b = buildBoard(n);
    setState(() {
      cards = b.cards;
      links = b.links;
      shapes = b.shapes;
      summary = n.summary;
      noteSource = how;
      boardEdited = false;
      lastSource = src;
      status = '${cards.length} editable ${cards.length == 1 ? 'card' : 'cards'} made from your transcript. $how.';
    });
  }

  Future<void> clearAll() async {
    if (!await confirm('Clear everything: transcript, notes, board and drawings? Download first if you want to keep them.')) return;
    if (listening) await speech.cancel();
    setState(() {
      title.clear();
      transcript.clear();
      cards = [];
      links = [];
      shapes = [];
      before = '';
      summary = '';
      noteSource = '';
      busy = false;
      lastSource = '';
      boardEdited = false;
      listening = false;
      drawMode = null;
      connecting = false;
      connectFrom = null;
      liveShape = null;
      status = idleStatus;
    });
  }

  Note currentNote() => Note(
        title.text.trim().isEmpty ? 'New note' : title.text.trim(),
        cards.where((c) => c.type == 'point' || c.type == 'idea').map((c) => c.text).toList(),
        cards.where((c) => c.type == 'action').map((c) => c.text).toList(),
        transcript.text.trim(),
        summary: summary,
      );

  String boardJson() => const JsonEncoder.withIndent('  ').convert({
        'app': 'Voino',
        'version': 1,
        'title': title.text,
        'transcript': transcript.text,
        'cards': cards.map((c) => c.toJson()).toList(),
        'connections': links.map((l) => l.toJson()).toList(),
        'shapes': shapes.map((s) => s.toJson()).toList(),
      });

  Future<void> copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    _msg('$what copied to clipboard');
  }

  Future<void> editCard(CardModel c) async {
    final ctl = TextEditingController(text: c.text);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setD) => AlertDialog(
          title: const Text('Edit card'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: ctl, maxLines: 5, autofocus: true),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              for (final e in cardColors.entries)
                GestureDetector(
                  onTap: () {
                    setD(() => c.color = e.key);
                    setState(() => boardEdited = true);
                  },
                  child: CircleAvatar(
                      radius: 14,
                      backgroundColor: e.value,
                      child: c.color == e.key ? const Icon(Icons.check, size: 14) : null),
                ),
            ]),
          ]),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  cards.remove(c);
                  links.removeWhere((l) => l.from == c.id || l.to == c.id);
                  boardEdited = true;
                });
                Navigator.pop(d, false);
              },
              child: const Text('Delete'),
            ),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok == true) {
      setState(() {
        c.text = ctl.text;
        boardEdited = true;
      });
    }
  }

  void tapCard(CardModel c) {
    if (!connecting) {
      editCard(c);
    } else if (connectFrom == null) {
      setState(() => connectFrom = c.id);
    } else if (connectFrom != c.id) {
      setState(() {
        links.add(Link(connectFrom!, c.id));
        connectFrom = null;
        connecting = false;
        boardEdited = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width > 800;
    final capture = _panel('01 / CAPTURE', 'Listen to the discussion', [
      TextField(
          controller: title,
          decoration: const InputDecoration(labelText: 'Give it a name', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      Row(children: [
        FilledButton.icon(
          onPressed: speechReady ? toggleListen : null,
          icon: Icon(listening ? Icons.stop : Icons.mic),
          label: Text(listening ? 'Stop listening' : (transcript.text.isEmpty ? 'Start speaking' : 'Continue listening')),
        ),
        const SizedBox(width: 12),
        Expanded(
            child: Text(
                speechReady ? (listening ? 'Listening for words...' : 'Speech available') : 'Type / paste mode (speech unavailable)',
                style: const TextStyle(fontSize: 12))),
      ]),
      const SizedBox(height: 12),
      TextField(
          controller: transcript,
          maxLines: 9,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
              labelText: 'What Voino heard (you can fix mistakes)', alignLabelWithHint: true, border: OutlineInputBorder())),
      const SizedBox(height: 12),
      Wrap(spacing: 8, children: [
        FilledButton.tonal(onPressed: busy ? null : generate, child: Text(busy ? 'Working...' : 'Make editable board')),
        OutlinedButton(onPressed: clearAll, child: const Text('Clear all')),
      ]),
      const SizedBox(height: 8),
      const Text(
          "Speech recognition may use the device or browser vendor's online service. Ask permission before recording other people.",
          style: TextStyle(fontSize: 11)),
    ]);
    final notes = _panel('02 / KEEP', 'Notes you can revise', [
      if (noteSource.isNotEmpty) Chip(label: Text(noteSource, style: const TextStyle(fontSize: 11))),
      Text(exportText(currentNote())),
      const SizedBox(height: 12),
      Wrap(spacing: 8, children: [
        OutlinedButton(onPressed: () => copy(exportText(currentNote()), 'Notes'), child: const Text('Copy notes')),
        OutlinedButton(onPressed: () => copy(boardJson(), 'Board JSON'), child: const Text('Copy board JSON')),
        OutlinedButton(onPressed: importBoard, child: const Text('Import board JSON')),
      ]),
      const SizedBox(height: 8),
      const Text('Check notes against the transcript. Rule-based notes are extracts, not a summary. Guest session: nothing is saved.',
          style: TextStyle(fontSize: 11)),
    ]);
    return Scaffold(
      appBar: AppBar(title: const Text('voino'), backgroundColor: Colors.transparent, actions: [
        IconButton(tooltip: 'Gemini settings', icon: Icon(settings.useAi && settings.keys.isNotEmpty ? Icons.auto_awesome : Icons.settings), onPressed: openSettings),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Listen in real time.\nLeave with editable notes.',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        if (wide)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: capture),
            const SizedBox(width: 16),
            Expanded(child: notes),
          ])
        else ...[capture, const SizedBox(height: 16), notes],
        const SizedBox(height: 16),
        _boardSection(),
      ]),
    );
  }

  Size get boardSize {
    var w = 1200.0, h = 900.0;
    for (final c in cards) {
      w = w < c.x + cardSize.width + 80 ? c.x + cardSize.width + 80 : w;
      h = h < c.y + cardSize.height + 80 ? c.y + cardSize.height + 80 : h;
    }
    for (final s in shapes) {
      w = w < s.rect.right + 40 ? s.rect.right + 40 : w;
      h = h < s.rect.bottom + 40 ? s.rect.bottom + 40 : h;
    }
    return Size(w, h);
  }

  Future<void> importBoard() async {
    final ctl = TextEditingController();
    final raw = await showDialog<String>(
        context: context,
        builder: (d) => AlertDialog(
              title: const Text('Import board JSON'),
              content: TextField(controller: ctl, maxLines: 8, decoration: const InputDecoration(hintText: 'Paste a Voino board JSON')),
              actions: [
                TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
                FilledButton(onPressed: () => Navigator.pop(d, ctl.text), child: const Text('Import')),
              ],
            ));
    if (raw == null || raw.trim().isEmpty) return;
    final r = parseBoardJson(raw);
    if (r == null) return _msg('That is not a valid Voino board.');
    if ((cards.isNotEmpty || shapes.isNotEmpty) && boardEdited && !await confirm('Replace your current board with the imported one?')) return;
    setState(() {
      cards = r.board.cards;
      links = r.board.links;
      shapes = r.board.shapes;
      if (r.title.isNotEmpty) title.text = r.title;
      if (r.transcript.isNotEmpty) transcript.text = r.transcript;
      summary = '';
      noteSource = 'Imported board';
      boardEdited = false;
      status = '${cards.length} cards imported. Everything is editable.';
    });
  }

  Future<void> openSettings() async {
    final keys = TextEditingController(text: settings.keys.join('\n'));
    var use = settings.useAi;
    String? result;
    List<String> parse() => keys.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    await showDialog<void>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setD) => AlertDialog(
          title: const Text('Gemini (optional)'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Voino works fully offline with local notes. Add your own Gemini API key(s) for AI summaries. '
                  'One key per line; Voino rotates through them. Keys stay on this device and are sent only to Google.',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              TextField(controller: keys, maxLines: 4, decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'AIza...')),
              SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Use Gemini for summaries'), value: use, onChanged: (v) => setD(() => use = v)),
              if (result != null) Text(result!, style: const TextStyle(fontSize: 12)),
            ]),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                setD(() => result = 'Testing...');
                try {
                  await GeminiClient(parse()).summarize('Voino test. This sentence checks that the key works.');
                  setD(() => result = 'Key works.');
                } catch (e) {
                  setD(() => result = 'Test failed: $e');
                }
              },
              child: const Text('Test'),
            ),
            TextButton(
              onPressed: () {
                setState(() => settings = Settings());
                settings.save();
                Navigator.pop(d);
              },
              child: const Text('Remove keys'),
            ),
            FilledButton(
              onPressed: () {
                final list = parse();
                setState(() {
                  settings.keys = list;
                  settings.useAi = use && list.isNotEmpty;
                });
                settings.save();
                Navigator.pop(d);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panel(String step, String heading, List<Widget> children) => Card(
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(step, style: const TextStyle(fontSize: 11, letterSpacing: 1.2)),
            Text(heading, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            ...children,
          ]),
        ),
      );

  Widget _tool(String label, VoidCallback f, {bool on = false}) =>
      on ? FilledButton.tonal(onPressed: f, child: Text(label)) : OutlinedButton(onPressed: f, child: Text(label));

  Widget _boardSection() {
    final drawing = drawMode != null;
    final size = boardSize;
    return _panel('03 / MAKE SENSE OF IT', 'Make the notes your own.', [
      Wrap(spacing: 8, runSpacing: 8, children: [
        _tool('+ Add a note', () {
          final i = cards.length;
          setState(() {
            cards.add(CardModel('idea-${DateTime.now().millisecondsSinceEpoch}', 'idea', 'Type your idea here',
                24.0 + (i % 2) * 285, 26.0 + (i ~/ 2) * 168, 'sand'));
            boardEdited = true;
          });
        }),
        _tool(connecting ? (connectFrom == null ? 'Tap first card' : 'Tap second card') : 'Connect two cards', () {
          setState(() {
            connecting = !connecting;
            connectFrom = null;
            drawMode = null;
          });
        }, on: connecting),
        _tool('Draw circle', () => setState(() {
              drawMode = drawMode == 'circle' ? null : 'circle';
              connecting = false;
            }), on: drawMode == 'circle'),
        _tool('Draw box', () => setState(() {
              drawMode = drawMode == 'box' ? null : 'box';
              connecting = false;
            }), on: drawMode == 'box'),
        _tool('Undo shape', () => setState(() {
              if (shapes.isNotEmpty) shapes.removeLast();
            })),
        _tool('Undo arrow', () => setState(() {
              if (links.isNotEmpty) links.removeLast();
            })),
      ]),
      const SizedBox(height: 8),
      Text(status, style: const TextStyle(fontSize: 12)),
      const SizedBox(height: 8),
      Container(
        height: 520,
        decoration: BoxDecoration(
            color: const Color(0xFFFBFAF6), border: Border.all(color: Colors.black12), borderRadius: BorderRadius.circular(8)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: drawing ? const NeverScrollableScrollPhysics() : null,
            child: SingleChildScrollView(
              physics: drawing ? const NeverScrollableScrollPhysics() : null,
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: Stack(children: [
                  Positioned.fill(
                    child: GestureDetector(
                      onPanStart: drawing ? (d) => dragStart = d.localPosition : null,
                      onPanUpdate: drawing
                          ? (d) => setState(() =>
                              liveShape = ShapeModel(drawMode!, Rect.fromPoints(dragStart!, d.localPosition)))
                          : null,
                      onPanEnd: drawing
                          ? (_) => setState(() {
                                if (liveShape != null && liveShape!.rect.width > 8 && liveShape!.rect.height > 8) {
                                  shapes.add(liveShape!);
                                  boardEdited = true;
                                }
                                liveShape = null;
                              })
                          : null,
                      child: CustomPaint(
                        painter: BoardPainter(cards, links, [...shapes, ?liveShape]),
                      ),
                    ),
                  ),
                  if (cards.isEmpty)
                    const Positioned(
                        left: 24, top: 24, child: Text('Editable cards appear here after you turn a transcript into notes.')),
                  for (final c in cards) _cardWidget(c),
                ]),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 8),
      const Text(
          'Tap a card to edit or delete it, drag to move. Connect draws arrows; Circle/Box then drag on empty space.',
          style: TextStyle(fontSize: 11)),
    ]);
  }

  Widget _cardWidget(CardModel c) {
    final selected = connectFrom == c.id;
    return Positioned(
      left: c.x,
      top: c.y,
      child: GestureDetector(
        onTap: () => tapCard(c),
        onPanUpdate: drawMode != null || connecting
            ? null
            : (d) => setState(() {
                  c.x = (c.x + d.delta.dx).clamp(0, 4000 - cardSize.width);
                  c.y = (c.y + d.delta.dy).clamp(0, 4000 - cardSize.height);
                  boardEdited = true;
                }),
        child: Container(
          width: cardSize.width,
          height: cardSize.height,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cardColors[c.color],
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? Colors.blue : Colors.black26, width: selected ? 3 : 1),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(c.type == 'action' ? 'TO DO' : c.type == 'idea' ? 'IDEA' : c.type == 'title' ? 'TITLE' : 'POINT',
                style: const TextStyle(fontSize: 10, letterSpacing: 1)),
            const SizedBox(height: 4),
            Expanded(child: Text(c.text, overflow: TextOverflow.fade)),
          ]),
        ),
      ),
    );
  }
}
