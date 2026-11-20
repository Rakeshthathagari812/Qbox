import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:record/record.dart';

import '../calculator/voice_services.dart';
import '../services/api_client.dart';
import '../services/language_api.dart';

/// The QBOX server could not be reached: say it again (the phone's own speech
/// recognition is then used until the server is back).
class VoiceServerUnavailable extends VoiceException {
  const VoiceServerUnavailable() : super('Could not reach QBOX right now. Tap the mic and say it again.');
}

/// Picks the best way to hear, by itself (nothing to choose, no names shown):
///   * Telugu, Hindi, Kannada, Tamil: the QBOX server's speech model (AI4Bharat
///     IndicConformer, made for Indian languages and accents) when it is reachable;
///   * English, or when the server cannot be reached: the phone's own.
class SmartVoiceInput implements VoiceInput {
  SmartVoiceInput({required this.phone, required this.server, required this.language, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final VoiceInput phone;
  final VoiceInput server;
  final LanguageApi language;
  final DateTime Function() _clock;

  /// The last answer to "is the server up?", kept for a short while.
  DateTime? _checkedAt;
  bool _serverUp = false;
  static const _remember = Duration(seconds: 30);

  VoiceInput? _active;

  @override
  Future<String> listen({required void Function(String words) onWords, String localeId = 'en_IN'}) async {
    final english = localeId.toLowerCase().startsWith('en');
    if (english || !await _serverReady()) {
      return (_active = phone).listen(onWords: onWords, localeId: localeId);
    }
    try {
      return await (_active = server).listen(onWords: onWords, localeId: localeId);
    } on VoiceServerUnavailable {
      _serverUp = false;
      _checkedAt = _clock();
      rethrow;
    }
  }

  @override
  Future<void> stop() async => _active?.stop();

  Future<bool> _serverReady() async {
    final checked = _checkedAt;
    if (checked != null && _clock().difference(checked) < _remember) return _serverUp;
    _serverUp = await language.isOnline();
    _checkedAt = _clock();
    return _serverUp;
  }
}

/// Records what is said (16 kHz mono WAV) until the person stops talking,
/// then the QBOX server writes it out. The recording is deleted straight after.
class IndicVoiceInput implements VoiceInput {
  IndicVoiceInput(this._api);

  final LanguageApi _api;
  final AudioRecorder _recorder = AudioRecorder();
  Completer<void>? _done;

  static const _sampleRate = 16000;
  static const _quietAfterSpeech = Duration(milliseconds: 1400);
  static const _waitForSpeech = Duration(seconds: 8);
  static const _longest = Duration(seconds: 25);

  @override
  Future<String> listen({required void Function(String words) onWords, String localeId = 'en_IN'}) async {
    if (!await _recorder.hasPermission()) {
      throw const VoiceException('Allow microphone access for QBOX in phone settings.');
    }
    final path = '${Directory.systemTemp.path}/qbox_voice_${DateTime.now().millisecondsSinceEpoch}.wav';
    try {
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: _sampleRate,
          numChannels: 1,
          // The phone's own clean-up: less shop noise, soft voices made louder.
          noiseSuppress: true,
          autoGain: true,
        ),
        path: path,
      );
    } catch (_) {
      throw const VoiceException('The microphone is busy. Try again in a moment.');
    }

    final started = DateTime.now();
    final ear = SpeechEnd();
    final done = _done = Completer<void>();
    final listening = _recorder.onAmplitudeChanged(const Duration(milliseconds: 100)).listen((a) {
      if (ear.hear(a.current, DateTime.now().difference(started)) && !done.isCompleted) done.complete();
    });
    await done.future;
    await listening.cancel();
    final saved = await _recorder.stop();
    final file = File(saved ?? path);
    if (!ear.heardSpeech) {
      _delete(file);
      return '';
    }

    onWords('…'); // the screen shows that it is now working it out
    try {
      final audio = base64Encode(await file.readAsBytes());
      final text = await _api.speechToText(audio, language: localeId.split('_').first, samplingRate: _sampleRate);
      if (text.isNotEmpty) onWords(text);
      return text;
    } on ApiException catch (e) {
      if (e.code == 'NETWORK' || e.code == 'LANGUAGE_OFF') throw const VoiceServerUnavailable();
      throw VoiceException(e.message);
    } finally {
      _delete(file);
    }
  }

  @override
  Future<void> stop() async {
    final done = _done;
    if (done != null && !done.isCompleted) done.complete();
  }

  /// Recordings never stay on the phone.
  static void _delete(File file) {
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }
}

/// Decides when someone has finished speaking, from the microphone loudness
/// (decibels, about every 100 ms).
///
/// It learns how loud the room is (a busy shop or a quiet home), counts as
/// speech only what is clearly louder than that, and stops after a short quiet
/// once the person has spoken.
class SpeechEnd {
  SpeechEnd({
    this.quietAfterSpeech = IndicVoiceInput._quietAfterSpeech,
    this.waitForSpeech = IndicVoiceInput._waitForSpeech,
    this.longest = IndicVoiceInput._longest,
  });

  final Duration quietAfterSpeech;
  final Duration waitForSpeech;
  final Duration longest;

  /// The room's background loudness (slowly follows the quietest moments).
  double _room = -50;
  bool _roomKnown = false;
  int _loudInARow = 0;
  Duration? _lastSpeech;

  bool get heardSpeech => _lastSpeech != null;

  /// Speech must be this much louder than the room (dB).
  static const _above = 10.0;

  /// Feed one loudness reading; true = stop recording now.
  bool hear(double db, Duration at) {
    if (db.isNaN || db.isInfinite) db = -60;
    db = db.clamp(-60.0, 0.0);
    if (!_roomKnown) {
      _room = db;
      _roomKnown = true;
    } else if (db < _room) {
      _room = db; // quieter than we thought: that is the room
    } else if (_lastSpeech == null || db < _room + _above) {
      _room += (db - _room) * 0.02; // the room may get noisier: follow slowly
    }

    final threshold = math.max(_room + _above, -48.0);
    if (db > threshold) {
      _loudInARow++;
      // Two readings in a row (~200 ms) = speech, not a click or a tap.
      if (_loudInARow >= 2 || _lastSpeech != null) _lastSpeech = at;
    } else {
      _loudInARow = 0;
    }

    final last = _lastSpeech;
    if (last != null && at - last > quietAfterSpeech) return true;
    if (last == null && at > waitForSpeech) return true;
    return at > longest;
  }
}
