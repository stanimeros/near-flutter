import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_near/services/firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<bool> registerWithEmailPassword(String email, String password, String username) async {
    try {
      // Create user with email and password
      final UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (result.user != null) {
        // Initialize user in Firestore
        await FirestoreService().createUser(
          result.user!.uid,
          email,
          username,
        );
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error in registerWithEmailPassword: $e');
      return false;
    }
  }

  Future<bool> signInWithEmailPassword(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return true;
    } catch (e) {
      debugPrint('Error in signInWithEmailPassword: $e');
      return false;
    }
  }
}