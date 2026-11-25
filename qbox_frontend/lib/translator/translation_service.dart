import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import '../services/api_client.dart';
import '../services/language_api.dart';
import 'languages.dart';

/// A problem with translating, with a message written for the user.
class TranslateException implements Exception {
  const TranslateException(this.message, {this.needsPack = false});

  final String message;

  /// True when it would work offline after downloading the language pack.
  final bool needsPack;

  @override
  String toString() => 'TranslateException($message)';
}

/// Translates text between [AppLanguage]s.
abstract class TextTranslator {
  /// True if the language pack for [language] is on the phone.
  Future<bool> isReady(AppLanguage language);

  /// Downloads the language pack (one time, about 30 MB). True if done.
  Future<bool> download(AppLanguage language);

  /// [fast]: a quick answer matters more than fine wording (spoken commands).
  Future<String> translate(String text, {required AppLanguage from, required AppLanguage to, bool fast = false});
}

/// Google ML Kit: translation runs on the phone itself. Free, works without
/// internet once each language pack is downloaded, and nothing said is sent
/// to any server (QBOX's or anyone else's).
class OnDeviceTextTranslator implements TextTranslator {
  final _models = OnDeviceTranslatorModelManager();
  final Map<String, OnDeviceTranslator> _open = {};

  static TranslateLanguage _mlKit(AppLanguage l) => switch (l) {
    AppLanguage.english => TranslateLanguage.english,
    AppLanguage.telugu => TranslateLanguage.telugu,
    AppLanguage.hindi => TranslateLanguage.hindi,
    AppLanguage.kannada => TranslateLanguage.kannada,
    AppLanguage.tamil => TranslateLanguage.tamil,
  };

  @override
  Future<bool> isReady(AppLanguage language) async {
    try {
      return await _models.isModelDownloaded(_mlKit(language).bcpCode);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> download(AppLanguage language) async {
    try {
      return await _models.downloadModel(_mlKit(language).bcpCode, isWifiRequired: false);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String> translate(String text, {required AppLanguage from, required AppLanguage to, bool fast = false}) async {
    if (from == to || text.trim().isEmpty) return text;
    for (final l in {from, to, AppLanguage.english}) {
      if (!await isReady(l)) {
        throw TranslateException(
          'No internet, and the ${l.englishName} offline pack is not downloaded yet.',
          needsPack: true,
        );
      }
    }
    final key = '${from.code}>${to.code}';
    final translator = _open[key] ??= OnDeviceTranslator(
      sourceLanguage: _mlKit(from),
      targetLanguage: _mlKit(to),
    );
    try {
      return await translator.translateText(text);
    } catch (_) {
      throw const TranslateException('Could not translate. Please try again.');
    }
  }
}

/// Online first: IndicTrans2 on the QBOX server, the better translator.
/// When that is not possible (no internet, not running, daily limit,
/// service down) it uses the free on-phone translator, if its packs are there.
/// Language packs are only needed for working offline.
class SmartTextTranslator implements TextTranslator {
  SmartTextTranslator({required this.online, required this.offline, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final LanguageApi online;
  final TextTranslator offline;
  final DateTime Function() _clock;

  /// After the server says online translation is not running (or the limit is
  /// reached), skip asking it for a short while instead of on every sentence.
  DateTime? _skipOnlineUntil;

  /// Where the last translation came from (shown as a small label).
  bool lastWasOnline = false;

  static const _fallBack = {
    'NETWORK', 'LANGUAGE_OFF', 'LANGUAGE_FAILED', 'LANGUAGE_LIMIT', 'LANGUAGE_NOT_SUPPORTED',
  };

  @override
  Future<bool> isReady(AppLanguage language) => offline.isReady(language);

  @override
  Future<bool> download(AppLanguage language) => offline.download(language);

  @override
  Future<String> translate(String text, {required AppLanguage from, required AppLanguage to, bool fast = false}) async {
    if (from == to || text.trim().isEmpty) return text;
    final skip = _skipOnlineUntil;
    if (skip == null || _clock().isAfter(skip)) {
      try {
        final result = await online.translate(text, from: from.code, to: to.code, fast: fast);
        lastWasOnline = true;
        return result;
      } on ApiException catch (e) {
        if (!_fallBack.contains(e.code) && e.status < 500) throw TranslateException(e.message);
        if (e.code == 'LANGUAGE_LIMIT') {
          _skipOnlineUntil = _clock().add(const Duration(minutes: 10));
        } else if (e.code == 'LANGUAGE_OFF') {
          // Our own AI server may be starting: try again soon.
          _skipOnlineUntil = _clock().add(const Duration(minutes: 1));
        }
      }
    }
    final result = await offline.translate(text, from: from, to: to);
    lastWasOnline = false;
    return result;
  }
}
