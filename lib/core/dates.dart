import 'package:intl/intl.dart';

/// Formats a date the Lekka way: 04 Nov 2026.
///
/// [languageCode] is 'en', 'te' or 'hi'. Month names follow the language.
/// The date symbols are loaded by the Flutter localization delegates
/// that MaterialApp sets up, so no extra initialisation is needed in the app.
String formatDate(DateTime date, String languageCode) {
  return DateFormat('dd MMM yyyy', languageCode).format(date);
}
