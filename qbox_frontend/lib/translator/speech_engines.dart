import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

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
class SmartVoiceInput implements VoiceInput, VoiceGuesses, VoiceWarmUp {
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
  static const _trust = Duration(minutes: 5);

  VoiceInput? _active;

  @override
  List<String> get guesses {
    final active = _active;
    return active is VoiceGuesses ? (active as VoiceGuesses).guesses : const [];
  }

  /// Asks now whether the server is up, so Speak does not have to wait for it.
  @override
  Future<void> warmUp({String localeId = 'en_IN'}) async {
    if (!localeId.toLowerCase().startsWith('en')) await _serverReady();
  }

  @override
  Future<String> listen({
    required void Function(String words) onWords,
    String localeId = 'en_IN',
    VoicePace pace = const VoicePace(),
    void Function()? onReady,
  }) async {
    final english = localeId.toLowerCase().startsWith('en');
    if (english || !await _serverReady()) {
      return (_active = phone).listen(onWords: onWords, localeId: localeId, pace: pace, onReady: onReady);
    }
    try {
      return await (_active = server).listen(onWords: onWords, localeId: localeId, pace: pace, onReady: onReady);
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
    if (checked != null && _serverUp && _clock().difference(checked) < _trust) {
      // It was up a little while ago: start at once, and ask meanwhile.
      _checkedAt = _clock();
      unawaited(language.isOnline().then((up) => _serverUp = up));
      return true;
    }
    _serverUp = await language.isOnline();
    _checkedAt = _clock();
    return _serverUp;
  }
}

/// The microphone, as raw 16 kHz mono 16-bit sound.
abstract class MicStream {
  Future<bool> hasPermission();

  Future<Stream<Uint8List>> start();

  Future<void> stop();
}

class RecorderMic implements MicStream {
  final AudioRecorder _recorder = AudioRecorder();

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<Stream<Uint8List>> start() => _recorder.startStream(
    const RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: IndicVoiceInput.sampleRate,
      numChannels: 1,
      // The phone's own clean-up: less shop noise, soft voices made louder.
      noiseSuppress: true,
      autoGain: true,
    ),
  );

  @override
  Future<void> stop() async {
    await _recorder.stop();
  }
}

/// Hears what is said until the person stops talking; the QBOX server writes it
/// out. Nothing is saved on the phone.
///
/// The server is asked at the first short quiet, before it is sure that the
/// person has finished: the answer is then ready when it is sure. If they go on
/// speaking, that answer is thrown away.
class IndicVoiceInput implements VoiceInput {
  IndicVoiceInput(this._api, {MicStream? mic}) : _mic = mic ?? RecorderMic();

  final LanguageApi _api;
  final MicStream _mic;
  Completer<void>? _done;

  static const sampleRate = 16000;
  static const _quietAfterSpeech = Duration(milliseconds: 1100);
  static const _waitForSpeech = Duration(seconds: 8);
  static const _longest = Duration(seconds: 25);

  /// Quiet for this long: the answer is asked for already.
  static const _early = Duration(milliseconds: 450);

  /// 100 ms of sound.
  static const _frame = sampleRate ~/ 10 * 2;

  @override
  Future<String> listen({
    required void Function(String words) onWords,
    String localeId = 'en_IN',
    VoicePace pace = const VoicePace(),
    void Function()? onReady,
  }) async {
    if (!await _mic.hasPermission()) {
      throw const VoiceException('Allow microphone access for QBOX in phone settings.');
    }
    final Stream<Uint8List> sound;
    try {
      sound = await _mic.start();
    } catch (_) {
      throw const VoiceException('The microphone is busy. Try again in a moment.');
    }

    final language = localeId.split('_').first;
    final ear = SpeechEnd(quietAfterSpeech: pace.serverPause, waitForSpeech: pace.waitForSpeech, longest: pace.longest);
    final heard = BytesBuilder(copy: false);
    final done = _done = Completer<void>();
    void end() {
      if (!done.isCompleted) done.complete();
    }

    // Even if the sound stops coming.
    final limit = Timer(pace.longest + const Duration(seconds: 1), end);
    var ready = false;
    var rest = Uint8List(0);
    var frames = 0;
    Future<String>? early;
    Duration? earlyFor;
    var asking = false;

    Future<String> ask() => _api.speechToText(
      base64Encode(wavOf(heard.toBytes(), sampleRate)),
      language: language,
      samplingRate: sampleRate,
    );

    final listening = sound.listen((bytes) {
      if (done.isCompleted) return;
      if (!ready) {
        ready = true;
        onReady?.call();
      }
      heard.add(Uint8List.fromList(bytes));
      final all = Uint8List.fromList([...rest, ...bytes]);
      var at = 0;
      for (; at + _frame <= all.length; at += _frame) {
        frames++;
        final time = Duration(milliseconds: 100 * frames);
        if (ear.hear(loudness(all, at, at + _frame), time)) {
          end();
          return;
        }
        final last = ear.lastSpeech;
        if (last != null && !asking && earlyFor != last && time - last >= _early && pace.serverPause > _early) {
          earlyFor = last;
          asking = true;
          early = ask().whenComplete(() => asking = false);
          early!.ignore(); // looked at below
        }
      }
      rest = all.sublist(at);
    }, onError: (_) => end(), onDone: end);

    await done.future;
    limit.cancel();
    await listening.cancel();
    try {
      await _mic.stop();
    } catch (_) {}
    if (!ear.heardSpeech) return '';

    onWords('…'); // the screen shows that it is now working it out
    try {
      var text = '';
      if (early != null && earlyFor == ear.lastSpeech) text = await early!.catchError((_) => '');
      // Not asked yet, or that was too little to hear.
      if (text.isEmpty) text = await ask();
      if (text.isNotEmpty) onWords(text);
      return text;
    } on ApiException catch (e) {
      if (e.code == 'NETWORK' || e.code == 'LANGUAGE_OFF') throw const VoiceServerUnavailable();
      throw VoiceException(e.message);
    }
  }

