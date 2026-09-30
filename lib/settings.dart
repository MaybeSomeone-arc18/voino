import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Device-local settings. Gemini keys never leave the device except in requests to Google.
class Settings {
  Settings({this.keys = const [], this.useAi = false, this.consented = false, this.useProxy = false, this.proxyConsented = false});
  List<String> keys;
  bool useAi, consented, useProxy, proxyConsented;

  static const _store = FlutterSecureStorage();

  static Future<Settings> load() async {
    try {
      final k = await _store.read(key: 'gemini_keys') ?? '';
      return Settings(
        keys: k.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
        useAi: await _store.read(key: 'use_ai') == '1',
        consented: await _store.read(key: 'ai_consent') == '1',
        useProxy: await _store.read(key: 'use_proxy') == '1',
        proxyConsented: await _store.read(key: 'proxy_consent') == '1',
      );
    } catch (_) {
      return Settings();
    }
  }

  Future<void> save() async {
    try {
      await _store.write(key: 'gemini_keys', value: keys.join('\n'));
      await _store.write(key: 'use_ai', value: useAi ? '1' : '0');
      await _store.write(key: 'ai_consent', value: consented ? '1' : '0');
      await _store.write(key: 'use_proxy', value: useProxy ? '1' : '0');
      await _store.write(key: 'proxy_consent', value: proxyConsented ? '1' : '0');
    } catch (_) {}
  }
}
