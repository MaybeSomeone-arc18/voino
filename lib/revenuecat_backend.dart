import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'pro_access.dart';

/// Public SDK key supplied at build time. Never use a secret API key here.
class RevenueCatBackend implements ProBackend {
  static const sdkKey = String.fromEnvironment('REVENUECAT_TEST_STORE_KEY');
  final Map<String, Package> _packages = {};
  CustomerInfoUpdateListener? _listener;

  bool _active(CustomerInfo info) =>
      info.entitlements.active.containsKey(proEntitlement);

  @override
  Future<void> configure() async {
    // This integration is a debug Android Test Store demo, not production billing.
    if (!kDebugMode || !sdkKey.startsWith('test_')) {
      throw StateError(
        'Build a debug Android APK with a public Test Store SDK key.',
      );
    }
    await Purchases.configure(PurchasesConfiguration(sdkKey));
  }

  @override
  Future<bool> refresh() async {
    await Purchases.invalidateCustomerInfoCache();
    return _active(await Purchases.getCustomerInfo());
  }

  @override
  Future<List<ProOffer>> offers() async {
    final offering = (await Purchases.getOfferings()).current;
    _packages.clear();
    if (offering == null) return [];
    return offering.availablePackages.map((p) {
      _packages[p.identifier] = p;
      return ProOffer(
        p.identifier,
        p.storeProduct.title,
        p.storeProduct.priceString,
      );
    }).toList();
  }

  @override
  Future<bool> purchase(String id) async {
    final package = _packages[id];
    if (package == null) throw StateError('Offering changed. Reload packages.');
    final result = await Purchases.purchase(PurchaseParams.package(package));
    return _active(result.customerInfo);
  }

  @override
  Future<bool> restore() async => _active(await Purchases.restorePurchases());

  @override
  void listen(void Function(bool) onAccess) {
    _listener = (info) => onAccess(_active(info));
    Purchases.addCustomerInfoUpdateListener(_listener!);
  }

  @override
  void dispose() {
    if (_listener != null) {
      Purchases.removeCustomerInfoUpdateListener(_listener!);
    }
  }
}
