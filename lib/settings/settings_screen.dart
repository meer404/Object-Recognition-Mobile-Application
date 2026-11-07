import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/ui_strings.dart';
import '../debug/speech_probe_screen.dart';

/// Settings placeholder. Volume, verbosity and thresholds are added once the
/// features they control exist.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Not the default back button: its tooltip would be Arabic (D-004).
        leading: IconButton(
          icon: const BackButtonIcon(),
          tooltip: UiStrings.back,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(UiStrings.settings),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            UiStrings.settingsPlaceholder,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
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
