import 'package:flutter/services.dart';
import 'package:flutter_native_contact_picker/flutter_native_contact_picker.dart';
import 'package:url_launcher/url_launcher.dart';

/// A contact chosen from the phone's address book.
class PickedContact {
  const PickedContact({required this.name, required this.phone});

  final String name;
  final String phone;
}

/// Things the app asks the phone to do: open WhatsApp / SMS / dialer, pick a contact.
abstract class DeviceActions {
  /// QBOX's own page in the phone's settings.
  Future<bool> openAppSettings();

  /// Where the phone's voices are added.
  Future<bool> openVoiceSettings();

  /// How loud the phone speaks, 0 to 100. Null = not known.
  Future<int?> mediaVolume();

  /// Opens [uri] in the right app. False if no app can open it.
  Future<bool> openLink(Uri uri);

  /// Opens the phone's own contact picker. Null if the person cancels.
  /// The phone shows its picker, so QBOX needs no permission to read contacts:
  /// it only receives the one contact the person chose.
  Future<PickedContact?> pickContact();
}

class PhoneDeviceActions implements DeviceActions {
  final _picker = FlutterNativeContactPicker();
  static const _settings = MethodChannel('qbox/settings');

  @override
  Future<bool> openAppSettings() => _open('appSettings');

  @override
  Future<bool> openVoiceSettings() => _open('voiceSettings');

  Future<bool> _open(String page) async {
    try {
      return await _settings.invokeMethod<bool>(page) ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<int?> mediaVolume() async {
    try {
      return await _settings.invokeMethod<int>('mediaVolume');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> openLink(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<PickedContact?> pickContact() async {
    try {
      final contact = await _picker.selectPhoneNumber();
      if (contact == null) return null;
      final phone = contact.selectedPhoneNumber ??
          (contact.phoneNumbers?.isNotEmpty == true ? contact.phoneNumbers!.first : '');
      return PickedContact(name: contact.fullName ?? '', phone: phone);
    } catch (_) {
      return null;
    }
  }
}

/// Opens the chat straight in the WhatsApp app (no web lookup, so no
/// "searching…"), with [text] typed in, ready to send.
Uri whatsAppAppLink(String mobile, String text) => Uri(
  scheme: 'whatsapp',
  host: 'send',
  queryParameters: {'phone': '91$mobile', 'text': text},
);

/// The same chat through the web link; used only if the app link cannot open.
Uri whatsAppLink(String mobile, String text) =>
    Uri.https('wa.me', '/91$mobile', {'text': text});

/// WhatsApp, where the person chooses who gets [text].
Uri whatsAppShareAppLink(String text) =>
    Uri(scheme: 'whatsapp', host: 'send', query: 'text=${Uri.encodeComponent(text)}');

Uri whatsAppShareLink(String text) =>
    Uri(scheme: 'https', host: 'wa.me', path: '/', query: 'text=${Uri.encodeComponent(text)}');

Uri smsLink(String mobile, String text) =>
    Uri(scheme: 'sms', path: '+91$mobile', queryParameters: {'body': text});

Uri callLink(String mobile) => Uri(scheme: 'tel', path: '+91$mobile');
