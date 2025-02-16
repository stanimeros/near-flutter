import 'dart:async';
import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_near/models/near_user.dart';
import 'package:flutter_near/models/meeting.dart';

class FirestoreService {
  FirebaseFirestore firestore = FirebaseFirestore.instance;

  Future<void> createUser(String uid, String email, String username) async {
    await firestore.collection('users').doc(uid).set({
      'uid': uid,
      'email': email,
      'username': username,
      'joined': FieldValue.serverTimestamp(),
    });
  }

  Future<NearUser?> getUser(String uid) async {
    try {
      var snapshot = await firestore.collection('users').doc(uid).get();
      NearUser user = NearUser.fromFirestore(snapshot);
      return user;
    } catch (e) {
      debugPrint('Error getUser: $e');
      return null;
    }
  }

  Future<List<NearUser>> getFriends(String uid) async {
    try {
      // Fetch requests where the current user is the requester
      var req1Snapshot = await firestore
        .collection('requests')
        .where('uid', isEqualTo: uid)
        .where('status', isEqualTo: 'accepted')
        .get();
      List<QueryDocumentSnapshot> req1Docs = req1Snapshot.docs;

      // Fetch requests where the current user is the recipient
      var req2Snapshot = await firestore
        .collection('requests')
        .where('fuid', isEqualTo: uid)
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

  Future<List<NearUser>> getUsersRequested(String uid) async {
    try {
      var querySnapshot = await firestore
        .collection('requests')
        .where('fuid', isEqualTo: uid)
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

  Future<void> sendRequest(String uid, String username) async {
    try {
      String? fuid = await getUID(username);
      if (fuid != null) {
        // Query for request with both users
        // Query for requests between these users in either direction
        QuerySnapshot requestsSnapshot = await firestore
          .collection('requests')
          .where('users', whereIn: [[uid, fuid], [fuid, uid]])
          .get();

        // If no request exists, create new one
        if (requestsSnapshot.docs.isEmpty) {
          DocumentReference requestDocRef = firestore
            .collection('requests')
            .doc();

          await requestDocRef.set({
            'uid': uid,
            'fuid': fuid,
            'users': [uid, fuid],
            'status': 'pending'
          }, SetOptions(merge: true));
        }
      }
    } catch(e) {
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

    Future<void> removeFriend(String uid, String fuid) async {
    try{
      QuerySnapshot requestsSnapshot = await firestore
        .collection('requests')
        .where('users', whereIn: [[uid, fuid], [fuid, uid]])
        .get();

      if (requestsSnapshot.docs.isNotEmpty) {
        DocumentReference requestDocRef = requestsSnapshot.docs.first.reference;
        await requestDocRef.delete();
      }
    }catch(e){
      debugPrint('Error removeFriend: $e');
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

  Future<void> setLocation(String uid, double lon, double lat) async {
    try{
      DocumentReference userDocRef = firestore.collection('users').doc(uid);
      await userDocRef.set({
        'location': GeoPoint(lat, lon),
        'updated' : FieldValue.serverTimestamp()
      }, SetOptions(merge: true));
    }catch(e){
      debugPrint('Error setLocation: $e');
    }
  }

  Future<void> setUser(String uid, String username, String k) async {
    try{
      DocumentReference userDocRef = firestore.collection('users').doc(uid);
      await userDocRef.set({
        'username': username,
        'kAnonymity': k
      }, SetOptions(merge: true));
    }catch(e){
      debugPrint('Error setUser: $e');
    }
  }

  Future<void> setProfilePicture(String uid, String path) async {
    try{
      String url = '';
      FirebaseStorage storage = FirebaseStorage.instance;

      Reference ref = storage.ref().child("$uid/profile/${DateTime.now()}");
      UploadTask uploadTask = ref.putFile(File(path));

      final snapshot = await uploadTask.whenComplete(() {});
      url = await snapshot.ref.getDownloadURL();

      DocumentReference userDocRef = firestore.collection('users').doc(uid);
      if (url.isNotEmpty){
        await userDocRef.set({
          'image': url
        }, SetOptions(merge: true));
      }
    }catch(e){
      debugPrint('Error setProfilePicture: $e');
    }
  }

  Stream<List<Meeting>> getMeetingsWithFriend(String currentUserId, String friendId) {
    return FirebaseFirestore.instance
      .collection('meetings')
      .where(Filter.or(
        Filter.and(
          Filter('senderId', isEqualTo: currentUserId),
          Filter('receiverId', isEqualTo: friendId),
        ),
        Filter.and(
          Filter('senderId', isEqualTo: friendId),
          Filter('receiverId', isEqualTo: currentUserId),
        ),
      ))
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snapshot) {
        final meetings = snapshot.docs
          .map((doc) {
            return Meeting.fromFirestore(doc.id, doc.data());
          })
          .toList();
        return meetings;
      });
  }

  Future<void> updateMeetingStatus(String meetingId, MeetingStatus newStatus) {
    return firestore
      .collection('meetings')
      .doc(meetingId)
      .update({'status': newStatus.name});
  }
}
