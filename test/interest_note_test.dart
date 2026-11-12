import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lekka/features/records/records_list.dart' show interestNote;
import 'package:lekka/l10n/app_localizations.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final te = lookupAppLocalizations(const Locale('te'));

  test('regular interest note is rebuilt in the chosen language', () {
    expect(interestNote(en, 'Simple interest 10.00% per month on ₹500'),
        'Simple interest: 10% per month on ₹500');
    expect(interestNote(te, 'Simple interest 10.00% per month on ₹500'),
        'సాధారణ వడ్డీ: ₹500 మీద నెలకు 10%');
  });

  test('late interest note', () {
    expect(interestNote(en, 'Late interest 2.00% per month on ₹513.36'),
        'Late interest: 2% per month on ₹513.36');
  });

  test('other text is left alone', () {
    expect(interestNote(en, 'Loan created'), isNull);
    expect(interestNote(en, null), isNull);
  });
}
