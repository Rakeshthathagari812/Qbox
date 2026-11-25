import 'api_client.dart';

/// Online speech and translation through the QBOX server, which runs AI4Bharat
/// IndicConformer and IndicTrans2 itself. Needs login and internet.
abstract class LanguageApi {
  /// [fast]: a quick answer matters more than fine wording (spoken commands).
  Future<String> translate(String text, {required String from, required String to, bool fast = false});

  /// Words in a 16 kHz mono WAV recording (base64). Empty = nothing heard.
  Future<String> speechToText(String wavBase64, {required String language, int samplingRate = 16000});

  /// Is the QBOX server's speech and translation running and reachable?
  Future<bool> isOnline();
}

class HttpLanguageApi implements LanguageApi {
  HttpLanguageApi(this._api);

  final ApiClient _api;

  /// The AI runs on the server's processor, which can take a few seconds.
  static const _aiTimeout = Duration(seconds: 30);

  @override
  Future<String> translate(String text, {required String from, required String to, bool fast = false}) async {
    final json = await _api.post(
      '/api/language/translate',
      {'text': text, 'source': from, 'target': to, 'fast': fast},
      timeout: _aiTimeout,
    );
    final out = json is Map<String, dynamic> ? json['text'] : null;
    if (out is! String) {
      throw const ApiException('ERROR', 'Something went wrong. Please try again.');
    }
    return out;
  }

  @override
  Future<String> speechToText(String wavBase64, {required String language, int samplingRate = 16000}) async {
    final json = await _api.post(
      '/api/language/speech-to-text',
      {'audio': wavBase64, 'language': language, 'samplingRate': samplingRate},
      timeout: _aiTimeout,
    );
    final out = json is Map<String, dynamic> ? json['text'] : null;
    return out is String ? out : '';
  }

  @override
  Future<bool> isOnline() async {
    try {
      final json = await _api.get('/api/language/status', timeout: const Duration(milliseconds: 1500));
      return json is Map<String, dynamic> && json['online'] == true;
    } on ApiException {
      return false;
    }
  }
}
