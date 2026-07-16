import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../services/ai_service.dart';
import '../models/expense_model.dart';
import '../models/budget_model.dart';
import 'package:intl/intl.dart';

/// Defines the three possible viewing modes for the statistics screen.
enum StatsViewMode { expenses, income, both }

/// [StatsViewModel] manages the complex data aggregation required for the charts
/// and insights on the Statistics screen. It leverages both [FirestoreService] for data
/// and [AIService] for intelligent analysis.
class StatsViewModel extends ChangeNotifier {
  final FirestoreService _firestoreService;
  final AIService _aiService = AIService();

  // --- State Variables ---
  
  /// The currently selected month being viewed. Defaults to the current month.
  DateTime selectedMonth = DateTime.now();

  /// Internal cache of all records for the selected month to avoid repeated fetches.
  List<ExpenseModel> _monthRecords = [];

  // --- Processed Data for Charts ---
  
  /// Expenses grouped by category (for Expense Pie Chart)
  Map<String, double> monthlyByCategory = {};
  
  /// Income grouped by category (for Income Pie Chart)
  Map<String, double> monthlyIncomeByCategory = {};
  
  /// Expenses grouped by week (W1–W4) for the Bar Chart
  List<Map<String, double>> weeklyData = []; 
  
  /// Income grouped by week (W1–W4) for the Bar Chart
  List<Map<String, double>> weeklyIncomeData = []; 
  
  /// Total numerical expenses for the selected month
  double totalMonthlyExpenses = 0;
  
  /// Total numerical income for the selected month
  double totalMonthlyIncome = 0;

  // --- AI State Variables ---
  
  /// The generated text summary/tips from Gemini.
  String aiInsights = '';
  
  /// Indicates if Gemini is currently generating insights.
  bool isAnalyzing = false;
  
  /// The structured AI result used to override local charts if available.
  AIAnalysisResult? aiResult;

  // Budgets loaded alongside stats specifically to provide context to the AI.
  List<BudgetModel> _budgets = [];

  /// The current toggle state (Expenses vs Income vs Both).
  StatsViewMode viewMode = StatsViewMode.expenses;
  
  /// Indicates if local Firestore data is currently being fetched.
  bool isLoading = false;

  StatsViewModel(this._firestoreService);

  /// Generates a list of the past 6 months (including the current month)
  /// for the month selector dropdown in the UI.
  List<DateTime> getPast6Months() {
    final now = DateTime.now();
    return List.generate(6, (i) {
      return DateTime(now.year, now.month - i, 1);
    });
  }

  /// Switches the view mode (e.g. from expenses to income) and triggers a UI rebuild.
  void setViewMode(StatsViewMode mode) {
    viewMode = mode;
    notifyListeners();
  }

  /// Updates the selected month, clears previous data, and reloads new stats.
  Future<void> selectMonth(DateTime month, String userId) async {
    selectedMonth = month;
    aiInsights = ''; // clear previous AI insights when month changes
    aiResult = null; // reset to local calculations
    notifyListeners();
    await loadStats(userId);
  }

  /// Fetches raw transaction data for the selected month and processes it into
  /// the maps and lists required by the pie and bar charts.
  Future<void> loadStats(String userId) async {
    isLoading = true;
    aiResult = null; // reset to local calculations when reloading
    notifyListeners();

    try {
      final year = selectedMonth.year;
      final month = selectedMonth.month;

      // Fetch base data
      _monthRecords =
          await _firestoreService.getRecordsByMonth(userId, year, month);
      _budgets = await _firestoreService.getBudgets(userId);

      // Filter to only records up to today if selected month is current month.
      // E.g., don't show future projected dates if the user accidentally added them.
      final now = DateTime.now();
      final isCurrentMonth = year == now.year && month == now.month;
      final cutoff = isCurrentMonth
          ? now
          : DateTime(year, month + 1, 0, 23, 59, 59);

      final relevantRecords =
          _monthRecords.where((r) => !r.date.isAfter(cutoff)).toList();

      // --- Process Expenses by category ---
      monthlyByCategory = {};
      for (var r in relevantRecords) {
        if (!r.isIncome) {
          monthlyByCategory[r.category] =
              (monthlyByCategory[r.category] ?? 0) + r.amount;
        }
      }

      // --- Process Income by category ---
      monthlyIncomeByCategory = {};
      for (var r in relevantRecords) {
        if (r.isIncome) {
          monthlyIncomeByCategory[r.category] =
              (monthlyIncomeByCategory[r.category] ?? 0) + r.amount;
        }
      }

      // Calculate totals
      totalMonthlyExpenses =
          monthlyByCategory.values.fold(0.0, (a, b) => a + b);
      totalMonthlyIncome =
          monthlyIncomeByCategory.values.fold(0.0, (a, b) => a + b);

      // --- Process Weekly breakdown ---
      weeklyData = _calculateWeeklyData(relevantRecords, false, cutoff);
      weeklyIncomeData = _calculateWeeklyData(relevantRecords, true, cutoff);
    } catch (e) {
      debugPrint('StatsViewModel.loadStats error: $e');
      // Reset variables gracefully on error
      monthlyByCategory = {};
      monthlyIncomeByCategory = {};
      weeklyData = [];
      weeklyIncomeData = [];
      totalMonthlyExpenses = 0;
      totalMonthlyIncome = 0;
    }

    isLoading = false;
    notifyListeners();
  }

