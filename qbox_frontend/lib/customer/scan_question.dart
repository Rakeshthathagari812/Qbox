import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_client.dart';
import '../services/app_services.dart';
import '../udhaar/udhaar_models.dart';
import '../udhaar/udhaar_widgets.dart';
import 'transaction_models.dart';

/// Asks "Did the payment go through?" after another app was opened. Yes adds it
/// to the history. Returns the message to show (null = not answered; it is
/// asked again in Pay to Shop).
Future<String?> askScanQuestion(BuildContext context, AppServices app, ScanQuestion question) async {
  final answer = await showDialog<({int? paise})>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _QuestionDialog(question: question),
  );
  if (answer == null) return null;
  return answerScanQuestion(app, question, answer.paise);
}

/// [paise] null = not paid.
Future<String> answerScanQuestion(AppServices app, ScanQuestion question, int? paise) async {
  try {
    await app.transactions.answer(question, amountPaise: paise);
    return paise == null ? 'Not paid. Nothing was added.' : 'Added to your history.';
  } on ApiException catch (e) {
    return e.message;
  }
}

class _QuestionDialog extends StatefulWidget {
  const _QuestionDialog({required this.question});

  final ScanQuestion question;

  @override
  State<_QuestionDialog> createState() => _QuestionDialogState();
}

class _QuestionDialogState extends State<_QuestionDialog> {
  final _amount = TextEditingController();
  String? _error;

  int? get _known => widget.question.amountPaise;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _yes() {
    final paise = _known ?? parsePaise(_amount.text);
    if (paise == null || paise < 100 || paise > 100000000) {
      setState(() => _error = 'Enter the amount you paid');
    } else {
      Navigator.of(context).pop((paise: paise));
    }
  }

  @override
  Widget build(BuildContext context) {
    final known = _known;
    return AlertDialog(
      title: const Text('Did the payment go through?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            known == null ? 'To ${widget.question.title}.' : '${rupees(known)} to ${widget.question.title}.',
            style: udText(14),
          ),
          if (known == null)
            TextField(
              key: const Key('scan-amount'),
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              style: udText(24, weight: FontWeight.w800),
              decoration: InputDecoration(prefixText: '₹ ', errorText: _error),
            ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('scan-no'),
          onPressed: () => Navigator.of(context).pop((paise: null)),
          child: const Text('No'),
        ),
        FilledButton(
          key: const Key('scan-yes'),
          onPressed: _yes,
          style: FilledButton.styleFrom(backgroundColor: udPaid),
          child: const Text('Yes, I paid'),
        ),
      ],
    );
  }
}
