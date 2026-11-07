import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'accessibility/haptics.dart';
import 'app/app_controller.dart';
import 'app/app_theme.dart';
import 'app/camera_screen.dart';
import 'app/sorani_localizations.dart';
import 'app/ui_strings.dart';
import 'camera/camera_frame.dart';
import 'camera/plugin_camera_service.dart';
import 'settings/app_settings.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Portrait only, so left and right in the image match the user's (D-017).
  SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);
  runApp(const KurdishVisionApp(createController: _createController));
}

AppController _createController() {
  const AppSettings settings = AppSettings();
  return AppController(
    camera: PluginCameraService(quality: settings.cameraQuality),
    haptics: const PlatformHaptics(),
    setKeepAwake: (bool enabled) => WakelockPlus.toggle(enable: enabled),
    // Phase 3 connects the detector here.
    onFrame: (CameraFrame frame) async {},
  );
}

/// Root widget: Sorani locale, RTL, high-contrast theme.
class KurdishVisionApp extends StatefulWidget {
  const KurdishVisionApp({super.key, required this.createController});

  final AppController Function() createController;

  @override
  State<KurdishVisionApp> createState() => _KurdishVisionAppState();
}

class _KurdishVisionAppState extends State<KurdishVisionApp> {
  late final AppController _controller = widget.createController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

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
      home: CameraScreen(controller: _controller),
    );
  }
}
