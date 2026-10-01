import 'package:flutter_test/flutter_test.dart';
import 'package:voino/pro_access.dart';

class FakeBackend implements ProBackend {
  bool entitled = false, fail = false;
  int configured = 0;
  void Function(bool)? listener;
  @override
  Future<void> configure() async {
    configured++;
    if (fail) throw Exception();
  }

  @override
  Future<bool> refresh() async {
    if (fail) throw Exception();
    return entitled;
  }

  @override
  Future<List<ProOffer>> offers() async => [
    const ProOffer('monthly', 'Monthly', r'$9.99'),
  ];
  @override
  Future<bool> purchase(String id) async {
    if (fail) throw Exception();
    return entitled;
  }

  @override
  Future<bool> restore() async => entitled;
  @override
  void listen(void Function(bool) onAccess) {
    listener = onAccess;
  }

  @override
  void dispose() {
    listener = null;
  }
}

void main() {
  test('web core stays free without configuring native purchases', () async {
    final b = FakeBackend();
    final p = ProAccess(android: false, backend: b);
    await p.init();
    expect(b.configured, 0);
    expect(p.canUseBoardFiles, true);
    p.dispose();
  });
  test(
    'Android files locked until real entitlement response is active',
    () async {
      final b = FakeBackend();
      final p = ProAccess(android: true, backend: b);
      await p.init();
      expect(p.canUseBoardFiles, false);
      await p.buy('monthly');
      expect(p.active, false);
      b.entitled = true;
      await p.buy('monthly');
      expect(p.canUseBoardFiles, true);
      p.dispose();
    },
  );
  test('failure or cancel never grants a new unlock', () async {
    final b = FakeBackend();
    final p = ProAccess(android: true, backend: b);
    await p.init();
    b.fail = true;
    await p.buy('monthly');
    expect(p.active, false);
    expect(p.busy, false);
    p.dispose();
  });
  test(
    'restore and expiry update access without saved local booleans',
    () async {
      final b = FakeBackend();
      final p = ProAccess(android: true, backend: b);
      await p.init();
      b.entitled = true;
      await p.restore();
      expect(p.active, true);
      b.listener!(false);
      expect(p.canUseBoardFiles, false);
      b.entitled = true;
      await p.refresh();
      expect(p.active, true);
      b.fail = true;
      await p.refresh();
      expect(p.active, false);
      p.dispose();
    },
  );
  test(
    'configuration failure leaves free app intact and files locked',
    () async {
      final b = FakeBackend()..fail = true;
      final p = ProAccess(android: true, backend: b);
      await p.init();
      expect(p.ready, false);
      expect(p.canUseBoardFiles, false);
      expect(await p.offers(), isEmpty);
      expect(await p.buy('monthly'), false);
      p.dispose();
    },
  );
}
