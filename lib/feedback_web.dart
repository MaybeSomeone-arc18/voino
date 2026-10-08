import 'dart:js_interop';

@JS('voinoFeedback')
external void _feedback();

/// Vibrates on Android Chrome, plays a faint click elsewhere (see web/feedback.js).
void switchFeedback() {
  try {
    _feedback();
  } catch (_) {}
}
