import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../models/user_model.dart';
import '../models/budget_model.dart';
import '../models/expense_model.dart';
import '../utils/constants.dart';

/// [HomeViewModel] is responsible for managing the state of the main dashboard.
/// It aggregates data from the user profile, budgets, and transactions, and provides
/// computed properties and formatting for the UI to display.
class HomeViewModel extends ChangeNotifier {
  final FirestoreService _firestoreService;

  // --- State Variables ---
  
  /// The current user's profile data.
  UserModel? user;
  
  /// The user's monthly budget limits.
  List<BudgetModel> budgets = [];
  
  /// A map associating expense categories (keys) with total spent amounts (values).
  Map<String, double> expensesByCategory = {};
  
  /// The sum of all expenses for the current month.
  double totalExpenses = 0;
  
  /// The sum of all recorded income (excluding base salary) for the current month.
  double totalIncome = 0;
  
  /// A dynamically generated piece of financial advice based on current spending.
  String advice = '';
  
  /// Indicates if a data fetch is currently in progress.
  bool isLoading = false;

  /// All income and expense records for the current month.
  /// Used primarily to build the context for the AI Chat.
  List<ExpenseModel> monthRecords = [];

  HomeViewModel(this._firestoreService);

  /// Calculates the total displayable income for the month.
  /// Monthly income = user's base income (from profile) + all income records added this month.
  double get displayMonthlyIncome => (user?.monthlyIncome ?? 0) + totalIncome;

  /// Fetches all necessary data from Firestore for the given [userId] for the current month.
  Future<void> loadData(String userId) async {
    // Notify UI that a fetch has started
    isLoading = true;
    notifyListeners();

    try {
      final now = DateTime.now();
      
      // Fetch user profile and budgets concurrently would be faster, but sequentially is safer
      user = await _firestoreService.getUser(userId);
      budgets = await _firestoreService.getBudgets(userId);
      
      // Fetch all transaction records for the current month
      monthRecords = await _firestoreService.getRecordsByMonth(
          userId, now.year, now.month);
          
      // Fetch aggregated expenses grouped by category
      expensesByCategory = await _firestoreService.getExpensesByCategory(
          userId, now.year, now.month);
          
      // Compute the total expenses
      totalExpenses = expensesByCategory.values.fold(0.0, (a, b) => a + b);
      
      // Compute total dynamic income (excluding base salary)
      totalIncome = await _firestoreService.getTotalIncomeByMonth(
          userId, now.year, now.month);

      // Generate local financial advice based on the fetched data
      final allocations = <String, double>{
        for (var b in budgets) b.category: b.allocatedAmount
      };
      advice = AppConstants.generateAdvice(
        budgetAllocations: allocations,
        expensesByCategory: expensesByCategory,
        monthlyIncome: displayMonthlyIncome,
      );
    } catch (e) {
      debugPrint('HomeViewModel.loadData error: $e');
      advice = 'Unable to load data. Pull to refresh.';
    }

    // Notify UI that fetch is complete
    isLoading = false;
    notifyListeners();
  }

  /// Helper to get the total amount spent for a specific [category].
  /// Returns 0 if no expenses exist for that category.
  double getUsedAmount(String category) =>
      expensesByCategory[category] ?? 0;

  /// Helper to calculate how much budget is remaining for a given [budget].
  double getRemainingAmount(BudgetModel budget) =>
      budget.allocatedAmount - getUsedAmount(budget.category);

  /// Helper to calculate the progress ratio for UI Progress Bars.
  /// Returns a value between 0.0 and 1.0 (can exceed 1.0 if over budget).
  double getProgressRatio(BudgetModel budget) {
    return getUsedAmount(budget.category) / budget.allocatedAmount;
  }
}
