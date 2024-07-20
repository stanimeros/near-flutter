import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {

  Future<bool> signInWithGoogle() async {
    try{
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        throw Error();
      }

      final GoogleSignInAuthentication gAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: gAuth.accessToken,
        idToken: gAuth.idToken
      );

      await FirebaseAuth.instance.signInWithCredential(credential);
      return true;
    }catch(e){
      debugPrint('signInWithGoogle: $e');
      return false;
    }
  }
  
}