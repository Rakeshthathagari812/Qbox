import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'onboarding_draft.dart';
import 'phone_stage.dart';
import 'services/app_services.dart';
import 'startup_gate.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0xFFF4F0FD),
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );
  runApp(QboxApp(services: AppServices.live()));
}

class QboxApp extends StatefulWidget {
  const QboxApp({required this.services, super.key});

  /// The backend connection. Tests pass a fake one.
  final AppServices services;

  @override
  State<QboxApp> createState() => _QboxAppState();
}

class _QboxAppState extends State<QboxApp> {
  final OnboardingDraft _draft = OnboardingDraft();

  @override
  Widget build(BuildContext context) {
    return ServicesScope(
      services: widget.services,
      child: OnboardingScope(
      draft: _draft,
      child: MaterialApp(
        title: 'QBOX',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          fontFamily: 'Poppins',
          scaffoldBackgroundColor: Colors.white,
        ),
        builder: (context, child) {
          return PhoneStage(child: child ?? const SizedBox.shrink());
        },
        home: const StartupGate(),
      ),
      ),
    );
  }
}
