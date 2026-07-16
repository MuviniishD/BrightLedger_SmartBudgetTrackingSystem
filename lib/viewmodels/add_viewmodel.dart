import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../services/ocr_service.dart';
import '../models/expense_model.dart';
import '../models/budget_model.dart';

class AddViewModel extends ChangeNotifier {
  final FirestoreService _firestoreService;

  List<BudgetModel> budgets = [];
  bool isLoading = false;
  bool isSavingBudgets = false;
  String? error;

  /// Populated by OcrService when a receipt is scanned from the Home screen.
  /// AddScreen consumes and clears this after pre-filling its fields.
  OcrResult? pendingOcr;

  void setOcrResult(OcrResult result) {
    pendingOcr = result;
    notifyListeners();
  }

  void clearOcrResult() {
    pendingOcr = null;
    notifyListeners();
  }

  AddViewModel(this._firestoreService);

  /// Load budgets for the user
  Future<void> loadBudgets(String userId) async {
    isLoading = true;
    notifyListeners();

    try {
      budgets = await _firestoreService.getBudgets(userId);
    } catch (e) {
      error = 'Failed to load budgets.';
    }

    isLoading = false;
    notifyListeners();
  }

  /// Save a new expense/income record only
  Future<bool> saveRecord(ExpenseModel record) async {
    isLoading = true;
    error = null;
    notifyListeners();

    try {
      await _firestoreService.addRecord(record);
      isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('saveRecord error: $e');
      error = 'Failed to save record.';
      isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Save budget allocations only (batch update)
  Future<bool> saveBudgets(
      String userId, Map<String, String> categoryAmounts) async {
    isSavingBudgets = true;
    error = null;
    notifyListeners();

    bool allSuccess = true;
    for (var b in budgets) {
      final text = categoryAmounts[b.category];
      if (text == null) continue;
      final double? newAmount = double.tryParse(text);
      if (newAmount != null && newAmount != b.allocatedAmount) {
        try {
          await _firestoreService.updateBudget(b.id!, newAmount);
          final idx = budgets.indexWhere((x) => x.id == b.id);
          if (idx != -1) {
            budgets[idx] = BudgetModel(
              id: b.id,
              userId: b.userId,
              category: b.category,
              allocatedAmount: newAmount,
            );
          }
        } catch (e) {
          debugPrint('saveBudgets error for ${b.category}: $e');
          allSuccess = false;
        }
      }
    }

    isSavingBudgets = false;
    notifyListeners();
    return allSuccess;
  }
}
