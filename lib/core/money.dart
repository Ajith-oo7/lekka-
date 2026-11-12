/// Money helpers.
///
/// Money is always whole paise in an `int` (1 rupee = 100 paise).
/// Never use floating point for money anywhere in the app.
library;

/// Formats [paise] as rupees with Indian digit grouping, e.g. 123456700 → ₹12,34,567.
///
/// Paise are shown only when they are not zero (₹500 but ₹500.50),
/// unless [alwaysShowPaise] is true (₹500.00).
String formatRupees(int paise, {bool alwaysShowPaise = false}) {
  final negative = paise < 0;
  final abs = paise.abs();
  final rupees = abs ~/ 100;
  final rest = abs % 100;
  final fraction =
      (alwaysShowPaise || rest != 0) ? '.${rest.toString().padLeft(2, '0')}' : '';
  return '${negative ? '-' : ''}₹${groupIndian(rupees)}$fraction';
}

/// Groups a whole number the Indian way: last three digits, then pairs.
/// 1234567 → 12,34,567. 999 → 999. 1000 → 1,000.
String groupIndian(int number) {
  final digits = number.abs().toString();
  if (digits.length <= 3) return number < 0 ? '-$digits' : digits;

  final lastThree = digits.substring(digits.length - 3);
  var head = digits.substring(0, digits.length - 3);
  final pairs = <String>[];
  while (head.length > 2) {
    pairs.insert(0, head.substring(head.length - 2));
    head = head.substring(0, head.length - 2);
  }
  if (head.isNotEmpty) pairs.insert(0, head);

  final grouped = '${pairs.join(',')},$lastThree';
  return number < 0 ? '-$grouped' : grouped;
}

/// Parses a typed amount like "500", "500.5" or "12,34,567.75" into paise
/// (or a typed rate like "10.25" into basis points: same maths, ×100).
/// Uses only integers. Returns null when the text is not a valid amount.
int? parseHundredths(String input) {
  final text = input.trim().replaceAll(',', '');
  final match = RegExp(r'^(\d{1,12})(?:\.(\d{0,2}))?$').firstMatch(text);
  if (match == null) return null;
  final whole = int.parse(match.group(1)!);
  final fraction = (match.group(2) ?? '').padRight(2, '0');
  return whole * 100 + int.parse(fraction);
}

/// Basis points as a percentage: 1000 → "10%", 1050 → "10.5%", 1025 → "10.25%".
String formatPercent(int bps) {
  final whole = bps ~/ 100;
  final rest = bps % 100;
  if (rest == 0) return '$whole%';
  final fraction = rest.toString().padLeft(2, '0').replaceAll(RegExp(r'0$'), '');
  return '$whole.$fraction%';
}

