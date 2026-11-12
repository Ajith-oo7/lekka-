import 'package:flutter_test/flutter_test.dart';
import 'package:lekka/core/money.dart';
import 'package:lekka/core/widgets.dart' show initials;

void main() {
  group('groupIndian', () {
    test('small numbers are not grouped', () {
      expect(groupIndian(0), '0');
      expect(groupIndian(999), '999');
    });
    test('Indian grouping: last three, then pairs', () {
      expect(groupIndian(1000), '1,000');
      expect(groupIndian(123456), '1,23,456');
      expect(groupIndian(1234567), '12,34,567');
      expect(groupIndian(100000000), '10,00,00,000');
    });
  });

  group('formatRupees (input is paise)', () {
    test('whole rupees', () {
      expect(formatRupees(0), '₹0');
      expect(formatRupees(50000), '₹500');
      expect(formatRupees(123456700), '₹12,34,567');
    });
    test('paise shown only when not zero', () {
      expect(formatRupees(50050), '₹500.50');
      expect(formatRupees(50005), '₹500.05');
      expect(formatRupees(50000, alwaysShowPaise: true), '₹500.00');
    });
    test('negative amounts', () {
      expect(formatRupees(-10000), '-₹100');
    });
  });

  group('initials', () {
    test('two words', () => expect(initials('Bala Krishna'), 'BK'));
    test('one word', () => expect(initials('vasu'), 'V'));
    test('empty', () => expect(initials('  '), '•'));
  });
}
