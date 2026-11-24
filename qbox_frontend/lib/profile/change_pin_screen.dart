import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_client.dart';
import '../services/app_services.dart';
import '../udhaar/udhaar_widgets.dart';

/// Change the login PIN. Closes with true when it changed.
class ChangePinScreen extends StatefulWidget {
  const ChangePinScreen({super.key});

  @override
  State<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends State<ChangePinScreen> {
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _again = TextEditingController();
  String? _oldError;
  String? _newError;
  String? _againError;
  bool _busy = false;

  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    _again.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _oldError = _old.text.length == 4 ? null : 'Enter your old PIN';
      _newError = _new.text.length == 4 ? null : 'Enter a 4-digit PIN';
      _againError = _again.text == _new.text ? null : 'PINs do not match';
    });
    if (_oldError != null || _newError != null || _againError != null) return;
    final services = ServicesScope.of(context);
    setState(() => _busy = true);
    try {
      final token = await services.profile.changePin(_old.text, _new.text);
      await services.session.saveToken(token);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        if (e.code == 'WRONG_PIN' || e.code == 'ACCOUNT_LOCKED') {
          _oldError = e.message;
        } else {
          _newError = e.message;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(title: 'Change PIN', subtitle: 'Your other phones will be logged out', busy: _busy),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  UdCard(
                    child: Column(
                      children: [
                        _field('pin-old', 'Old PIN', _old, _oldError, focus: true),
                        _field('pin-new', 'New PIN', _new, _newError),
                        _field('pin-again', 'New PIN again', _again, _againError, last: true),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 54,
                    child: FilledButton(
                      key: const Key('pin-save'),
                      onPressed: _busy ? null : _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: udPurple,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        textStyle: udText(17, weight: FontWeight.w700),
                      ),
                      child: const Text('Change PIN'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    String key,
    String label,
    TextEditingController controller,
    String? error, {
    bool focus = false,
    bool last = false,
  }) => TextField(
    key: Key(key),
    controller: controller,
    autofocus: focus,
    obscureText: true,
    enableSuggestions: false,
    autocorrect: false,
    keyboardType: TextInputType.number,
    textInputAction: last ? TextInputAction.done : TextInputAction.next,
    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
    style: udText(20, weight: FontWeight.w700),
    decoration: InputDecoration(labelText: label, errorText: error, errorMaxLines: 3),
    onSubmitted: last ? (_) => _save() : null,
  );
}
