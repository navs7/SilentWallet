import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:silentwallet/screens/amount_pad.dart';

void main() {
  testWidgets('GST key shows the rate and a hint icon inside its corner', (
    t,
  ) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    var rate = 5;
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (c, set) => AmountPad(
              calculator: true,
              rowHeight: 44,
              gstPercent: rate,
              onKey: (_) {},
              onDone: () {},
              onEquals: () {},
              onGst: () {},
              onGstRate: () => set(() => rate = rate == 5 ? 18 : 5),
              onClose: () {},
              onToggleCalculator: () {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('5% GST'), findsOneWidget);
    final key = t.getRect(find.byKey(const Key('pad-gst')));
    final hint = t.getRect(find.byKey(const Key('pad-gst-hint')));
    final label = t.getRect(find.text('5% GST'));
    final box = key.inflate(1);
    expect(box.contains(hint.topLeft) && box.contains(hint.bottomRight), true);
    expect(
      hint.left >= label.right - 1,
      true,
      reason: 'icon must not cover the text',
    );
    await t.longPress(find.byKey(const Key('pad-gst')));
    await t.pump();
    expect(find.text('18% GST'), findsOneWidget);
  });
}
