import 'dart:js_interop';

@JS('voinoWhisper')
external JSObject? get _ns;

@JS('voinoWhisper.supported')
external bool get _supported;

@JS('voinoWhisper.start')
external JSPromise<JSAny?> _start(JSFunction onText, JSFunction onProgress, JSFunction onError);

@JS('voinoWhisper.stop')
external JSPromise<JSAny?> _stop();

/// Whisper tiny (multilingual) running in the browser (see web/whisper.js).
class WhisperEngine {
  static bool get supported => _ns != null && _supported;

  static Future<void> start({
    required void Function(String text) onText,
    required void Function(int percent) onProgress,
    required void Function(String message) onError,
  }) async {
    await _start(
      ((JSString t) => onText(t.toDart)).toJS,
      ((JSNumber p) => onProgress(p.toDartInt)).toJS,
      ((JSString m) => onError(m.toDart)).toJS,
    ).toDart;
  }

  static Future<void> stop() async {
    await _stop().toDart;
  }
}
