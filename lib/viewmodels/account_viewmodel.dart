import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../models/user_model.dart';
import '../models/budget_model.dart';

class AccountViewModel extends ChangeNotifier {
  final AuthService _authService;
  final FirestoreService _firestoreService;

  UserModel? user;
  List<BudgetModel> budgets = [];
  bool isLoading = false;
  String? error;
  String? successMessage;

  AccountViewModel(this._authService, this._firestoreService);

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

  /// Sync/Update categories and budgets in Firestore
  Future<bool> updateCategoriesAndBudgets({
    required String userId,
    required List<BudgetModel> newBudgets,
    required List<String> newIncomeCategories,
  }) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      await _firestoreService.syncBudgets(userId, newBudgets);
      budgets = newBudgets;

      final expenseCategories = newBudgets.map((b) => b.category).toList();
      await _firestoreService.updateUser(userId, {
        'selectedCategories': expenseCategories,
        'selectedIncomeCategories': newIncomeCategories,
      });

      // Reload user profile in local state
      user = await _firestoreService.getUser(userId);

      successMessage = 'Categories and budgets updated successfully.';
      isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error updating categories and budgets: $e');
      error = 'Failed to update categories and budgets.';
      isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Load user profile
  Future<void> loadUser(String uid) async {
    isLoading = true;
    notifyListeners();

    try {
      user = await _firestoreService.getUser(uid);
    } catch (e) {
      error = 'Failed to load profile.';
    }

    isLoading = false;
    notifyListeners();
  }

  /// Change email (requires re-authentication)
  Future<bool> changeEmail(
      String currentPassword, String newEmail) async {
    isLoading = true;
    error = null;
    notifyListeners();

    try {
      final currentEmail = _authService.currentUser?.email ?? '';
      await _authService.reauthenticate(currentEmail, currentPassword);
      await _authService.updateEmail(newEmail);
      await _firestoreService.updateUser(
          _authService.currentUser!.uid, {'email': newEmail});
      successMessage = 'Verification email sent to $newEmail.';
      isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      error = 'Failed to update email. Check your password.';
      isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Change password (requires re-authentication)
  Future<bool> changePassword(
      String currentPassword, String newPassword) async {
    isLoading = true;
    error = null;
    notifyListeners();

    try {
      final email = _authService.currentUser?.email ?? '';
      await _authService.reauthenticate(email, currentPassword);
      await _authService.updatePassword(newPassword);
      successMessage = 'Password updated successfully.';
      isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      error = 'Failed to update password. Check your current password.';
      isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Delete entire user profile and all associated data, then delete Auth account
  Future<bool> deleteUserProfile(String userId) async {
    isLoading = true;
    error = null;
    notifyListeners();

    try {
      // 1. Delete all Firestore data (records, budgets, user doc)
      await _firestoreService.deleteUserAllData(userId);
      // 2. Delete Firebase Auth account
      await _authService.deleteAccount();
      
      successMessage = 'User profile and all data deleted successfully.';
      isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error deleting user profile: $e');
      error = 'Failed to delete user profile. You may need to re-authenticate (re-login) before deleting your account for security reasons.';
      isLoading = false;
      notifyListeners();
      return false;
    }
  }

  void clearMessages() {
    error = null;
    successMessage = null;
    notifyListeners();
  }
}
