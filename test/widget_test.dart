import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wawacell_flutter/ble_connection.dart';
import 'package:wawacell_flutter/force_format.dart';
import 'package:wawacell_flutter/main.dart';

void main() {
  test('formats force values like the reference application', () {
    expect(formatForceValue(null), '');
    expect(formatForceValue(double.nan), '');
    expect(formatForceValue(0), '!0.00');
    expect(formatForceValue(5.238), '!5.24');
    expect(formatForceValue(0.007), '!0.01');
    expect(formatForceValue(-0.006), '-0.01');
    expect(formatForceValue(-0.002), '!0.00');
    expect(formatForceValue(1.2), '!1.20');
    expect(formatForceValue(-0.2), '-0.20');
    expect(formatForceValue(-0.5), '-0.50');
    expect(formatForceValue(-0.51), '-0.51');
    expect(formatForceValue(99.991), '99.99');
    expect(formatForceValue(100), '99.99');
    expect(formatForceValue(-10), '-9.99');
    expect(formatForceValue(23.4, unit: 'kg'), '!!23');
    expect(formatForceValue(-0.3, unit: 'kg'), '!!!0');
    expect(formatForceValue(23, unit: 'Lb'), '!!24');
    expect(formatForceValue(22, unit: 'Lb'), '!!22');
    expect(formatForceValue(-0.3, unit: 'Lb'), '!!!0');
  });

  test('decodes little-endian float measurements', () {
    expect(
      decodeLoadCellMeasurement(Uint8List.fromList([0x00, 0x00, 0xA0, 0x3F])),
      1.25,
    );
    expect(
      () => decodeLoadCellMeasurement(Uint8List.fromList([0x00, 0x00])),
      throwsFormatException,
    );
  });

  testWidgets('shows the tabbed WawaCell live panel', (tester) async {
    await tester.pumpWidget(const WawaCellApp());

    void expectEqualSpacing(List<double> gaps) {
      final expectedGap = gaps.first;
      for (final gap in gaps.skip(1)) {
        expect(gap, closeTo(expectedGap, 0.1));
      }
    }

    expect(find.text('LIVE'), findsOneWidget);
    expect(find.text('PEAK'), findsOneWidget);
    expect(find.text('GRAPH'), findsOneWidget);
    expect(find.text('SETTINGS'), findsOneWidget);
    expect(find.text('BLE STATUS'), findsOneWidget);
    expect(find.text('DISCONNECTED'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('header-bluetooth-card')),
        matching: find.byType(Icon),
      ),
      findsNothing,
    );
    expect(find.text('RELATIVE FORCE'), findsOneWidget);
    expect(find.text('RELATIVE ZERO'), findsOneWidget);
    expect(find.text('ABSOLUTE FORCE'), findsOneWidget);
    expect(find.text('UNITS  kN'), findsNothing);
    expect(find.text('SAMPLE RATE  100 Hz'), findsNothing);
    expect(find.byKey(const ValueKey('header-units-card')), findsNothing);
    expect(find.byKey(const ValueKey('header-sample-rate-card')), findsNothing);
    expect(find.text('8.8.8.8.'), findsAtLeastNWidgets(1));
    for (final backingText in tester.widgetList<Text>(find.text('8.8.8.8.'))) {
      expect(backingText.style?.shadows, isEmpty);
    }
    final activeForceText = tester.widget<Text>(
      find
          .byWidgetPredicate(
            (widget) =>
                widget is Text &&
                widget.style?.fontFamily == 'DSEG7' &&
                widget.style?.color == const Color(0xFF35BFF2),
          )
          .first,
    );
    expect(activeForceText.style?.shadows?.single.blurRadius, 6);
    expect(tester.widget<Icon>(find.byIcon(Icons.sensors)).shadows, isNotEmpty);
    expect(
      tester.getTopLeft(find.byType(TabBar)).dy,
      greaterThan(tester.getTopLeft(find.byType(TabBarView)).dy),
    );
    final headerCards = [
      tester.getRect(find.byKey(const ValueKey('header-bluetooth-card'))),
      tester.getRect(find.byKey(const ValueKey('header-unit-card'))),
      tester.getRect(find.byKey(const ValueKey('header-zero-card'))),
    ];
    for (var index = 1; index < headerCards.length; index++) {
      expect(
        headerCards[index].left,
        greaterThan(headerCards[index - 1].right),
      );
    }
    expect(find.text('UNIT'), findsOneWidget);
    expect(find.text('kN'), findsOneWidget);
    expect(find.text('ZERO'), findsOneWidget);
    expect(find.text('REL'), findsOneWidget);
    expect(find.text('TAP TO CONNECT'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('header-unit-card')));
    await tester.pumpAndSettle();
    expect(find.text('kg'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('header-unit-card')));
    await tester.pumpAndSettle();
    expect(find.text('Lb'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('header-unit-card')));
    await tester.pumpAndSettle();
    expect(find.text('kN'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('header-zero-card')));
    await tester.pumpAndSettle();
    expect(find.text('ABS'), findsOneWidget);
    expect(find.text('ABSOLUTE FORCE'), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('header-zero-card')));
    await tester.pumpAndSettle();
    expect(find.text('REL'), findsOneWidget);

    final liveArea = tester.getRect(
      find.byKey(const ValueKey('live-panel-area')),
    );
    final liveHeader = tester.getRect(
      find.byKey(const ValueKey('live-header-panel')),
    );
    final liveMain = tester.getRect(
      find.byKey(const ValueKey('live-main-panel')),
    );
    final liveFooter = tester.getRect(
      find.byKey(const ValueKey('live-footer-panels')),
    );
    final liveZero = tester.getRect(
      find.byKey(const ValueKey('live-zero-panel')),
    );
    final liveSecondary = tester.getRect(
      find.byKey(const ValueKey('live-secondary-panel')),
    );
    final liveForceHeading = tester.getRect(find.text('RELATIVE FORCE').first);
    final liveForcePanel = tester.getRect(
      find.byKey(const ValueKey('live-main-panel')),
    );
    expect(liveForceHeading.top, lessThan(liveForcePanel.center.dy));
    final liveMainDigits = tester.widget<Transform>(
      find.byKey(const ValueKey('live-main-force-digits')),
    );
    expect(liveMainDigits.transform.getTranslation().y, lessThan(0));
    final mainFontSize = tester
        .widget<Text>(
          find.descendant(
            of: find.byKey(const ValueKey('live-main-panel')),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Text &&
                  widget.style?.fontFamily == 'DSEG7' &&
                  widget.style?.color == const Color(0xFF35BFF2),
            ),
          ),
        )
        .style!
        .fontSize!;
    final liveSecondaryDigits = tester.widgetList<Text>(
      find.descendant(
        of: find.byKey(const ValueKey('live-footer-panels')),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Text &&
              widget.style?.fontFamily == 'DSEG7' &&
              widget.style?.color == const Color(0xFFE6EDF5),
        ),
      ),
    );
    expect(liveSecondaryDigits, hasLength(2));
    expect(
      liveSecondaryDigits.every(
        (text) => (text.style?.fontSize ?? 0) == mainFontSize / 2,
      ),
      isTrue,
    );
    expect(
      tester.getTopLeft(find.text('RELATIVE ZERO').last).dy,
      greaterThan(liveMain.bottom),
    );
    expect(
      tester.getTopLeft(find.text('ABSOLUTE FORCE').last).dy,
      greaterThan(liveMain.bottom),
    );

    expectEqualSpacing([
      liveHeader.left - liveArea.left,
      liveHeader.top - liveArea.top,
      liveArea.right - liveHeader.right,
      liveArea.bottom - liveFooter.bottom,
      liveMain.top - liveHeader.bottom,
      liveFooter.top - liveMain.bottom,
      liveZero.right <= liveSecondary.left
          ? liveSecondary.left - liveZero.right
          : liveZero.left - liveSecondary.right,
    ]);
    expect(find.byKey(const ValueKey('live-force-mode-toggle')), findsNothing);
    expect(find.text('REMOVE ZERO'), findsOneWidget);
    expect(find.text('SET AS ZERO'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('live-zero-panel')),
        matching: find.byType(InkWell),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('live-secondary-panel')),
        matching: find.byType(InkWell),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('live-zero-panel')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('live-secondary-panel')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('header-zero-card')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('PEAK'));
    await tester.pumpAndSettle();
    final peakHeader = tester.getRect(
      find.byKey(const ValueKey('peak-header-panel')),
    );
    final peakMaximum = tester.getRect(
      find.byKey(const ValueKey('peak-maximum-panel')),
    );
    final peakMinimum = tester.getRect(
      find.byKey(const ValueKey('peak-minimum-panel')),
    );
    expect(peakMaximum.top, greaterThan(peakHeader.bottom));
    expect(peakMaximum.height, greaterThan(peakHeader.height));
    expect(peakMinimum.height, closeTo(peakMaximum.height, .1));
    expect(peakMaximum.bottom, lessThan(peakMinimum.top));
    expect(peakMaximum.left, closeTo(peakMinimum.left, .1));
    expect(peakMaximum.right, closeTo(peakMinimum.right, .1));
    expect(find.byKey(const ValueKey('peak-force-panel')), findsNothing);
    expect(
      find.byKey(const ValueKey('peak-absolute-maximum-panel')),
      findsNothing,
    );
    expect(find.text('ABSOLUTE PEAK MAXIMUM'), findsOneWidget);
    expect(find.text('ABSOLUTE PEAK MINIMUM'), findsOneWidget);
    expect(find.text('NO PEAK'), findsNWidgets(2));
    expect(find.text('ALERT THRESHOLD'), findsNWidgets(2));
    for (final card in ['maximum', 'minimum']) {
      expect(find.byKey(ValueKey('peak-$card-time-card')), findsOneWidget);
      expect(find.byKey(ValueKey('peak-$card-reset-card')), findsOneWidget);
      expect(find.byKey(ValueKey('peak-$card-threshold-card')), findsOneWidget);
    }
    expect(
      find.byKey(const ValueKey('peak-maximum-threshold-slider')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('peak-minimum-threshold-slider')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('peak-maximum-reset')), findsOneWidget);
    expect(find.byKey(const ValueKey('peak-minimum-reset')), findsOneWidget);
    for (final card in ['maximum', 'minimum']) {
      final peakFontSize = tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(ValueKey('peak-$card-panel')),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Text &&
                    widget.style?.fontFamily == 'DSEG7' &&
                    widget.style?.color == const Color(0xFF35BFF2),
              ),
            ),
          )
          .style!
          .fontSize!;
      expect(peakFontSize, closeTo(mainFontSize, .01));
    }

    await tester.tap(find.byKey(const ValueKey('peak-maximum-reset')));
    await tester.pumpAndSettle();
    expect(find.text('NO PEAK'), findsNWidgets(2));
    await tester.tap(find.byKey(const ValueKey('peak-maximum-alert')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('peak-maximum-alert')))
          .tooltip,
      'Disable alert',
    );
    await tester.enterText(
      find.byKey(const ValueKey('peak-maximum-threshold')),
      '5.25',
    );
    await tester.pump();
    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('peak-maximum-threshold')),
          )
          .controller!
          .text,
      '5.25',
    );
    expect(
      tester
          .widget<Slider>(
            find.byKey(const ValueKey('peak-maximum-threshold-slider')),
          )
          .value,
      5.25,
    );

    await tester.tap(find.byKey(const ValueKey('header-zero-card')));
    await tester.pumpAndSettle();
    expect(find.text('RELATIVE PEAK MAXIMUM'), findsOneWidget);
    expect(find.text('RELATIVE PEAK MINIMUM'), findsOneWidget);
    await tester.tap(find.text('LIVE'));
    await tester.pumpAndSettle();
    expect(find.text('RELATIVE FORCE'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('header-zero-card')));
    await tester.pumpAndSettle();
    expect(find.text('ABSOLUTE FORCE'), findsNWidgets(2));
    await tester.tap(find.text('PEAK'));
    await tester.pumpAndSettle();
    expect(find.text('ABSOLUTE PEAK MINIMUM'), findsOneWidget);

    await tester.tap(find.text('GRAPH'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('graph-header-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('graph-plot-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('force-history-graph')), findsOneWidget);
    expect(find.text('ABSOLUTE FORCE  |  kN'), findsOneWidget);
    expect(find.text('WAITING FOR DATA'), findsOneWidget);
    expect(find.byKey(const ValueKey('graph-record-panel')), findsOneWidget);
    expect(find.byIcon(Icons.fiber_manual_record), findsOneWidget);
    final firstGraphPainter = tester
        .widget<CustomPaint>(find.byKey(const ValueKey('force-history-graph')))
        .painter;
    await tester.pump(const Duration(milliseconds: 20));
    final nextGraphPainter = tester
        .widget<CustomPaint>(find.byKey(const ValueKey('force-history-graph')))
        .painter;
    expect(identical(firstGraphPainter, nextGraphPainter), isFalse);

    await tester.enterText(
      find.byKey(const ValueKey('graph-range-input')),
      '15',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Slider>(find.byKey(const ValueKey('graph-range-slider')))
          .value,
      15,
    );

    await tester.tap(find.text('AUTO'));
    await tester.pumpAndSettle();
    expect(find.text('Auto Record Settings'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('close-auto-settings')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey('auto-settings-opacity')),
          )
          .opacity,
      0,
    );

    await tester.tap(find.byKey(const ValueKey('graph-record-toggle')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('graph-record-toggle')))
          .tooltip,
      'Stop recording',
    );

    await tester.tap(find.text('SETTINGS'));
    await tester.pumpAndSettle();
    expect(find.text('Time format'), findsOneWidget);
    expect(find.text('Date format'), findsOneWidget);
    expect(find.text('Units'), findsOneWidget);
    expect(find.text('Sample rate'), findsOneWidget);

    await tester.tap(find.text('24-hour'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('12-hour').last);
    await tester.pumpAndSettle();
    expect(find.text('12-hour'), findsOneWidget);
  });

  testWidgets('fits the app in a short desktop browser viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(656, 512);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const WawaCellApp());
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('PEAK'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('GRAPH'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
