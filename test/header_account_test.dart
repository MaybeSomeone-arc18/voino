import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voino/main.dart';

// Header sign-in/account button states for Google sign-in + saved boards.
void main() {
  Widget host(VoinoHeader header) => MaterialApp(
    home: Scaffold(body: Center(child: header)),
  );

  VoinoHeader header({
    bool signedIn = false,
    bool authBusy = false,
    VoidCallback? onAccount,
    VoidCallback? onBoards,
  }) => VoinoHeader(
    android: false,
    active: true,
    busy: false,
    showListen: false,
    onPro: () {},
    onListen: () {},
    onSettings: () {},
    settingsIcon: Icons.tune,
    signedIn: signedIn,
    authBusy: authBusy,
    onAccount: onAccount,
    onBoards: onBoards,
  );

  testWidgets('signed-out web header shows a working Sign in, no Boards', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      host(header(onAccount: () => taps++, onBoards: null)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Account'), findsNothing);
    expect(find.text('Boards'), findsNothing);
    await tester.tap(find.text('Sign in'));
    expect(taps, 1);
  });

  testWidgets('auth busy disables the Sign in button', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      host(header(authBusy: true, onAccount: () => taps++)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign in'), warnIfMissed: false);
    expect(taps, 0);
  });

  testWidgets('signed-in header shows Boards and Account', (tester) async {
    var boards = 0, account = 0;
    await tester.pumpWidget(
      host(
        header(
          signedIn: true,
          onAccount: () => account++,
          onBoards: () => boards++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Boards'), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Sign in'), findsNothing);
    await tester.tap(find.text('Boards'));
    await tester.tap(find.text('Account'));
    expect([boards, account], [1, 1]);
  });
}
