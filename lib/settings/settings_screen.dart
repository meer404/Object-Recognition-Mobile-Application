import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import '../app/ui_strings.dart';
import '../debug/speech_probe_screen.dart';

/// Settings. Volume, verbosity and thresholds are added once the features they
/// control can be tried on a device.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Not the default back button: its tooltip would be Arabic (D-004).
        leading: IconButton(
          // On Android, BackButtonIcon labels itself with Flutter's built-in
          // "back", which our ckb fallback serves in Arabic (found on a phone).
          // Excluding it leaves the Sorani tooltip as the only label.
          icon: const ExcludeSemantics(child: BackButtonIcon()),
          tooltip: UiStrings.back,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(UiStrings.settings),
      ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (BuildContext context, Widget? _) => ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            // In every build: measurements must come from profile or release
            // builds (D-021). A labelled switch rather than a hidden gesture, so
            // it works with a screen reader.
            SwitchListTile(
              title: const Text(UiStrings.evaluationMode),
              subtitle: const Text(UiStrings.evaluationModeDetail),
              value: controller.settings.evaluationMode,
              onChanged: (bool on) => controller.updateSettings(
                controller.settings.copyWith(evaluationMode: on),
              ),
            ),
            if (controller.exportMetrics != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: FilledButton(
                  onPressed: () => _export(context),
                  child: const Text(UiStrings.exportMetrics),
                ),
              ),
            const SizedBox(height: 24),
            Text(
              UiStrings.settingsPlaceholder,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ],
        ),
      ),
      // Researcher tools, compiled out of release builds (D-010).
      bottomNavigationBar: kDebugMode
          ? SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  ListenableBuilder(
                    listenable: controller,
                    builder: (BuildContext context, Widget? _) =>
                        SwitchListTile(
                          title: const Text('Detection boxes (debug)'),
                          value: controller.settings.showDebugOverlay,
                          onChanged: (bool on) => controller.updateSettings(
                            controller.settings.copyWith(showDebugOverlay: on),
                          ),
                        ),
                  ),
                  Padding(
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
                ],
              ),
            )
          : null,
    );
  }

  Future<void> _export(BuildContext context) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final bool shared = await controller.exportMetrics!();
    if (!shared) {
      messenger.showSnackBar(
        const SnackBar(content: Text(UiStrings.noMetrics)),
      );
    }
  }
}
