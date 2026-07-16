import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../models/budget_model.dart';
import '../models/expense_model.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ── User Operations ──

  Future<void> createUser(UserModel user) async {
    await _db.collection('users').doc(user.uid).set(user.toMap());
  }

  Future<bool> emailExists(String email) async {
    final query = await _db
        .collection('users')
        .where('email', isEqualTo: email.trim())
        .limit(1)
        .get();
    return query.docs.isNotEmpty;
  }

  Future<UserModel?> getUser(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (doc.exists && doc.data() != null) {
      return UserModel.fromMap(doc.data()!, uid);
    }
    return null;
  }

  Future<void> updateUser(String uid, Map<String, dynamic> data) async {
    await _db.collection('users').doc(uid).update(data);
  }

  // ── Budget Operations ──

  Future<void> createBudgets(String userId, List<BudgetModel> budgets) async {
    final batch = _db.batch();
    for (var budget in budgets) {
      final ref = _db.collection('budgets').doc();
      batch.set(ref, budget.toMap());
    }
    await batch.commit();
  }

  Future<void> syncBudgets(String userId, List<BudgetModel> newBudgets) async {
    final existing = await getBudgets(userId);
    final batch = _db.batch();

    // Delete removed categories
    for (var ext in existing) {
      final isStillPresent = newBudgets.any(
        (b) => b.category.toLowerCase() == ext.category.toLowerCase(),
      );
      if (!isStillPresent && ext.id != null) {
        batch.delete(_db.collection('budgets').doc(ext.id));
      }
    }

    // Add or update categories
    for (var b in newBudgets) {
      final extIndex = existing.indexWhere(
        (e) => e.category.toLowerCase() == b.category.toLowerCase(),
      );
      if (extIndex == -1) {
        final ref = _db.collection('budgets').doc();
        batch.set(ref, b.toMap());
      } else {
        final ext = existing[extIndex];
        if (ext.allocatedAmount != b.allocatedAmount && ext.id != null) {
          batch.update(
              _db.collection('budgets').doc(ext.id),
              {'allocatedAmount': b.allocatedAmount});
        }
      }
    }

    await batch.commit();
  }

  Future<List<BudgetModel>> getBudgets(String userId) async {
    final snapshot = await _db
        .collection('budgets')
        .where('userId', isEqualTo: userId)
        .get();
    return snapshot.docs
        .map((doc) => BudgetModel.fromMap(doc.data(), doc.id))
        .toList();
  }

  Future<void> updateBudget(String budgetId, double amount) async {
    await _db
        .collection('budgets')
        .doc(budgetId)
        .update({'allocatedAmount': amount});
  }

  Future<void> deleteAllBudgets(String userId) async {
    final snapshot = await _db
        .collection('budgets')
        .where('userId', isEqualTo: userId)
        .get();
    final batch = _db.batch();
    for (var doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  // ── Expenses Operations (collection: 'expenses') ──

  Future<void> addRecord(ExpenseModel record) async {
    await _db.collection('expenses').add(record.toMap());
  }

  /// Stream of all records for a user, sorted client-side by date descending.
  /// Note: orderBy is intentionally omitted to avoid requiring a Firestore
  /// composite index on (userId, date) which may not exist.
  Stream<List<ExpenseModel>> getRecordsStream(String userId) {
    return _db
        .collection('expenses')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snapshot) {
      final records = snapshot.docs
          .map((doc) => ExpenseModel.fromMap(doc.data(), doc.id))
          .toList();
      // Sort client-side: newest first
      records.sort((a, b) => b.date.compareTo(a.date));
      return records;
    });
  }

  /// Get records for a specific month, filtered client-side.
  /// Note: date range where-clauses are omitted to avoid composite index
  /// requirements on (userId, date).
  Future<List<ExpenseModel>> getRecordsByMonth(
      String userId, int year, int month) async {
    final startOfMonth = DateTime(year, month, 1);
    final endOfMonth = DateTime(year, month + 1, 0, 23, 59, 59);

    final snapshot = await _db
        .collection('expenses')
        .where('userId', isEqualTo: userId)
        .get();

    return snapshot.docs
        .map((doc) => ExpenseModel.fromMap(doc.data(), doc.id))
        .where((r) =>
            !r.date.isBefore(startOfMonth) && !r.date.isAfter(endOfMonth))
        .toList();
  }

  /// Get expense (non-income) records grouped by category for a month
  Future<Map<String, double>> getExpensesByCategory(
      String userId, int year, int month) async {
    final records = await getRecordsByMonth(userId, year, month);
    final Map<String, double> byCategory = {};
    for (var r in records) {
      if (!r.isIncome) {
        byCategory[r.category] = (byCategory[r.category] ?? 0) + r.amount;
      }
    }
    return byCategory;
  }

  /// Get income records grouped by category for a month
  Future<Map<String, double>> getIncomeByCategory(
      String userId, int year, int month) async {
    final records = await getRecordsByMonth(userId, year, month);
    final Map<String, double> byCategory = {};
    for (var r in records) {
      if (r.isIncome) {
        byCategory[r.category] = (byCategory[r.category] ?? 0) + r.amount;
      }
    }
    return byCategory;
  }

  /// Total expenses for a month
  Future<double> getTotalExpensesByMonth(
      String userId, int year, int month) async {
    final records = await getRecordsByMonth(userId, year, month);
    return records
        .where((r) => !r.isIncome)
        .fold<double>(0.0, (total, r) => total + r.amount);
  }

  /// Total income for a month
  Future<double> getTotalIncomeByMonth(
      String userId, int year, int month) async {
    final records = await getRecordsByMonth(userId, year, month);
    return records
        .where((r) => r.isIncome)
        .fold<double>(0.0, (total, r) => total + r.amount);
  }

  /// Delete all records for a user
  Future<void> deleteAllRecords(String userId) async {
    final snapshot = await _db
        .collection('expenses')
        .where('userId', isEqualTo: userId)
        .get();
    final batch = _db.batch();
    for (var doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  /// Delete all Firestore data for the user (records, budgets, and user doc)
  Future<void> deleteUserAllData(String userId) async {
    // 1. Delete records
    await deleteAllRecords(userId);
    // 2. Delete budgets
    await deleteAllBudgets(userId);
    // 3. Delete user document
    await _db.collection('users').doc(userId).delete();
  }

  /// Update an individual expense/income record
  Future<void> updateRecord(String id, Map<String, dynamic> data) async {
    await _db.collection('expenses').doc(id).update(data);
  }

  /// Delete an individual expense/income record
  Future<void> deleteRecord(String id) async {
    await _db.collection('expenses').doc(id).delete();
  }
}
