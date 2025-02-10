import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_near/services/firestore.dart';
import 'package:flutter_near/services/near_user.dart';

class UserProvider extends ChangeNotifier {
  NearUser? _nearUser;
  bool _isLoading = true;

  NearUser? get nearUser => _nearUser;
  bool get isLoading => _isLoading;

  Future<void> loadNearUser() async {
    _isLoading = true;
    notifyListeners();

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        _nearUser = await FirestoreService().getUser(user.uid);
      }
    } catch (e) {
      debugPrint('Error loading user: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  void updateUser(NearUser user) {
    _nearUser = user;
    notifyListeners();
  }

  // Updates user data without triggering a rebuild
  void updateUserSilently(NearUser user) {
    _nearUser = user;
  }
}