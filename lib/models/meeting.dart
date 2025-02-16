import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class Meeting {
  final String id;
  String senderId;
  String receiverId;
  DateTime time;
  GeoPoint location;
  MeetingStatus status;
  List<GeoPoint> previousLocations;
  final DateTime createdAt;

  Meeting({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.location,
    required this.time,
    required this.createdAt,
    required this.status,
    this.previousLocations = const [],
  });

  factory Meeting.fromFirestore(String id, Map<String, dynamic> data) {
    return Meeting(
      id: id,
      senderId: data['senderId'],
      receiverId: data['receiverId'],
      location: data['location'],
      time: (data['time'] as Timestamp).toDate(),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      status: MeetingStatus.values.firstWhere(
        (e) => e.name == data['status'],
        orElse: () => MeetingStatus.pending,
      ),
      previousLocations: (data['previousLocations'] as List?)
          ?.map((loc) => loc as GeoPoint)
          .toList() ?? [],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'senderId': senderId,
      'receiverId': receiverId,
      'location': location,
      'time': Timestamp.fromDate(time),
      'createdAt': Timestamp.fromDate(createdAt),
      'status': status.name,
      'previousLocations': previousLocations,
    };
  }
}

enum MeetingStatus {
  pending,
  accepted,
  rejected,
  counterProposal,
  cancelled
}

extension MeetingStatusExtension on MeetingStatus {
  String get displayName {
    switch (this) {
      case MeetingStatus.pending:
        return 'Pending';
      case MeetingStatus.accepted:
        return 'Accepted';
      case MeetingStatus.rejected:
        return 'Rejected';
      case MeetingStatus.counterProposal:
        return 'Counter Proposal';
      case MeetingStatus.cancelled:
        return 'Cancelled';
    }
  }

  Color get color {
    switch (this) {
      case MeetingStatus.pending:
        return Colors.orange;
      case MeetingStatus.accepted:
        return Colors.green;
      case MeetingStatus.rejected:
        return Colors.red;
      case MeetingStatus.counterProposal:
        return Colors.blue;
      case MeetingStatus.cancelled:
        return Colors.grey;
    }
  }
} 