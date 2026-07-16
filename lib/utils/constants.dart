import 'package:flutter/material.dart';

class AppConstants {
  // Default budget categories
  static const List<String> defaultCategories = [
    'Food',
    'Transport',
    'Shopping',
    'Bills',
    'Health',
    'Others',
  ];

  // Category colors (expense categories + income categories)
  static const Map<String, Color> categoryColors = {
    // Expense categories
    'Food': Color(0xFFE07A5F),
    'Transport': Color(0xFF4EA8DE),
    'Shopping': Color(0xFF9B5DE5),
    'Bills': Color(0xFF2D6A4F),
    'Health': Color(0xFF00B4D8),
    'Others': Color(0xFFF4A261),
    // Income categories
    'Earned': Color(0xFF43A047),
    'Investment': Color(0xFF1E88E5),
    'Passive': Color(0xFFAB47BC),
  };

  // Category icons (expense + income)
  static const Map<String, IconData> categoryIcons = {
    // Expense categories
    'Food': Icons.restaurant,
    'Transport': Icons.directions_car,
    'Shopping': Icons.shopping_bag,
    'Bills': Icons.receipt_long,
    'Health': Icons.health_and_safety,
    'Others': Icons.category,
    // Income categories
    'Earned': Icons.work,
    'Investment': Icons.trending_up,
    'Passive': Icons.account_balance,
  };

  /// Returns the color for a category; custom categories get a generated color
  static Color getCategoryColor(String category) {
    return categoryColors[category] ??
        Color((category.hashCode & 0x00FFFFFF) | 0xFF808000);
  }

  /// Returns the icon for a category
  static IconData getCategoryIcon(String category) {
    return categoryIcons[category] ?? Icons.label;
  }

  /// Format amount as RM currency string
  static String formatCurrency(double amount) {
    if (amount == amount.roundToDouble()) {
      return 'RM ${amount.toStringAsFixed(0)}';
    }
    return 'RM ${amount.toStringAsFixed(1)}';
  }

  /// AI-powered financial advice generator.
  /// Analyses budget vs actual spending and provides contextual tips.
  static String generateAdvice({
    required Map<String, double> budgetAllocations,
    required Map<String, double> expensesByCategory,
    required double monthlyIncome,
  }) {
    // 1. Check for over-budget categories
    for (var entry in budgetAllocations.entries) {
      double used = expensesByCategory[entry.key] ?? 0;
      if (entry.value > 0 && used > entry.value) {
        double overBy = used - entry.value;
        final tips = [
          '${entry.key} is RM${overBy.toStringAsFixed(0)} over budget. Consider pausing non-essential buys.',
          '${entry.key} exceeded by RM${overBy.toStringAsFixed(0)}. Review recent purchases and cut back.',
          'You\'ve overspent on ${entry.key} by RM${overBy.toStringAsFixed(0)}. Try cheaper alternatives this week.',
        ];
        return tips[DateTime.now().day % tips.length];
      }
    }

    // 2. Check for near-budget categories (>90%)
    for (var entry in budgetAllocations.entries) {
      double used = expensesByCategory[entry.key] ?? 0;
      double ratio = entry.value > 0 ? used / entry.value : 0;
      if (ratio > 0.9) {
        return '${entry.key} budget is ${(ratio * 100).toStringAsFixed(0)}% used. Be mindful of spending.';
      }
    }

    // 3. Overall spending vs income
    double totalExpenses =
        expensesByCategory.values.fold(0.0, (a, b) => a + b);
    if (monthlyIncome > 0) {
      double ratio = totalExpenses / monthlyIncome;
      if (ratio > 0.8) {
        return 'Total spending at ${(ratio * 100).toStringAsFixed(0)}% of income. Consider reviewing expenses.';
      }
    }

    // 4. No expenses yet
    if (totalExpenses == 0) {
      return 'Start tracking expenses to get personalised financial insights! 📊';
    }

    // 5. Positive messages
    final msgs = [
      'Great financial discipline this month! Keep it up 💪',
      'Spending is well managed. Consider saving the surplus 💰',
      'Budget on track! You\'re building good financial habits 🎯',
    ];
    return msgs[DateTime.now().day % msgs.length];
  }
}