  /// Leverages [AIService] (Gemini) to analyze the loaded month's data.
  /// If successful, it replaces the local chart calculations with AI-structured chart data.
  Future<void> generateAIInsights() async {
    isAnalyzing = true;
    aiInsights = '';
    aiResult = null;
    notifyListeners();

    // Format month for AI Prompt (e.g. "August 2026")
    final monthLabel =
        DateFormat('MMMM yyyy').format(selectedMonth);

    try {
      // Attempt to get structured charts and insights
      final result = await _aiService.analyzeSpendingWithCharts(
        records: _monthRecords,
        budgets: _budgets,
        month: monthLabel,
      );

      if (result != null) {
        aiResult = result;
        aiInsights = result.insights;
      } else {
        // Fallback to legacy text-only analysis if structured JSON parsing fails
        aiInsights = await _aiService.analyzeSpending(
          expensesByCategory: monthlyByCategory,
          incomeByCategory: monthlyIncomeByCategory,
          budgets: _budgets,
          month: monthLabel,
        );
      }
    } catch (e) {
      debugPrint('Error generating AI insights with charts: $e');
      aiInsights = 'Failed to generate AI insights. Please try again.';
    }

    isAnalyzing = false;
    notifyListeners();
  }

  /// Calculates the number of weeks to display in the bar chart.
  /// Hides future empty weeks if viewing the current month.
  int get visibleWeekCount {
    final now = DateTime.now();
    if (selectedMonth.year == now.year &&
        selectedMonth.month == now.month) {
      int day = now.day;
      if (day <= 7) return 1;
      if (day <= 14) return 2;
      if (day <= 21) return 3;
      return 4;
    }
    // Always show 4 weeks for past months
    return 4;
  }

  /// Computed property providing the correct pie chart data depending on 
  /// whether the AI override exists and which toggle is active.
  Map<String, double> get displayByCategory {
    if (aiResult != null) {
      switch (viewMode) {
        case StatsViewMode.expenses:
          return aiResult!.expensesPie;
        case StatsViewMode.income:
          return aiResult!.incomePie;
        case StatsViewMode.both:
          return aiResult!.bothPie;
      }
    }

    switch (viewMode) {
      case StatsViewMode.expenses:
        return monthlyByCategory;
      case StatsViewMode.income:
        return monthlyIncomeByCategory;
      case StatsViewMode.both:
        return {
          'Expenses': totalMonthlyExpenses,
          'Income': totalMonthlyIncome,
        };
    }
  }

  /// Computed property providing the correct bar chart data depending on 
  /// whether the AI override exists and which toggle is active.
  List<Map<String, double>> get displayWeeklyData {
    if (aiResult != null) {
      switch (viewMode) {
        case StatsViewMode.expenses:
          return List.generate(4, (i) {
            final val = i < aiResult!.expensesWeekly.length ? aiResult!.expensesWeekly[i] : 0.0;
            return {'Expenses': val};
          });
        case StatsViewMode.income:
          return List.generate(4, (i) {
            final val = i < aiResult!.incomeWeekly.length ? aiResult!.incomeWeekly[i] : 0.0;
            return {'Income': val};
          });
        case StatsViewMode.both:
          return List.generate(4, (i) {
            final item = i < aiResult!.bothWeekly.length ? aiResult!.bothWeekly[i] : {'expenses': 0.0, 'income': 0.0};
            return {
              'Expenses': item['expenses'] ?? 0.0,
              'Income': item['income'] ?? 0.0,
            };
          });
      }
    }

    switch (viewMode) {
      case StatsViewMode.expenses:
        return weeklyData;
      case StatsViewMode.income:
        return weeklyIncomeData;
      case StatsViewMode.both:
        return List.generate(4, (i) {
          final expMap = i < weeklyData.length ? weeklyData[i] : <String, double>{};
          final incMap = i < weeklyIncomeData.length ? weeklyIncomeData[i] : <String, double>{};
          
          final expTotal = expMap.values.fold(0.0, (a, b) => a + b);
          final incTotal = incMap.values.fold(0.0, (a, b) => a + b);
          
          return {
            'Expenses': expTotal,
            'Income': incTotal,
          };
        });
    }
  }

  /// Computed property to get the central total text for the pie chart.
  double get displayTotal {
    if (aiResult != null) {
      switch (viewMode) {
        case StatsViewMode.expenses:
          return aiResult!.expensesPie.values.fold(0.0, (a, b) => a + b);
        case StatsViewMode.income:
          return aiResult!.incomePie.values.fold(0.0, (a, b) => a + b);
        case StatsViewMode.both:
          final exp = aiResult!.expensesPie.values.fold(0.0, (a, b) => a + b);
          final inc = aiResult!.incomePie.values.fold(0.0, (a, b) => a + b);
          return exp + inc;
      }
    }

    switch (viewMode) {
      case StatsViewMode.expenses:
        return totalMonthlyExpenses;
      case StatsViewMode.income:
        return totalMonthlyIncome;
      case StatsViewMode.both:
        return totalMonthlyExpenses + totalMonthlyIncome;
    }
  }

  /// Internal helper to bin transactions into 4 standard weeks.
  List<Map<String, double>> _calculateWeeklyData(
      List<ExpenseModel> records, bool incomeOnly, DateTime cutoff) {
    List<Map<String, double>> weeks = [{}, {}, {}, {}];

    for (var r in records) {
      if (r.date.isAfter(cutoff)) continue;
      if (incomeOnly && !r.isIncome) continue;
      if (!incomeOnly && r.isIncome) continue;

      final day = r.date.day;
      // Week 1: 1-7, Week 2: 8-14, Week 3: 15-21, Week 4: 22+
      final weekIndex = day <= 7
          ? 0
          : day <= 14
              ? 1
              : day <= 21
                  ? 2
                  : 3;

      weeks[weekIndex][r.category] =
          (weeks[weekIndex][r.category] ?? 0) + r.amount;
    }

    return weeks;
  }
}
