import 'package:url_launcher/url_launcher.dart';

/// Digits only; 10-digit local numbers default to India (+91) for this CRM.
String? whatsappNumber(String? mobile) {
  if (mobile == null) return null;
  var digits = mobile.replaceAll(RegExp(r'\\D'), '');
  if (digits.isEmpty) return null;
  if (digits.length == 10) digits = '91$digits';
  return digits;
}

String shreeramAriesWhatsAppMessage(String? customerName) {
  final name = (customerName ?? '').trim();
  final greeting = name.isEmpty ? 'Dear Sir/Madam,' : 'Dear $name,';

  return '''$greeting

Thank you for your interest in Shreeram Aries.

Please find the project details below:

Project Brochure:
https://shreeram-developers.com/shreeramarise/ShreeRamAriesBrochure.pdf

Location:
https://share.google/2WnmUWvPqcofHPZD5

Shreeram Aries
Near SB Party Plot,
New Shahibaug, Nana Chiloda,
Ahmedabad

Contact:
+91 95123 43239 | +91 95123 33239

Website:
https://shreeram-developers.com/

Thank you,
Team Shreeram Developers''';
}

Uri? whatsappUri(String? mobile, {String? message}) {
  final n = whatsappNumber(mobile);
  if (n == null) return null;
  return Uri.https(
    'wa.me',
    '/$n',
    message == null || message.isEmpty ? null : {'text': message},
  );
}

Future<void> openWhatsApp(
  String? mobile, {
  String? customerName,
  String? message,
}) async {
  final text = message ?? shreeramAriesWhatsAppMessage(customerName);
  final uri = whatsappUri(mobile, message: text);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<void> openPhoneCall(String? mobile) async {
  if (mobile == null || mobile.trim().isEmpty) return;
  await launchUrl(Uri(scheme: 'tel', path: mobile.trim()));
}
