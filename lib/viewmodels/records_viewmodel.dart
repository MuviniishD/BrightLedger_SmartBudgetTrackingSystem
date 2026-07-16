import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/firestore_service.dart';
import '../models/expense_model.dart';

class RecordsViewModel extends ChangeNotifier {
  final FirestoreService _firestoreService;

  List<ExpenseModel> _allRecords = [];
  List<ExpenseModel> filteredRecords = [];

  /// All filter chips: ['All', 'Incomes', 'Expenses', ...income cats, ...expense cats]
  List<String> availableCategories = ['All'];
  String selectedCategory = 'All';

  List<String> incomeCategories = ['Earned', 'Investment', 'Passive'];
  List<String> expenseCategories = ['Food', 'Transport', 'Shopping', 'Bills', 'Health', 'Others'];

  // Date range filter
  DateTime? dateRangeStart;
  DateTime? dateRangeEnd;

  bool isLoading = false;

  RecordsViewModel(this._firestoreService);

  void listenToRecords(String userId) {
    loadCategories(userId);
    _firestoreService.getRecordsStream(userId).listen(
      (records) {
        _allRecords = records;
        _applyFilters();
        notifyListeners();
      },
      onError: (e) {
        debugPrint('RecordsViewModel stream error: $e');
      },
    );
  }

  /// Filter records by the selected chip (All / Incomes / Expenses / category name)
  void filterByCategory(String category) {
    selectedCategory = category;
    _applyFilters();
    notifyListeners();
  }

  /// Set a custom date range filter
  void filterByDateRange(DateTime start, DateTime end) {
    dateRangeStart = DateTime(start.year, start.month, start.day, 0, 0, 0);
    dateRangeEnd = DateTime(end.year, end.month, end.day, 23, 59, 59);
    _applyFilters();
    notifyListeners();
  }

  /// Clear the date range filter
  void clearDateFilter() {
    dateRangeStart = null;
    dateRangeEnd = null;
    _applyFilters();
    notifyListeners();
  }

  /// Load filter chips: All | Incomes | Expenses | income categories | expense categories
  Future<void> loadCategories(String userId) async {
    try {
      final budgets = await _firestoreService.getBudgets(userId);
      final user = await _firestoreService.getUser(userId);

      expenseCategories = budgets.map((b) => b.category).toSet().toList();
      if (expenseCategories.isEmpty) {
        expenseCategories = ['Food', 'Transport', 'Shopping', 'Bills', 'Health', 'Others'];
      }
      
      incomeCategories =
          user?.selectedIncomeCategories ?? ['Earned', 'Investment', 'Passive'];

      availableCategories = [
        'All',
        'Incomes',
        'Expenses',
        ...incomeCategories,
        ...expenseCategories,
      ];
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading categories in RecordsViewModel: $e');
    }
  }

  /// Search records by text (shop name) or date string
  void searchByDate(String query) {
    if (query.isEmpty) {
      _applyFilters();
      notifyListeners();
      return;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 23, 59, 59);

    final base = _baseList();

    final lowerQuery = query.toLowerCase();
    filteredRecords = base.where((record) {
      if (record.date.isAfter(today)) return false;
      if (dateRangeStart != null &&
          record.date.isBefore(dateRangeStart!)) {
        return false;
      }
      if (dateRangeEnd != null &&
          record.date.isAfter(dateRangeEnd!)) {
        return false;
      }

      // Text match on shop name/reference
      final matchReference =
          record.reference.toLowerCase().contains(lowerQuery);

      // Date match
      final dateStr1 =
          DateFormat('d MMM yyyy').format(record.date).toLowerCase();
      final dateStr2 =
          DateFormat('d MMMM yyyy').format(record.date).toLowerCase();
      final dateStr3 =
          DateFormat('MMM yyyy').format(record.date).toLowerCase();
      final dateStr4 =
          DateFormat('MMMM yyyy').format(record.date).toLowerCase();
      final dateStr5 = DateFormat('d MMM').format(record.date).toLowerCase();

      return matchReference ||
          dateStr1.contains(lowerQuery) ||
          dateStr2.contains(lowerQuery) ||
          dateStr3.contains(lowerQuery) ||
          dateStr4.contains(lowerQuery) ||
          dateStr5.contains(lowerQuery);
    }).toList();

    notifyListeners();
  }

  /// Returns the base list respecting the selected type/category chip
  List<ExpenseModel> _baseList() {
    switch (selectedCategory) {
      case 'All':
        return List.from(_allRecords);
      case 'Incomes':
        return _allRecords.where((r) => r.isIncome).toList();
      case 'Expenses':
        return _allRecords.where((r) => !r.isIncome).toList();
      default:
        return _allRecords.where((r) => r.category == selectedCategory).toList();
    }
  }

  void _applyFilters() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day, 23, 59, 59);

    filteredRecords = _baseList().where((r) {
      if (r.date.isAfter(today)) return false;
      if (dateRangeStart != null && r.date.isBefore(dateRangeStart!)) {
        return false;
      }
      if (dateRangeEnd != null && r.date.isAfter(dateRangeEnd!)) return false;
      return true;
    }).toList();
  }

  /// true if a date range filter is active
  bool get hasDateFilter => dateRangeStart != null && dateRangeEnd != null;

  /// Human-readable label for active date range
  String get dateFilterLabel {
    if (!hasDateFilter) return '';
    final fmt = DateFormat('d MMM');
    return '${fmt.format(dateRangeStart!)} – ${fmt.format(dateRangeEnd!)}';
  }

  /// Update record reference and category in Firestore
  Future<bool> updateRecord(String id, String newReference, String newCategory) async {
    isLoading = true;
    notifyListeners();
    try {
      await _firestoreService.updateRecord(id, {
        'reference': newReference,
        'category': newCategory,
      });
      isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error updating record in RecordsViewModel: $e');
      isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Delete record in Firestore
  Future<bool> deleteRecord(String id) async {
    isLoading = true;
    notifyListeners();
    try {
      await _firestoreService.deleteRecord(id);
      isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error deleting record in RecordsViewModel: $e');
      isLoading = false;
      notifyListeners();
      return false;
    }
  }
}
