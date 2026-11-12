import 'package:flutter_test/flutter_test.dart';
import 'package:lekka/core/loan_math.dart';
import 'package:lekka/core/money.dart';
import 'package:lekka/data/models.dart';

LoanTerms terms(int bps, RatePeriod period) => LoanTerms(
      id: 't',
      loanId: 'l',
      version: 1,
      rateBps: bps,
      ratePeriod: period,
      interestType: InterestType.simple,
      lateRateBps: 0,
      graceDays: 0,
      createdAt: DateTime(2026, 11, 4),
    );

void main() {
  group('parseHundredths', () {
    test('rupees to paise', () {
      expect(parseHundredths('500'), 50000);
      expect(parseHundredths('500.5'), 50050);
      expect(parseHundredths('500.05'), 50005);
      expect(parseHundredths('500.'), 50000);
      expect(parseHundredths('12,34,567.75'), 123456775);
    });
    test('percent to basis points', () {
      expect(parseHundredths('10'), 1000);
      expect(parseHundredths('2.5'), 250);
      expect(parseHundredths('0'), 0);
    });
    test('rejects bad input', () {
      expect(parseHundredths(''), isNull);
      expect(parseHundredths('abc'), isNull);
      expect(parseHundredths('1.234'), isNull);
      expect(parseHundredths('-5'), isNull);
    });
  });

  test('formatPercent', () {
    expect(formatPercent(1000), '10%');
    expect(formatPercent(1050), '10.5%');
    expect(formatPercent(1025), '10.25%');
    expect(formatPercent(5), '0.05%');
  });

  group('monthlyInterestEstimate', () {
    test('₹500 at 10% per month is ₹50', () {
      expect(monthlyInterestEstimate(50000, terms(1000, RatePeriod.month)), 5000);
    });
    test('per year uses 365 days', () {
      // ₹1,000 at 12% a year: 100000 × 0.12 × 30/365 = 986.3 paise → 986
      expect(monthlyInterestEstimate(100000, terms(1200, RatePeriod.year)), 986);
    });
    test('zero cases', () {
      expect(monthlyInterestEstimate(0, terms(1000, RatePeriod.month)), 0);
      expect(monthlyInterestEstimate(50000, null), 0);
    });
  });

  group('loanStatus', () {
    final now = DateTime(2026, 11, 4);
    LoanStatus s(DateTime? due, [int balance = 50000]) =>
        loanStatus(nextDueDate: due, outstandingPaise: balance, now: now);

    test('paid when balance is zero', () => expect(s(DateTime(2026, 1, 1), 0), LoanStatus.paid));
    test('overdue after the due date', () => expect(s(DateTime(2026, 11, 3)), LoanStatus.overdue));
    test('due soon on the day and up to 2 days before', () {
      expect(s(DateTime(2026, 11, 4)), LoanStatus.dueSoon);
      expect(s(DateTime(2026, 11, 6)), LoanStatus.dueSoon);
    });
    test('on track further out', () => expect(s(DateTime(2026, 11, 7)), LoanStatus.onTrack));
  });
}
