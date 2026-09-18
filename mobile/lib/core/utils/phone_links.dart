import 'package:url_launcher/url_launcher.dart';

/// Digits only; 10-digit local numbers default to India (+91) for this CRM.
String? whatsappNumber(String? mobile) {
  if (mobile == null) return null;
  var digits = mobile.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;
  if (digits.length == 10) digits = '91$digits';
  return digits;
}

Uri? whatsappUri(String? mobile) {
  final n = whatsappNumber(mobile);
  if (n == null) return null;
  return Uri.parse('https://wa.me/$n');
}

Future<void> openWhatsApp(String? mobile) async {
  final uri = whatsappUri(mobile);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<void> openPhoneCall(String? mobile) async {
  if (mobile == null || mobile.trim().isEmpty) return;
  await launchUrl(Uri(scheme: 'tel', path: mobile.trim()));
}