  @override
  Future<void> stop() async {
    final done = _done;
    if (done != null && !done.isCompleted) done.complete();
  }
}

/// The loudest moment in [bytes] (16-bit sound) from [from] to [to], in decibels.
double loudness(Uint8List bytes, int from, int to) {
  final data = ByteData.sublistView(bytes);
  var peak = 0;
  for (var i = from; i + 1 < to; i += 2) {
    final v = data.getInt16(i, Endian.little).abs();
    if (v > peak) peak = v;
  }
  return peak == 0 ? -160 : 20 * math.log(peak / 32767) / math.ln10;
}

/// [pcm] (16-bit mono) as a WAV file.
Uint8List wavOf(Uint8List pcm, int rate) {
  final head = ByteData(44);
  void text(int at, String s) {
    for (var i = 0; i < s.length; i++) {
      head.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  text(0, 'RIFF');
  head.setUint32(4, 36 + pcm.length, Endian.little);
  text(8, 'WAVEfmt ');
  head
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, rate, Endian.little)
    ..setUint32(28, rate * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little);
  text(36, 'data');
  head.setUint32(40, pcm.length, Endian.little);
  return Uint8List.fromList([...head.buffer.asUint8List(), ...pcm]);
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

  /// The last few seconds, oldest first.
  final List<({Duration at, double db})> _recent = [];

  /// Everything clearly louder than the room since speech began.
  final List<double> _speech = [];
  int _loudInARow = 0;
  Duration? _lastSpeech;

  bool get heardSpeech => _lastSpeech != null;

  /// When the voice was last heard.
  Duration? get lastSpeech => _lastSpeech;

  /// Speech must be this much louder than the room (dB).
  static const _above = 10.0;

  /// The phone answers this (or near it) while the microphone is not giving
  /// sound yet. It is not a quiet room.
  static const _noSound = -90.0;
  static const _remember = Duration(seconds: 3);

  /// Feed one loudness reading; true = stop recording now.
  bool hear(double db, Duration at) {
    if (!db.isNaN && db > _noSound) _read(math.min(db, 0), at);
    final last = _lastSpeech;
    if (last != null && at - last > quietAfterSpeech) return true;
    if (last == null && at > waitForSpeech) return true;
    return at > longest;
  }

  void _read(double db, Duration at) {
    _recent
      ..removeWhere((r) => at - r.at > _remember)
      ..add((at: at, db: db));
    // The quietest moment of the last seconds: speech always has gaps. It can go
    // up again, as when the phone makes a quiet room louder by itself.
    final room = _recent.map((r) => r.db).reduce(math.min);

    if (_lastSpeech == null) {
      if (db > math.max(room + _above, -50)) {
        // Two readings in a row (~200 ms) = speech, not a click or a tap.
        if (++_loudInARow >= 2) {
          _lastSpeech = at;
          _speech.add(db);
        }
      } else {
        _loudInARow = 0;
      }
      return;
    }

    if (db > room + _above) _speech.add(db);
    final loud = _usualSpeech();
    // Nearer the voice than the room, not just above the room.
    final threshold = math.max(room + math.max(_above, (loud - room) * 0.45), -50);
    if (db > threshold && !_steady(at, loud)) _lastSpeech = at;
  }

  /// How loud the voice usually is (one bang does not change it).
  double _usualSpeech() {
    final sorted = List.of(_speech)..sort();
    return sorted[(sorted.length - 1) * 8 ~/ 10];
  }

  /// A fan or traffic stays level; a voice goes up and down. Level and below
  /// the voice for a second is not the voice.
  bool _steady(Duration at, double loud) {
    const second = Duration(milliseconds: 1000);
    final last = _recent.where((r) => at - r.at <= second).map((r) => r.db).toList();
    if (last.length < 8) return false;
    final high = last.reduce(math.max);
    return high - last.reduce(math.min) <= 6 && high < loud - 5;
  }
}
