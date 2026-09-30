import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'board.dart';
import 'board_controller.dart';
import 'board_view.dart';
import 'gemini.dart';
import 'settings.dart';
import 'whisper_stub.dart' if (dart.library.js_interop) 'whisper_web.dart';
import 'logic.dart';
import 'live_transcript.dart';

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
  bool speechReady = false, listening = false, busy = false;
  Settings settings = Settings();
  String engine = 'device'; // device | whisper (web only)
  String micNote = '';
  String view = 'listen'; // listen | notes | board
  String summary = '', noteSource = '';
  String before = '', lastSource = '', status = idleStatus;
  final board = BoardController();
  List<CardModel> get cards => board.cards;
  List<Link> get links => board.links;
  List<ShapeModel> get shapes => board.shapes;
  bool get boardEdited => board.edited;

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
        .then((ok) => setState(() {
              speechReady = ok;
              if (!ok && WhisperEngine.supported) engine = 'whisper'; // no device recognizer: use Whisper
            }));
  }

  void _msg(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> toggleWhisper() async {
    if (listening) {
      setState(() => micNote = 'Finishing transcription...');
      await WhisperEngine.stop();
      setState(() {
        listening = false;
        micNote = '';
      });
      generate(manual: false);
      return;
    }
    setState(() {
      listening = true;
      micNote = 'Loading speech model...';
    });
    try {
      await WhisperEngine.start(
        onText: (t) {
          final clean = cleanWhisperText(t);
          if (clean.isNotEmpty && mounted) setState(() => transcript.text = stitchSpeech(transcript.text, clean));
        },
        onProgress: (p) {
          if (mounted) setState(() => micNote = p >= 100 ? 'Listening (Whisper)...' : 'Downloading speech model $p% (first time only)');
        },
        onError: (m) => _msg(m),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          listening = false;
          micNote = '';
        });
        _msg('Whisper could not start: $e. Try Device speech or type instead.');
      }
    }
  }

  Future<void> toggleListen() async {
    if (engine == 'whisper') return toggleWhisper();
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
    var useKeys = settings.useAi && settings.keys.isNotEmpty;
    var useProxy = settings.useProxy && defaultProxyUrl() != null;
    if (useKeys && !settings.consented) {
      if (await confirm('Send this transcript to Google Gemini using your API key to write a summary? '
          'It leaves your device. Choose Cancel to skip it.')) {
        settings.consented = true;
        await settings.save();
      } else {
        useKeys = false;
      }
    }
    if (useProxy && !settings.proxyConsented) {
      if (await confirm('Send this transcript to the Voino server, which forwards it to Google Gemini to write a summary? '
          'It leaves your device; the server does not keep it. Choose Cancel to skip it.')) {
        settings.proxyConsented = true;
        await settings.save();
      } else {
        useProxy = false;
      }
    }
    Note n;
    var how = 'Rule-based extract';
    if (useKeys || useProxy) {
      setState(() {
        busy = true;
        status = 'Summarizing with AI...';
      });
      final r = await summarizeWithFallback(src, title.text,
          keys: settings.keys, useKeys: useKeys, useProxy: useProxy, proxyUrl: defaultProxyUrl());
      n = r.note;
      how = r.how;
      if (mounted) setState(() => busy = false);
    } else {
      n = makeNotes(src, title.text);
    }
    _apply(n, src, how);
  }

  void _apply(Note n, String src, String how) {
    board.replace(buildBoard(n));
    setState(() {
      summary = n.summary;
      noteSource = how;
      lastSource = src;
      status = '${cards.length} editable ${cards.length == 1 ? 'card' : 'cards'} made from your transcript. $how.';
      view = 'notes';
    });
  }

  Future<void> clearAll() async {
    if (!await confirm('Clear everything: transcript, notes, board and drawings? Download first if you want to keep them.')) return;
    if (listening) {
      if (engine == 'whisper') {
        await WhisperEngine.stop();
      } else {
        await speech.cancel();
      }
    }
    board.clear();
    setState(() {
      title.clear();
      transcript.clear();
      before = '';
      summary = '';
      noteSource = '';
      busy = false;
      lastSource = '';
      listening = false;
      micNote = '';
      status = idleStatus;
      view = 'listen';
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

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width > 800;
    final capture = _panel('01 / CAPTURE', 'Listen to the discussion', [
      TextField(
          controller: title,
          decoration: const InputDecoration(labelText: 'Give it a name', border: OutlineInputBorder())),
      if (kIsWeb && WhisperEngine.supported) ...[
        const SizedBox(height: 12),
        SegmentedButton<String>(
          segments: [
            const ButtonSegment(value: 'whisper', label: Text('Whisper (local)')),
            ButtonSegment(value: 'device', label: const Text('Device speech'), enabled: speechReady),
          ],
          selected: {engine},
          onSelectionChanged: listening ? null : (v) => setState(() => engine = v.first),
        ),
      ],
      const SizedBox(height: 12),
      Row(children: [
        FilledButton.icon(
          onPressed: (engine == 'whisper' ? WhisperEngine.supported : speechReady) ? toggleListen : null,
          icon: Icon(listening ? Icons.stop : Icons.mic),
          label: Text(listening ? 'Stop listening' : (transcript.text.isEmpty ? 'Start speaking' : 'Continue listening')),
        ),
        const SizedBox(width: 12),
        Expanded(
            child: Text(
                micNote.isNotEmpty
                    ? micNote
                    : (engine == 'whisper' || speechReady)
                        ? (listening ? 'Listening for words...' : 'Speech available')
                        : 'Type / paste mode (speech unavailable)',
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
        OutlinedButton(onPressed: downloadBoard, child: const Text('Download board JSON')),
        OutlinedButton(onPressed: openBoardFile, child: const Text('Open board file')),
        OutlinedButton(onPressed: importBoard, child: const Text('Paste board JSON')),
      ]),
      const SizedBox(height: 8),
      const Text('Check notes against the transcript. Rule-based notes are extracts, not a summary. Guest session: nothing is saved.',
          style: TextStyle(fontSize: 11)),
    ]);
    return Scaffold(
      backgroundColor: paper,
      body: Stack(children: [
        Positioned.fill(child: SvgPicture.asset('assets/voino_bg.svg', fit: BoxFit.cover, alignment: Alignment.topCenter)),
        if (view != 'listen') Positioned.fill(child: ColoredBox(color: paper.withValues(alpha: 0.86))),
        SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 8, 0),
            child: Row(children: [
              SvgPicture.asset('assets/logo/voino-logo.svg', height: 26, semanticsLabel: 'Voino logo'),
              const SizedBox(width: 10),
              const Text('voino', style: TextStyle(fontSize: 18, letterSpacing: 4, fontWeight: FontWeight.w300, color: ink)),
              const Spacer(),
              if (view != 'listen')
                TextButton(onPressed: () => setState(() => view = 'listen'), child: const Text('Listen', style: TextStyle(color: ink))),
              IconButton(
                  tooltip: 'Gemini settings',
                  icon: Icon((settings.useAi && settings.keys.isNotEmpty) || settings.useProxy ? Icons.auto_awesome : Icons.tune,
                      color: ink, size: 20),
                  onPressed: openSettings),
            ]),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              child: view == 'listen'
                  ? KeyedSubtree(key: const ValueKey('listen'), child: _listenView())
                  : KeyedSubtree(
                      key: ValueKey(view),
                      child: ListView(padding: const EdgeInsets.all(16), children: [
                        _tabs(),
                        const SizedBox(height: 16),
                        if (view == 'board')
                          _boardSection()
                        else if (wide)
                          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Expanded(child: capture),
                            const SizedBox(width: 16),
                            Expanded(child: notes),
                          ])
                        else ...[notes, const SizedBox(height: 16), capture],
                      ])),
            ),
          ),
        ]),
      ),
      ]),
    );
  }

  static const paper = Color(0xFFF4EEE1), ink = Color(0xFF2B2A28), gold = Color(0xFFC4903F);

  Widget _tabs() => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        for (final t in const [['notes', 'Notes'], ['board', 'Board']])
          TextButton(
            onPressed: () => setState(() => view = t[0]),
            child: Text(t[1],
                style: TextStyle(
                    color: view == t[0] ? ink : Colors.black45,
                    fontWeight: view == t[0] ? FontWeight.w600 : FontWeight.w400,
                    letterSpacing: 1.5)),
          ),
      ]);

  Widget _listenView() {
    final canListen = engine == 'whisper' ? WhisperEngine.supported : speechReady;
    return Column(children: [
      Expanded(
        child: Stack(alignment: Alignment.center, children: [
          Positioned(
            top: 24,
            left: 32,
            right: 32,
            child: Text(
                'Turn conversations\ninto clarity.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 30,
                    height: 1.25,
                    fontWeight: FontWeight.w300,
                    color: ink,
                    shadows: [for (var k = 0; k < 3; k++) Shadow(color: paper, blurRadius: 14)])),
          ),
        ]),
      ),
      Container(
        decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [paper.withValues(alpha: 0), paper.withValues(alpha: 0.92)], stops: const [0, 0.35])),
        padding: const EdgeInsets.fromLTRB(24, 40, 24, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (listening) ...[
            LiveTranscript(text: transcript.text),
            const SizedBox(height: 18),
          ],
          GestureDetector(
            onTap: canListen ? toggleListen : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: listening ? 88 : 76,
              height: listening ? 88 : 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: listening ? gold : ink,
                boxShadow: [BoxShadow(color: (listening ? gold : ink).withValues(alpha: 0.3), blurRadius: listening ? 32 : 16)],
              ),
              child: Icon(listening ? Icons.pause : Icons.mic_none, color: paper, size: 34),
            ),
          ),
          const SizedBox(height: 10),
          Text(
              micNote.isNotEmpty
                  ? micNote
                  : busy
                      ? 'Making sense of it...'
                      : listening
                          ? 'Listening · tap to pause'
                          : !canListen
                              ? 'Speech unavailable · type instead'
                              : transcript.text.isEmpty
                                  ? 'Start listening'
                                  : 'Continue listening',
              style: const TextStyle(fontSize: 12, letterSpacing: 1.2, color: ink)),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            TextButton(
                onPressed: () => setState(() => view = 'notes'),
                child: const Text('Type instead', style: TextStyle(fontSize: 12, color: Colors.black54))),
            if (transcript.text.trim().isNotEmpty) ...[
              TextButton(
                  onPressed: busy ? null : generate,
                  child: const Text('Done', style: TextStyle(fontSize: 12, color: Colors.black54))),
              TextButton(
                  onPressed: clearAll, child: const Text('Clear', style: TextStyle(fontSize: 12, color: Colors.black54))),
            ],
          ]),
        ]),
      ),
    ]);
  }

  Future<void> downloadBoard() async {
    if (cards.isEmpty && shapes.isEmpty) return _msg('Nothing on the board to download yet.');
    try {
      final name = title.text.trim().isEmpty ? 'voino-board' : title.text.trim().replaceAll(RegExp(r'[^A-Za-z0-9-]+'), '-');
      await FileSaver.instance.saveFile(
          name: name, bytes: Uint8List.fromList(utf8.encode(boardJson())), fileExtension: 'json', mimeType: MimeType.json);
      _msg('Board saved. Anyone can open it with Open board file.');
    } catch (e) {
      _msg('Could not save the file ($e). Use Copy board JSON instead.');
    }
  }

  Future<void> openBoardFile() async {
    try {
      final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
      if (files.isEmpty) return;
      final bytes = await files.first.readAsBytes();
      if (bytes.length > 2 * 1024 * 1024) return _msg('That file is too large to be a Voino board.');
      await _loadBoard(utf8.decode(bytes, allowMalformed: true));
    } catch (e) {
      _msg('Could not open the file ($e). Try Import board JSON and paste it instead.');
    }
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
    await _loadBoard(raw);
  }

  Future<void> _loadBoard(String raw) async {
    final r = parseBoardJson(raw);
    if (r == null) return _msg('That is not a valid Voino board.');
    if ((cards.isNotEmpty || shapes.isNotEmpty) && boardEdited && !await confirm('Replace your current board with the imported one?')) return;
    board.replace(r.board);
    setState(() {
      if (r.title.isNotEmpty) title.text = r.title;
      if (r.transcript.isNotEmpty) transcript.text = r.transcript;
      summary = '';
      noteSource = 'Imported board';
      status = '${cards.length} cards imported. Everything is editable.';
    });
  }

  Future<void> openSettings() async {
    final keys = TextEditingController(text: settings.keys.join('\n'));
    var use = settings.useAi;
    var proxy = settings.useProxy;
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
              if (defaultProxyUrl() != null)
                SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Use Voino\'s hosted summarizer'),
                    subtitle: const Text('No key needed. Sends the transcript to the Voino server, which forwards it to Gemini. Rate limited; used after your own keys.', style: TextStyle(fontSize: 11)),
                    value: proxy,
                    onChanged: (v) => setD(() => proxy = v)),
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
                setState(() {
                  settings.keys = [];
                  settings.useAi = false;
                  settings.consented = false;
                });
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
                  settings.useProxy = proxy;
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

  Widget _boardSection() => BoardPanel(controller: board, onSave: downloadBoard, onOpen: openBoardFile);
}
