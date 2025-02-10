import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_near/services/firestore.dart';

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
      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      if (userCredential.user != null) {
        await FirestoreService().createUser(userCredential.user!.uid, email);
        return true;
      }

      return false;
    } catch (e) {
      debugPrint('registerWithEmailPassword: $e');
      return false;
    }
  }

}