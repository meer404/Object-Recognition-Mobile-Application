import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'accessibility/accessibility_controls.dart';
import 'app/app_theme.dart';
import 'app/sorani_localizations.dart';
import 'app/ui_strings.dart';
import 'debug/speech_probe_screen.dart';

void main() {
  runApp(const KurdishVisionApp());
}

/// Root widget: Sorani locale, RTL, high-contrast theme.
class KurdishVisionApp extends StatelessWidget {
  const KurdishVisionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: UiStrings.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      locale: soraniLocale,
      supportedLocales: const <Locale>[soraniLocale],
      localizationsDelegates: const <LocalizationsDelegate<Object>>[
        ...soraniLocalizationsDelegates,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      // Belt and braces: the UI is RTL even if locale resolution changes.
      builder: (BuildContext context, Widget? child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const _PlaceholderHome(),
    );
  }
}

/// Phase 0 placeholder; replaced by the camera screen in Phase 2.
class _PlaceholderHome extends StatelessWidget {
  const _PlaceholderHome();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AccessibilityControls(
        child: Semantics(
          container: true,
          label: UiStrings.homeSemantics,
          excludeSemantics: true,
          child: Center(
            child: Text(
              UiStrings.preparing,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
        ),
      ),
      // Researcher tool, compiled out of release builds (D-010).
      bottomNavigationBar: kDebugMode
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SpeechProbeScreen(),
                    ),
                  ),
                  child: const Text('Speech probe (debug)'),
                ),
              ),
            )
          : null,
    );
  }
}
