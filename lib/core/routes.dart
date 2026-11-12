/// Route paths.
class Routes {
  static const auth = '/auth';
  static const loans = '/loans';
  static const records = '/records';
  static const reminders = '/reminders';
  static const summary = '/summary';
  static const chits = '/chits';
  static const settings = '/settings';

  // Phase 2. Kept outside '/loans' so they open over the tab bar.
  static const groups = '/groups';
  static const groupPattern = '/group/:id';
  static const newLoanPattern = '/loan/new';
  static const loanPattern = '/loan/:id';

  static String group(String id) => '/group/$id';
  static String loan(String id) => '/loan/$id';
  static const changeTermsPattern = '/loan/:id/terms';
  static String changeTerms(String id) => '/loan/$id/terms';

  /// New loan form, optionally with a group already chosen. [borrowed] opens
  /// it for a loan the person took (solo borrower mode).
  static String newLoan({String? groupId, bool borrowed = false}) {
    final query = [if (groupId != null) 'group=$groupId', if (borrowed) 'side=borrowed'].join('&');
    return query.isEmpty ? newLoanPattern : '$newLoanPattern?$query';
  }

  // Phase 4: join a shared loan with an invite code.
  static const join = '/join';
  static const joinPattern = '/join/:code';
  static String joinWith(String code) => '/join/$code';
}
