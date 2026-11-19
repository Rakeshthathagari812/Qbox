import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// A problem with voice, with a message written for the shopkeeper.
class VoiceException implements Exception {
  const VoiceException(this.message);

  final String message;

  @override
  String toString() => 'VoiceException($message)';
}

/// Listens to the microphone and turns speech into text.
abstract class VoiceInput {
  /// Listens until the person stops talking. [onWords] receives the words
  /// heard so far. Returns everything heard (may be empty).
  Future<String> listen({required void Function(String words) onWords});

  /// Stops listening early; [listen] then returns what was heard.
  Future<void> stop();
}

/// Says text out loud.
abstract class Speaker {
  Future<void> say(String text);

  Future<void> stop();
}

/// Uses the phone's own speech recognition (Google on Android), in Indian English.
class DeviceVoiceInput implements VoiceInput {
  final SpeechToText _speech = SpeechToText();
  bool _ready = false;
  Completer<String>? _done;
  String _heard = '';

  @override
  Future<String> listen({required void Function(String words) onWords}) async {
    if (!_ready) {
      try {
        _ready = await _speech.initialize(
          onError: _onError,
          onStatus: _onStatus,
        );
      } catch (_) {
        _ready = false;
      }
      if (!_ready) {
        throw const VoiceException(
          'Voice is not available. Allow microphone access for QBOX in phone settings.',
        );
      }
    }
    _heard = '';
    final done = _done = Completer<String>();
    await _speech.listen(
      onResult: (result) {
        _heard = result.recognizedWords;
        onWords(_heard);
        if (result.finalResult) _finish();
      },
      listenOptions: SpeechListenOptions(
        localeId: 'en_IN',
        listenFor: const Duration(seconds: 20),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
      ),
    );
    return done.future;
  }

  @override
  Future<void> stop() => _speech.stop();

  void _onStatus(String status) {
    if (status == SpeechToText.doneStatus) _finish();
  }

  void _onError(SpeechRecognitionError error) {
    final done = _done;
    if (done == null || done.isCompleted) return;
    final message = switch (error.errorMsg) {
      'error_no_match' ||
      'error_speech_timeout' => null, // heard nothing useful
      'error_network' || 'error_network_timeout' || 'error_server' =>
        'Voice needs internet on this phone. Check your connection and try again.',
      'error_permission' || 'error_insufficient_permissions' =>
        'Allow microphone access for QBOX in phone settings.',
      'error_busy' => 'The microphone is busy. Try again in a moment.',
      _ => 'Could not hear you. Please try again.',
    };
    if (message == null) {
      done.complete(_heard);
    } else {
      done.completeError(VoiceException(message));
    }
  }

  void _finish() {
    final done = _done;
    if (done != null && !done.isCompleted) done.complete(_heard);
  }
}

/// Uses the phone's text-to-speech voice, in Indian English.
class DeviceSpeaker implements Speaker {
  final FlutterTts _tts = FlutterTts();
  bool _ready = false;

  @override
  Future<void> say(String text) async {
    try {
      if (!_ready) {
        final available = await _tts.isLanguageAvailable('en-IN');
        await _tts.setLanguage(available == true ? 'en-IN' : 'en-US');
        await _tts.setSpeechRate(0.5);
        _ready = true;
      }
      await _tts.stop();
      await _tts.speak(text);
    } catch (_) {
      // Speaking is a bonus: never let it break the calculator.
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
