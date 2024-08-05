import 'dart:async';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_near/common/globals.dart' as globals;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_near/common/location_service.dart';
import 'package:flutter_near/common/message.dart';
import 'package:flutter_near/common/near_user.dart';

class FirestoreService {
  User authUser = FirebaseAuth.instance.currentUser!;
  FirebaseFirestore firestore = FirebaseFirestore.instance;

  Future<NearUser?> getUser(String uid) async {
    try {
      var snapshot = await firestore.collection('users').doc(uid).get();
      NearUser user = NearUser.fromFirestore(snapshot);
      if (authUser.uid == uid){
        globals.user = user;
      }
      return user;
    } catch (e) {
      debugPrint('Error getUser: $e');
      return null;
    }
  }

  Future<List<NearUser>> getFriends() async {
    try {
      // Fetch requests where the current user is the requester
      var req1Snapshot = await firestore
        .collection('requests')
        .where('uid', isEqualTo: authUser.uid)
        .where('status', isEqualTo: 'accepted')
        .get();
      List<QueryDocumentSnapshot> req1Docs = req1Snapshot.docs;

      // Fetch requests where the current user is the recipient
      var req2Snapshot = await firestore
        .collection('requests')
        .where('fuid', isEqualTo: authUser.uid)
        .where('status', isEqualTo: 'accepted')
        .get();
      List<QueryDocumentSnapshot> req2Docs = req2Snapshot.docs;

      // Create a set to store unique friends' IDs
      Set<String> friendIds = {};

      // Add friend IDs from both query results to the set
      friendIds.addAll(req1Docs.map((doc) => doc['fuid'] as String));
      friendIds.addAll(req2Docs.map((doc) => doc['uid'] as String));

      // Fetch NearUser documents for each unique friend ID
      List<NearUser> friends = [];
      for (String friendId in friendIds) {
        DocumentSnapshot friendDoc = await firestore.collection('users').doc(friendId).get();
        if (friendDoc.exists) {
          friends.add(NearUser.fromFirestore(friendDoc));
        }
      }

      return friends;
    } catch (e) {
      debugPrint('Error getFriends: $e');
      return [];
    }
  }

  Future<List<NearUser>> getUsersRequested() async {
    try {
      var querySnapshot = await firestore
        .collection('requests')
        .where('fuid', isEqualTo: authUser.uid)
        .where('status', isEqualTo: 'pending')
        .get();

      List<QueryDocumentSnapshot> docs = querySnapshot.docs;
      List<Future<NearUser?>> userFutures = docs.map((doc) {
        return FirestoreService().getUser(doc['uid']);
      }).toList();
      
      // Wait for all futures to complete
      List<NearUser?> users = await Future.wait(userFutures);
      List<NearUser> nonNullUsers = users.where((user) => user != null).cast<NearUser>().toList();

      return nonNullUsers;
    } catch (e) {
      debugPrint('Error getUsersRequested: $e');
      return [];
    }
  }

  Stream<DocumentSnapshot> getChatSnapshot(NearUser friend){
    List<String> ids = [authUser.uid, friend.uid];
    ids.sort();
    String chatId = ids.join('_');

    var chatSnapshot = firestore
      .collection('chats')
      .doc(chatId)
      .snapshots();

    return chatSnapshot;
  }

  Stream<QuerySnapshot> getChatsSnapshot(){
    var chatsSnapshot = firestore
      .collection('chats')
      .where('users', arrayContains: authUser.uid)
      .snapshots();

    return chatsSnapshot;
  }

  void sendMessage(NearUser friend, String content) async {
    if (content.isEmpty){
      return;
    }
    // Create a Message object with necessary data
    Message message = Message(
      uid: authUser.uid,
      friendUid: friend.uid,
      content: content,
      timestamp: DateTime.now(),
    );

    // Convert the Message object to a map for Firestore
    Map<String, dynamic> messageData = {
      'uid': message.uid,
      // 'friendUid': message.friendUid,
      'content': message.content,
      'timestamp': message.timestamp,
    };

    List<String> ids = [authUser.uid, friend.uid];
    ids.sort();
    String chatId = ids.join('_');
    DocumentReference chatDocRef = firestore.collection('chats').doc(chatId);
    DocumentSnapshot chatDoc = await chatDocRef.get();

    if (chatDoc.exists) {
      // If the document exists, update it by adding the new message
      await chatDocRef.update({
        'messages': FieldValue.arrayUnion([messageData]),
      });
    } else {
      // If the document does not exist, create it with the new message
      await chatDocRef.set({
        'users' : [authUser.uid, friend.uid],
        'messages': [messageData],
      });
    }
  }

  void deleteMessages(NearUser friend) async {
    List<String> ids = [authUser.uid, friend.uid];
    ids.sort();
    String chatId = ids.join('_');

    DocumentReference chatDocRef = firestore.collection('chats').doc(chatId);
    await chatDocRef.delete();
  }

  Future<void> sendRequest(String username) async {
    try{
      String? fuid = await getUID(username);
      if (fuid != null) {
        bool? reqEx1 = await requestExists(authUser.uid, fuid);
        if (reqEx1 != null && !reqEx1){
          bool? reqEx2 = await requestExists(fuid, authUser.uid);
          if (reqEx2 != null && !reqEx2){
            QuerySnapshot requestsSnapshot = await firestore
              .collection('requests')
              .where('uid', isEqualTo: authUser.uid) 
              .where('fuid', isEqualTo: fuid)
              .get();

            if (requestsSnapshot.docs.isEmpty) {
              DocumentReference requestDocRef = firestore.collection('requests').doc();
              await requestDocRef.set({
                'uid': authUser.uid,
                'fuid': fuid,
                'status': 'pending'
              }, SetOptions(merge: true));
            }
          }
        }
      }
    }catch(e){
      debugPrint('Error sendRequest: $e');
    }
  }

