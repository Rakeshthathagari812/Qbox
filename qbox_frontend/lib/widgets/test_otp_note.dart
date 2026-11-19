import 'package:flutter/material.dart';

/// Shows the OTP on screen while the backend is in test mode (no SMS
/// provider yet). Disappears on its own once real SMS is switched on,
/// because the backend stops sending the code to the app.
class TestOtpNote extends StatelessWidget {
  const TestOtpNote({required this.code, super.key});

  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('test-otp-note'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4DB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF5D58A)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.science_outlined, size: 16, color: Color(0xFF8A5A00)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Test mode OTP: $code',
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF8A5A00),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
