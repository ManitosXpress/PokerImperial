import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Firebase Authentication Service
/// Handles all authentication operations including:
/// - Email/Password registration and login
/// - Google Sign-In
/// - User profile creation
/// - Auth state management
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get current user
  User? get currentUser => _auth.currentUser;

  /// Stream of auth state changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Register with username and password
  /// Creates user profile in Firestore automatically
  Future<UserCredential> registerWithUsername({
    required String username,
    required String password,
    required String nickname,
  }) async {
    try {
      final email = '$username@poker.app';
      
      // Create user account
      final UserCredential userCredential =
          await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Update display name
      await userCredential.user?.updateDisplayName(nickname);

      // Create user profile in Firestore
      await _createUserProfile(
        uid: userCredential.user!.uid,
        email: email,
        username: username, // Store username explicitly
        nickname: nickname,
      );

      return userCredential;
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  /// Sign in with username and password
  Future<UserCredential> signInWithUsername({
    required String username,
    required String password,
  }) async {
    try {
      final email = '$username@poker.app';
      
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }

  /// Sign out
  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Create user profile in Firestore
  /// This document will be read-only for clients (enforced by security rules)
  /// Only Cloud Functions can modify credit balance
  Future<void> _createUserProfile({
    required String uid,
    required String email,
    required String username,
    required String nickname,
  }) async {
    try {
      await _firestore.collection('users').doc(uid).set({
        'uid': uid,
        'email': email,
        'username': username,
        'displayName': nickname, // Changed from 'nickname' to 'displayName'
        'photoURL': '', // Empty for email/password registration
        'createdAt': FieldValue.serverTimestamp(),
        'credit': 0, // Changed from 'walletBalance' to 'credit'
        'role': 'player', // Default role for public registration
        'clubId': null, // No club assigned by default
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error creating user profile: $e');
      // Don't throw - authentication should succeed even if profile creation fails
      // The backend/Cloud Function will create the profile on token verification
    }
  }

  /// Handle Firebase Auth exceptions with user-friendly messages
  String _handleAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'weak-password':
        return 'La contraseña es muy débil. Usa al menos 6 caracteres.';
      case 'email-already-in-use':
        return 'Este correo ya está registrado. Intenta iniciar sesión.';
      case 'invalid-email':
        return 'El correo electrónico no es válido.';
      case 'user-not-found':
        return 'No existe una cuenta con este correo.';
      case 'wrong-password':
        return 'Contraseña incorrecta.';
      case 'user-disabled':
        return 'Esta cuenta ha sido deshabilitada.';
      case 'too-many-requests':
        return 'Demasiados intentos. Intenta más tarde.';
      default:
        return 'Error de autenticación: ${e.message}';
    }
  }

  /// Reset password
  Future<void> resetPassword(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw _handleAuthException(e);
    }
  }
}
