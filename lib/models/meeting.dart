import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class Meeting {
  final String id;
  final String senderId;
  final String receiverId;
  final GeoPoint location;
  final DateTime time;
  final MeetingStatus status;
  final String? message;

  Meeting({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.location,
    required this.time,
    required this.status,
    this.message,
  });

  factory Meeting.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map;
    return Meeting(
      id: doc.id,
      senderId: data['senderId'] ?? '',
      receiverId: data['receiverId'] ?? '',
      location: data['location'] ?? const GeoPoint(0, 0),
      time: data['time']?.toDate() ?? DateTime.now(),
      status: MeetingStatus.values.firstWhere(
        (e) => e.toString() == 'MeetingStatus.${data['status']}',
        orElse: () => MeetingStatus.pending,
      ),
      message: data['message'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'senderId': senderId,
      'receiverId': receiverId,
      'location': location,
      'time': Timestamp.fromDate(time),
      'status': status.toString().split('.').last,
      'message': message,
    };
  }

  Meeting copyWith({
    String? id,
    String? senderId,
    String? receiverId,
    GeoPoint? location,
    DateTime? time,
    MeetingStatus? status,
    String? message,
  }) {
    return Meeting(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      location: location ?? this.location,
      time: time ?? this.time,
      status: status ?? this.status,
      message: message ?? this.message,
    );
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