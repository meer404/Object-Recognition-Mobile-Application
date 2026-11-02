import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Sorani Kurdish locale used throughout the app.
const Locale soraniLocale = Locale('ckb');

/// Flutter 3.41 ships no `ckb` Material/Cupertino/Widgets localizations
/// (verified against the SDK's flutter_localizations/lib/src/l10n). These
/// delegates serve the Arabic (`ar`) built-in strings for `ckb`. Arabic shares
/// the script and RTL direction, so widgets lay out correctly.
///
/// Limitation: built-in framework strings (e.g. a back-button tooltip) are
/// Arabic, not Sorani. All app-owned strings come from ui_strings.dart.
/// See docs/decisions.md (D-004).
const Locale _fallbackLocale = Locale('ar');

const List<LocalizationsDelegate<Object>> soraniLocalizationsDelegates =
    <LocalizationsDelegate<Object>>[
      _SoraniMaterialDelegate(),
      _SoraniCupertinoDelegate(),
      _SoraniWidgetsDelegate(),
    ];

bool _isSorani(Locale locale) =>
    locale.languageCode == soraniLocale.languageCode;

class _SoraniMaterialDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const _SoraniMaterialDelegate();

  @override
  bool isSupported(Locale locale) => _isSorani(locale);

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      GlobalMaterialLocalizations.delegate.load(_fallbackLocale);

  @override
  bool shouldReload(_SoraniMaterialDelegate old) => false;
}

class _SoraniCupertinoDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  const _SoraniCupertinoDelegate();

  @override
  bool isSupported(Locale locale) => _isSorani(locale);

  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      GlobalCupertinoLocalizations.delegate.load(_fallbackLocale);

  @override
  bool shouldReload(_SoraniCupertinoDelegate old) => false;
}

class _SoraniWidgetsDelegate
    extends LocalizationsDelegate<WidgetsLocalizations> {
  const _SoraniWidgetsDelegate();

  @override
  bool isSupported(Locale locale) => _isSorani(locale);

  @override
  Future<WidgetsLocalizations> load(Locale locale) =>
      GlobalWidgetsLocalizations.delegate.load(_fallbackLocale);

  @override
  bool shouldReload(_SoraniWidgetsDelegate old) => false;
}
