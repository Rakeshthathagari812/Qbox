import 'package:flutter/material.dart';

import '../services/settings_store.dart';
import 'indic_numbers.dart';
import 'language_packs.dart';
import 'languages.dart';
import 'translation_service.dart';

/// One "Speak in" language shared by every voice feature (Udhaar, Calculator,
/// Calendar). Numbers are read on the phone; the rest of the sentence is
/// translated to English (on the QBOX server, or on the phone when offline) and
/// then understood by the same rules as English speech.

const _key = 'voice_lang';
const _oldUdhaarKey = 'udhaar_voice_lang'; // before the setting was shared

Future<AppLanguage> readVoiceLanguage(SettingsStore settings) async =>
    AppLanguage.fromCode(await settings.read(_key) ?? await settings.read(_oldUdhaarKey));

Future<void> saveVoiceLanguage(SettingsStore settings, AppLanguage language) => settings.write(_key, language.code);

/// Lets the user pick the language (saved). The best way to hear it is chosen
/// by itself. Returns the new language, or null if it did not change.
/// No download here: language packs are only fetched when needed offline.
Future<AppLanguage?> pickVoiceLanguage(
  BuildContext context, {
  required AppLanguage current,
  required SettingsStore settings,
  required TextTranslator translator,
}) async {
  const purple = Color(0xFF651CE4);
  const body = Color(0xFF5C5872);
  final picked = await showModalBottomSheet<AppLanguage>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                'Speak in',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Used for voice in Udhaar, Calculator and Calendar.',
                style: TextStyle(fontFamily: 'Poppins', fontSize: 12, color: body),
              ),
            ),
            for (final l in AppLanguage.values)
              ListTile(
                key: Key('voice-lang-${l.code}'),
                leading: Icon(l == current ? Icons.radio_button_checked : Icons.radio_button_off, color: purple),
                title: Text(
                  l.label,
                  style: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600),
                ),
                onTap: () => Navigator.of(context).pop(l),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    ),
  );
  if (picked == null || picked == current) return null;
  await saveVoiceLanguage(settings, picked);
  return picked;
}

/// [words] said in [language], in English. Translates online (IndicTrans2)
/// when possible; offline it uses the phone's pack, asking to download it
/// only then. Null if that was refused or translating failed ([onError]).
Future<String?> voiceToEnglish(
  BuildContext context, {
  required String words,
  required AppLanguage language,
  required TextTranslator translator,
  required void Function(String message) onError,
}) {
  if (language == AppLanguage.english) return Future.value(words);
  return translateWithPacks(
    context,
    translator: translator,
    // Numbers as digits first: translation then cannot change an amount.
    text: numbersToDigits(words, language),
    from: language,
    to: AppLanguage.english,
    onError: onError,
  );
}

/// Translates; if that only failed because an offline pack is missing, offers
/// to download it and tries again. Null when it could not be done.
Future<String?> translateWithPacks(
  BuildContext context, {
  required TextTranslator translator,
  required String text,
  required AppLanguage from,
  required AppLanguage to,
  required void Function(String message) onError,
}) async {
  try {
    return await translator.translate(text, from: from, to: to);
  } on TranslateException catch (e) {
    if (!e.needsPack || !context.mounted) {
      onError(e.message);
      return null;
    }
  }
  if (!await ensureLanguagePacks(context, translator, [from, to])) return null;
  try {
    return await translator.translate(text, from: from, to: to);
  } on TranslateException catch (e) {
    onError(e.message);
    return null;
  }
}

/// The small "Speak in: తెలుగు" button shown next to each voice feature.
class VoiceLanguageChip extends StatelessWidget {
  const VoiceLanguageChip({required this.language, required this.onPressed, super.key});

  final AppLanguage language;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    const purple = Color(0xFF651CE4);
    return ActionChip(
      avatar: const Icon(Icons.translate_rounded, size: 16, color: purple),
      label: Text('Speak in: ${language.nativeName}'),
      labelStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 12, fontWeight: FontWeight.w600, color: purple),
      backgroundColor: Colors.white,
      side: const BorderSide(color: Color(0xFFD9CEF5)),
      onPressed: onPressed,
    );
  }
}
