import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// [AuthService] handles all Firebase Authentication operations.
/// This includes user login, registration, state management, and profile updates.
class AuthService {
  // Instance of FirebaseAuth used for all authentication calls
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Retrieves the currently authenticated [User], or null if not signed in.
  User? get currentUser => _auth.currentUser;

  /// Provides a stream that emits changes to the user's authentication state.
  /// Useful for listening to login/logout events across the app.
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Authenticates an existing user with their [email] and [password].
  /// Returns a [UserCredential] upon successful sign-in.
  Future<UserCredential> signIn(String email, String password) async {
    // Trim the email to avoid trailing/leading spaces causing auth errors
    return await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Creates a new user account using the provided [email] and [password].
  /// Returns a [UserCredential] upon successful registration.
  Future<UserCredential> register(String email, String password) async {
    // Trim the email to avoid validation errors
    return await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  /// Sends a password reset email to the specified [email] address.
  Future<void> sendPasswordReset(String email) async {
    // Trim email before sending reset link
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  /// Signs out the currently authenticated user.
  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Initiates an email update process for the current user to [newEmail].
  /// Sends a verification email to the new address before updating.
  Future<void> updateEmail(String newEmail) async {
    // Verify before update is the recommended Firebase method for security
    await _auth.currentUser?.verifyBeforeUpdateEmail(newEmail.trim());
  }

  /// Updates the current user's password to [newPassword].
  /// Note: Requires the user to have signed in recently.
  Future<void> updatePassword(String newPassword) async {
    await _auth.currentUser?.updatePassword(newPassword);
  }

  /// Re-authenticates the current user using their [email] and [password].
  /// This is required before performing sensitive operations like changing password or deleting account.
  Future<void> reauthenticate(String email, String password) async {
    // Create credential object from email and password
    final credential = EmailAuthProvider.credential(
      email: email,
      password: password,
    );
    // Attempt to re-authenticate with Firebase
    await _auth.currentUser?.reauthenticateWithCredential(credential);
  }

  /// Deletes the current user's account permanently from Firebase.
  /// Requires recent authentication.
  Future<void> deleteAccount() async {
    await _auth.currentUser?.delete();
  }
}

