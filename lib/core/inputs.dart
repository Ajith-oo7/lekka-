import 'package:flutter/services.dart';

/// Lets the person type an amount or a rate: digits, one dot, at most two
/// decimals (₹500.50, 10.25%). Anything else is ignored as they type.
class DecimalInputFormatter extends TextInputFormatter {
  static final _pattern = RegExp(r'^\d{0,12}(\.\d{0,2})?$');

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return _pattern.hasMatch(newValue.text) ? newValue : oldValue;
  }
}