  Future<void> acceptRequest(String fuid) async {
    try{
      QuerySnapshot requestsSnapshot = await firestore
        .collection('requests')
        .where('uid', isEqualTo: fuid)
        .get();

      if (requestsSnapshot.docs.isNotEmpty) {
        DocumentReference requestDocRef = requestsSnapshot.docs.first.reference;
        await requestDocRef.set({
          'status': 'accepted'
        }, SetOptions(merge: true));
      }
    }catch(e){
      debugPrint('Error acceptRequest: $e');
    }
  }

  Future<void> rejectRequest(String uid, String fuid) async {
    try{
      QuerySnapshot requestsSnapshot = await firestore
        .collection('requests')
        .where('uid', isEqualTo: uid)
        .where('fuid', isEqualTo: fuid)
        .get();

      if (requestsSnapshot.docs.isNotEmpty) {
        DocumentReference requestDocRef = requestsSnapshot.docs.first.reference;
        await requestDocRef.delete();
      }
    }catch(e){
      debugPrint('Error rejectRequest: $e');
    }
  }

  Future<String?> getUID(String username) async {
    try{
      QuerySnapshot usersSnapshot = await firestore
      .collection('users')
      .where('username', isEqualTo: username)
      .get();

      if (usersSnapshot.docs.isNotEmpty){
        return usersSnapshot.docs.first.id;
      }
    }catch(e){
      debugPrint('Error getUID: $e');
    }
    return null;
  }

  Future<bool?> requestExists(String uid, String fuid) async {
    try{
      QuerySnapshot requestsSnapshot = await firestore
        .collection('requests')
        .where('uid', isEqualTo: uid)
        .where('fuid', isEqualTo: fuid)
        .get();

      if (requestsSnapshot.docs.isNotEmpty) {
        return true;
      }
      return false;
    }catch(e){
      debugPrint('Error requestExists: $e');
      return null;
    }
  }

  Future<void> setLocation(double lon, double lat) async {
    try{
      DocumentReference userDocRef = firestore.collection('users').doc(authUser.uid);
      await userDocRef.set({
        'location': GeoPoint(lat, lon),
        'updated' : FieldValue.serverTimestamp()
      }, SetOptions(merge: true));
      globals.user!.location = GeoPoint(lat, lon);
    }catch(e){
      debugPrint('Error setLocation: $e');
    }
  }

  Future<void> setUsername(String username) async {
    try{
      DocumentReference userDocRef = firestore.collection('users').doc(authUser.uid);
      String? someUid = await getUID(username);
      if (someUid == null){
        await userDocRef.set({
          'username': username
        }, SetOptions(merge: true));
      }
    }catch(e){
      debugPrint('Error setUsername: $e');
    }
  }

  Future<void> setKAnonymity(String k) async {
    try{
      DocumentReference userDocRef = firestore.collection('users').doc(authUser.uid);
      await userDocRef.set({
          'kAnonymity': k
        }, SetOptions(merge: true));
    }catch(e){
      debugPrint('Error setUsername: $e');
    }
  }

  Future<void> setProfilePicture(String path) async {
    try{
      String url = '';
      FirebaseStorage storage = FirebaseStorage.instance;

      Reference ref = storage.ref().child("${authUser.uid}/profile/${DateTime.now()}");
      UploadTask uploadTask = ref.putFile(File(path));

      final snapshot = await uploadTask.whenComplete(() {});
      url = await snapshot.ref.getDownloadURL();

      DocumentReference userDocRef = firestore.collection('users').doc(authUser.uid);
      if (url.isNotEmpty){
        await userDocRef.set({
          'image': url
        }, SetOptions(merge: true));
      }
    }catch(e){
      debugPrint('Error setProfilePicture: $e');
    }
  }

  Future<NearUser?> initializeUser() async {
    try{
      if (globals.user == null){
        DocumentReference userDocRef = firestore.collection('users').doc(authUser.uid);
        DocumentSnapshot userDoc = await userDocRef.get();
        if (!userDoc.exists){
          String username = authUser.displayName!.replaceAll(' ', '').toLowerCase();
          if (username.length > 8) {
            username = username.substring(0, 8);
          }
          
          int counter = 1;
          String? someUid = await getUID(username);
          while (someUid != null) {
            username = '$username$counter';
            counter++;
          }

          await userDocRef.set({
            'username': username,
            'email': authUser.email,
            'joined' : FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }

        await FirestoreService().getUser(authUser.uid);
        globals.deviceLocation = await LocationService().getCurrentPosition();
      }
    }catch(e){
      debugPrint('Error initializeUser: $e');
    }
    return globals.user;
  }

  void signOut() async {
    globals.user = null;
    FirebaseAuth.instance.signOut();
  }

  void deleteAccount() async {

    // Delete user messages
    QuerySnapshot chatsSnapshot = await firestore
      .collection('chats')
      .where('users', arrayContains: authUser.uid)
      .get();

    for (var doc in chatsSnapshot.docs) {
      await doc.reference.delete();
    }

    // Delete user requests
    QuerySnapshot requestsSnapshot = await firestore
      .collection('posts')
      .where('uid', isEqualTo: authUser.uid)
      .get();

    for (var doc in requestsSnapshot.docs) {
      await doc.reference.delete();
    }

    requestsSnapshot = await firestore
      .collection('posts')
      .where('fuid', isEqualTo: authUser.uid)
      .get();

    for (var doc in requestsSnapshot.docs) {
      await doc.reference.delete();
    }

    DocumentReference userDocRef = firestore.collection('users').doc(authUser.uid);
    await userDocRef.delete();

    signOut();
  }
}
