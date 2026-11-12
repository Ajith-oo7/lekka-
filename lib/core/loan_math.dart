import '../data/models.dart';

/// How a loan is doing, for the status pill and the Summary counts.
enum LoanStatus { onTrack, dueSoon, overdue, paid }

/// "Due soon" means the due date is today or within this many days.
/// Matches the first reminder in Phase 5 (2 days before).
const dueSoonDays = 2;

LoanStatus loanStatus({required DateTime? nextDueDate, required int outstandingPaise, DateTime? now}) {
  if (outstandingPaise <= 0) return LoanStatus.paid;
  if (nextDueDate == null) return LoanStatus.onTrack;
  final day = now ?? today();
  // Compare as UTC calendar dates so a daylight-saving change can't shift the count.
  final daysLeft = DateTime.utc(nextDueDate.year, nextDueDate.month, nextDueDate.day)
      .difference(DateTime.utc(day.year, day.month, day.day))
      .inDays;
  if (daysLeft < 0) return LoanStatus.overdue;
  if (daysLeft <= dueSoonDays) return LoanStatus.dueSoon;
  return LoanStatus.onTrack;
}

/// Roughly how much interest 30 days add at today's balance and terms.
/// Only for the summary card. The real amounts come from the daily server
/// job (Phase 3), which is what Records shows.
///
/// interest = balance × rate_bps / 10000 × 30 / period_days, rounded half up,
/// in integers only.
int monthlyInterestEstimate(int outstandingPaise, LoanTerms? terms) {
  if (terms == null || outstandingPaise <= 0 || terms.rateBps == 0) return 0;
  final numerator = outstandingPaise * terms.rateBps * 30;
  final denominator = 10000 * terms.ratePeriod.days;
  return (numerator * 2 + denominator) ~/ (denominator * 2);
}
