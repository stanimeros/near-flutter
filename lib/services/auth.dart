import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_near/services/firestore.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  Future<String?> registerWithEmailPassword(String email, String password, String username) async {
    try {
      final uid = await FirestoreService().getUID(username);
      if (uid != null) {
        return 'Username already exists';
      }

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
        return null;
      }

      return 'Something went wrong';
    } catch (e) {
      debugPrint('Error in registerWithEmailPassword: $e');
      return (e as FirebaseException).message.toString();
    }
  }

  Future<String?> signInWithEmailPassword(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return null;
    } catch (e) {
      debugPrint('Error in signInWithEmailPassword: $e');
      return (e as FirebaseException).message.toString();
    }
  }
}