/// The languages QBOX can hear, translate and speak.
enum AppLanguage {
  english('en', 'English', 'English', 'en_IN', 'en-IN'),
  telugu('te', 'Telugu', 'తెలుగు', 'te_IN', 'te-IN'),
  hindi('hi', 'Hindi', 'हिंदी', 'hi_IN', 'hi-IN'),
  kannada('kn', 'Kannada', 'ಕನ್ನಡ', 'kn_IN', 'kn-IN'),
  tamil('ta', 'Tamil', 'தமிழ்', 'ta_IN', 'ta-IN');

  const AppLanguage(
    this.code,
    this.englishName,
    this.nativeName,
    this.speechLocale,
    this.voiceLocale,
  );

  /// Short code used by the translator ("te").
  final String code;
  final String englishName;

  /// The name written in the language itself, so a speaker can find it.
  final String nativeName;

  /// For the phone's speech recognition ("te_IN").
  final String speechLocale;

  /// For the phone's voice ("te-IN").
  final String voiceLocale;

  /// "తెలుగు (Telugu)", or just "English".
  String get label =>
      this == AppLanguage.english ? englishName : '$nativeName ($englishName)';

  static AppLanguage fromCode(String? code, {AppLanguage fallback = AppLanguage.english}) {
    for (final l in values) {
      if (l.code == code) return l;
    }
    return fallback;
  }
}
