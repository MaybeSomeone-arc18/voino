import 'package:flutter/foundation.dart';

const proEntitlement = 'voino_pro';

class ProOffer {
  const ProOffer(this.id, this.title, this.price);
  final String id, title, price;
}

abstract class ProBackend {
  Future<void> configure();
  Future<bool> refresh();
  Future<List<ProOffer>> offers();
  Future<bool> purchase(String id);
  Future<bool> restore();
  void listen(void Function(bool) onAccess);
  void dispose();
}

/// Never stores an entitlement boolean as a permanent local unlock.
class ProAccess extends ChangeNotifier {
  ProAccess({required this.android, required this.backend});
  final bool android;
  final ProBackend backend;
  bool active = false, ready = false, busy = false;
  String message = '';
  bool _disposed = false;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool get canUseBoardFiles => !android || active;

  Future<void> init() async {
    if (!android) return;
    busy = true;
    _notify();
    try {
      await backend.configure();
      backend.listen((value) {
        active = value;
        _notify();
      });
      active = await backend.refresh();
      ready = true;
      message =
          'Sandbox only. No real charge. Pro unlocks board JSON save and open.';
    } catch (_) {
      active = false;
      message =
          'Test purchases unavailable. Free notes and board editing still work.';
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> refresh() async {
    if (!android || !ready || busy) return;
    try {
      active = await backend.refresh();
    } catch (_) {
      active = false; // Cannot verify access: fail closed for board files only.
    }
    _notify();
  }

  Future<List<ProOffer>> offers() async {
    if (!ready) return [];
    return backend.offers();
  }

  Future<bool> buy(String id) => _transaction(() => backend.purchase(id));
  Future<bool> restore() => _transaction(backend.restore);

  Future<bool> _transaction(Future<bool> Function() operation) async {
    if (!android || !ready || busy) return false;
    busy = true;
    _notify();
    try {
      active = await operation();
      message = active
          ? 'Test Pro active. Board JSON save and open unlocked.'
          : 'No active voino_pro entitlement. Board files remain locked.';
    } catch (_) {
      // A canceled/failed purchase must not unlock access.
      message = 'Purchase canceled or failed. No new access granted.';
    } finally {
      busy = false;
      _notify();
    }
    return active;
  }

  @override
  void dispose() {
    _disposed = true;
    backend.dispose();
    super.dispose();
  }
}
