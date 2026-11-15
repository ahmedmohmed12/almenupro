import 'package:flutter/foundation.dart';

/// Notifies P&L widgets when expenses are created or deleted
/// so totals update without rebuilding the whole admin page.
class ExpenseLedgerService extends ChangeNotifier {
  ExpenseLedgerService._();

  static final ExpenseLedgerService instance = ExpenseLedgerService._();

  void notifyChanged() => notifyListeners();
}
