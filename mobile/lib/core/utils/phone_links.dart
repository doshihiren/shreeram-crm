import 'package:url_launcher/url_launcher.dart';

/// Digits only; 10-digit local numbers default to India (+91) for this CRM.
String? whatsappNumber(String? mobile) {
  if (mobile == null) return null;
  var digits = mobile.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;
  if (digits.length == 10) digits = '91$digits';
  return digits;
}

/// Prefilled first WhatsApp message for Shreeram Aries leads.
String whatsappIntroMessage({String? customerName}) {
  final name = (customerName ?? '').trim();
  final greeting = name.isEmpty ? 'Dear Sir/Madam,' : 'Dear $name,';

  return '''
$greeting

Thank you for your interest in Shreeram Aries.

Brochure:
https://shreeram-developers.com/shreeramarise/ShreeRamAriesBrochure.pdf

Website:
https://shreeram-developers.com/

Location:
https://share.google/2WnmUWvPqcofHPZD5

Shreeram Aries,
Near. SB Party Plot,
New Shahibaug, Nana Chiloda,
Ahmedabad

+91 95123 43239 | +91 95123 33239
'''.trim();
}

Uri? whatsappUri(String? mobile, {String? customerName}) {
  final n = whatsappNumber(mobile);
  if (n == null) return null;
  final text = whatsappIntroMessage(customerName: customerName);
  return Uri.parse('https://wa.me/$n?text=${Uri.encodeComponent(text)}');
}

Future<void> openWhatsApp(String? mobile, {String? customerName}) async {
  final uri = whatsappUri(mobile, customerName: customerName);
  if (uri == null) return;
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

Future<void> openPhoneCall(String? mobile) async {
  if (mobile == null || mobile.trim().isEmpty) return;
  await launchUrl(Uri(scheme: 'tel', path: mobile.trim()));
}
