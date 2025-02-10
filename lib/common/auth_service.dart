import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AuthService {

  Future<bool> signInWithEmailPassword(String email, String password) async {
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return true;
    } catch (e) {
      debugPrint('signInWithEmailPassword: $e');
      return false;
    }
  }

  Future<bool> registerWithEmailPassword(String email, String password) async {
    try {
      await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      return true;
    } catch (e) {
      debugPrint('registerWithEmailPassword: $e');
      return false;
    }
  }

}