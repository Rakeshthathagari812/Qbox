import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Keeps the calculator's history, GT, memory and sound setting on the phone,
/// so they are still there after the app is closed. Cleared on log out.
abstract class CalculatorStore {
  Future<Map<String, dynamic>?> load();

  Future<void> save(Map<String, dynamic> data);

  Future<void> clear();
}

class PrefsCalculatorStore implements CalculatorStore {
  static const _key = 'qbox_calculator';

  @override
  Future<Map<String, dynamic>?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final text = prefs.getString(_key);
      if (text == null) return null;
      final data = jsonDecode(text);
      return data is Map<String, dynamic> ? data : null;
    } catch (_) {
      return null; // damaged data: start fresh rather than crash
    }
  }

  @override
  Future<void> save(Map<String, dynamic> data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(data));
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}

/// Keeps everything in memory only. Used by tests.
class MemoryCalculatorStore implements CalculatorStore {
  Map<String, dynamic>? data;

  @override
  Future<Map<String, dynamic>?> load() async => data == null
      ? null
      : jsonDecode(jsonEncode(data)) as Map<String, dynamic>;

  @override
  Future<void> save(Map<String, dynamic> value) async =>
      data = jsonDecode(jsonEncode(value)) as Map<String, dynamic>;

  @override
  Future<void> clear() async => data = null;
}
