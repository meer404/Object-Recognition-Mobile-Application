import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kurdish_vision/app/sorani_localizations.dart';
import 'package:kurdish_vision/app/ui_strings.dart';
import 'package:kurdish_vision/main.dart';

void main() {
  testWidgets('app builds with Sorani locale and RTL direction', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const KurdishVisionApp());
    await tester.pumpAndSettle();

    final BuildContext context = tester.element(find.byType(Scaffold));
    expect(Directionality.of(context), TextDirection.rtl);
    expect(Localizations.localeOf(context), soraniLocale);
    // Framework strings resolve through the ckb → ar fallback delegate.
    expect(MaterialLocalizations.of(context), isNotNull);
  });

  testWidgets('home exposes a Sorani semantics label', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpWidget(const KurdishVisionApp());
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel(UiStrings.homeSemantics), findsOneWidget);
    handle.dispose();
  });

  testWidgets('meets Android tap-target and contrast guidelines', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await tester.pumpWidget(const KurdishVisionApp());
    await tester.pumpAndSettle();

    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(textContrastGuideline));
    handle.dispose();
  });
}
