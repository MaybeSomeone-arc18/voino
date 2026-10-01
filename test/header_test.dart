import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voino/main.dart';

void main() {
  for (final width in [320.0, 360.0, 390.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('active Android header fits $width at text scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var pro = 0, listen = 0, settings = 0;
        final capture = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            home: RepaintBoundary(
              key: capture,
              child: MediaQuery(
                data: MediaQueryData(
                  size: Size(width, 844),
                  textScaler: TextScaler.linear(scale),
                ),
                child: Scaffold(
                  body: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 8, 0),
                    child: VoinoHeader(
                      android: true,
                      active: true,
                      busy: false,
                      showListen: true,
                      onPro: () => pro++,
                      onListen: () => listen++,
                      onSettings: () => settings++,
                      settingsIcon: Icons.tune,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final label in ['Test Pro active', 'Listen']) {
          final rect = tester.getRect(find.text(label));
          expect(rect.right, lessThanOrEqualTo(width));
          expect(rect.left, greaterThanOrEqualTo(0));
        }
        await tester.tap(find.text('Test Pro active'));
        await tester.tap(find.text('Listen'));
        await tester.tap(find.byTooltip('Gemini settings'));
        expect([pro, listen, settings], [1, 1, 1]);
        if (width == 360 && scale == 1) {
          final boundary =
              capture.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final png = await image.toByteData(format: ui.ImageByteFormat.png);
          print('HEADER_PNG:${base64Encode(png!.buffer.asUint8List())}');
          image.dispose();
        }
      });
    }
  }
}
