import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Device-local settings. Gemini keys leave the device only in requests to Google.
class Settings {
  Settings({
    this.keys = const [],
    this.useAi = false,
    this.consented = false,
    this.useProxy = false,
    this.proxyConsented = false,
    Future<void> Function(String, String)? write,
  }) : _write =
           write ??
           ((key, value) =>
               const FlutterSecureStorage().write(key: key, value: value));
  List<String> keys;
  bool useAi, consented, useProxy, proxyConsented;
  final Future<void> Function(String, String) _write;
  static const _store = FlutterSecureStorage();

  static Future<Settings> load() async {
    try {
      final k = await _store.read(key: 'gemini_keys') ?? '';
      return Settings(
        keys: k
            .split('\n')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(),
        useAi: await _store.read(key: 'use_ai') == '1',
        consented: await _store.read(key: 'ai_consent') == '1',
        useProxy: await _store.read(key: 'use_proxy') == '1',
        proxyConsented: await _store.read(key: 'proxy_consent') == '1',
      );
    } catch (_) {
      return Settings();
    }
  }

  /// Throws on any failure; caller must not claim that settings persisted.
  Future<void> save() async {
    await _write('gemini_keys', keys.join('\n'));
    await _write('use_ai', useAi ? '1' : '0');
    await _write('ai_consent', consented ? '1' : '0');
    await _write('use_proxy', useProxy ? '1' : '0');
    await _write('proxy_consent', proxyConsented ? '1' : '0');
  }
}
