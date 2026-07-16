import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../models/user_model.dart';
import '../models/budget_model.dart';

/// [AuthViewModel] acts as the state manager for all authentication-related UI.
/// It bridges the [AuthService] (Firebase Auth) and the [FirestoreService] (Database)
/// with the login and registration screens, handling loading states and error messages.
class AuthViewModel extends ChangeNotifier {
  final AuthService _authService;
  final FirestoreService _firestoreService;

  // Internal state variables
  bool _isLoading = false;
  String? _error;

  /// Indicates if an asynchronous authentication operation is currently running.
  /// Used by the UI to show a loading spinner.
  bool get isLoading => _isLoading;
  
  /// Holds the current error message, if any. Null means no error.
  String? get error => _error;

  AuthViewModel(this._authService, this._firestoreService);

  /// Internal helper to update the loading state and notify the UI to rebuild.
  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  /// Clears the current error message. Typically called when the user starts typing again.
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Attempts to sign the user in with the provided [email] and [password].
  /// Returns [true] if successful, or [false] if an error occurred (which updates the [error] state).
  Future<bool> signIn(String email, String password) async {
    _setLoading(true);
    _error = null;
    try {
      // Delegate the actual sign-in request to the AuthService
      await _authService.signIn(email, password);
      _setLoading(false);
      return true;
    } on FirebaseAuthException catch (e) {
      // Handle known Firebase Auth errors gracefully
      _error = _mapAuthError(e.code);
      _setLoading(false);
      return false;
    } catch (e) {
      // Catch-all for network or unexpected errors
      _error = 'An unexpected error occurred.';
      _setLoading(false);
      return false;
    }
  }

  /// Registers a new user, creates their profile document in Firestore, 
  /// and initializes their monthly budget allocations.
  Future<bool> register({
    required String email,
    required String password,
    required String name,
    required double monthlyIncome,
    required List<BudgetModel> budgets,
  }) async {
    _setLoading(true);
    _error = null;
    try {
      // 1. Create the user in Firebase Auth
      final credential = await _authService.register(email, password);
      final uid = credential.user!.uid;

      try {
        // 2. Create the detailed user profile in the 'users' Firestore collection
        final user = UserModel(
          uid: uid,
          name: name,
          email: email,
          monthlyIncome: monthlyIncome,
          selectedCategories: budgets.map((b) => b.category).toList(),
          // Setup default income categories for the new user
          selectedIncomeCategories: const ['Earned', 'Investment', 'Passive'],
          memberSince: DateTime.now(),
        );
        await _firestoreService.createUser(user);

        // 3. Create the budget documents in the 'budgets' Firestore collection
        // Linked back to the user via the `userId` field
        final budgetsWithUid = budgets
            .map((b) => BudgetModel(
                  userId: uid,
                  category: b.category,
                  allocatedAmount: b.allocatedAmount,
                ))
            .toList();
        await _firestoreService.createBudgets(uid, budgetsWithUid);
      } catch (e) {
        // Specifically catch database errors (like permission denied or network failure)
        // User is created in Auth, but DB is incomplete. 
        _error = 'Account created, but database setup failed. Check Firestore rules.';
        _setLoading(false);
        return false;
      }

      _setLoading(false);
      return true;
    } on FirebaseAuthException catch (e) {
      debugPrint('FirebaseAuthException during registration: ${e.code} - ${e.message}');
      _error = _mapAuthError(e.code);
      _setLoading(false);
      return false;
    } catch (e) {
      debugPrint('Unexpected error during registration: $e');
      _error = 'Registration failed. Please try again.';
      _setLoading(false);
      return false;
    }
  }

  /// Requests a password reset email to be sent to the given [email] address.
  Future<bool> sendPasswordReset(String email) async {
    _setLoading(true);
    _error = null;
    try {
      await _authService.sendPasswordReset(email);
      _setLoading(false);
      return true;
    } on FirebaseAuthException catch (e) {
      _error = _mapAuthError(e.code);
      _setLoading(false);
      return false;
    } catch (e) {
      _error = 'Could not send reset email. Please try again.';
      _setLoading(false);
      return false;
    }
  }

  /// Signs the user out locally and destroys the session token.
  Future<void> signOut() async {
    await _authService.signOut();
  }

  /// Maps cryptic Firebase Auth error codes into human-readable strings.
  String _mapAuthError(String code) {
    switch (code) {
      case 'user-not-found':
        return 'Email not found. Please check or register.';
      case 'wrong-password':
        return 'Incorrect password. Please try again.';
      case 'email-already-in-use':
        return 'This email is already registered.';
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'invalid-email':
        return 'Invalid email address.';
      case 'invalid-credential':
        return 'Invalid email or password.';
      case 'operation-not-allowed':
        return 'Email/Password sign-in is not enabled in Firebase Console.';
      case 'network-request-failed':
        return 'Network error. Please check your internet connection.';
      case 'too-many-requests':
        return 'Too many login attempts. Please wait a moment and try again.';
      case 'user-disabled':
        return 'This account has been disabled. Contact support.';
      case 'expired-action-code':
        return 'The link has expired. Please request a new one.';
      case 'missing-client-identifier':
      case 'app-not-authorized':
        return 'Authentication verification failed. Please try again.';
      default:
        return 'Authentication error. Please try again.';
    }
  }
}
