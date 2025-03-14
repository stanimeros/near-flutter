import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class Meeting {
  final String token;
  DateTime datetime;
  GeoPoint location;
  MeetingStatus status;
  DateTime updatedAt;
  final DateTime createdAt;

  Meeting({
    required this.token,
    required this.datetime,
    required this.location,
    required this.updatedAt,
    required this.createdAt,
    required this.status,
  });

  factory Meeting.fromApi(Map<String, dynamic> data) {
    // Map API status to our MeetingStatus enum
    MeetingStatus status;
    switch (data['status']) {
      case 'created':
        status = MeetingStatus.pending;
        break;
      case 'suggested':
        status = MeetingStatus.pending;
        break;
      case 'resuggested':
        status = MeetingStatus.pending;
        break;
      case 'accepted':
        status = MeetingStatus.accepted;
        break;
      case 'rejected':
        status = MeetingStatus.rejected;
        break;
      case 'cancelled':
        status = MeetingStatus.cancelled;
        break;
      default:
        status = MeetingStatus.pending;
    }
    
    return Meeting(
      token: data['token'],
      datetime: data['datetime'] != null 
          ? DateTime.parse(data['datetime']) 
          : DateTime.now(),
      location: GeoPoint(
        data['location_lat'] ?? 0, 
        data['location_lon'] ?? 0
      ),
      updatedAt: data['updated_at'] != null 
          ? DateTime.parse(data['updated_at']) 
          : DateTime.parse(data['created_at']),
      createdAt: DateTime.parse(data['created_at']),
      status: status,
    );
  }
  
  // Convert MeetingStatus to API status string
  String get apiStatus {
    switch (status) {
      case MeetingStatus.pending:
        return 'suggested';
      case MeetingStatus.accepted:
        return 'accepted';
      case MeetingStatus.rejected:
        return 'rejected';
      case MeetingStatus.cancelled:
        return 'cancelled';
    }
  }
}

String formatDateTime(DateTime dateTime) {
  return '${dateTime.day}/${dateTime.month}/${dateTime.year} at ${dateTime.hour}:${dateTime.minute.toString().padLeft(2, '0')}';
}

bool isMeetingPast(DateTime time) {
  return time.isBefore(DateTime.now());
}

enum MeetingStatus {
  pending,
  accepted,
  rejected,
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
      case MeetingStatus.cancelled:
        return Colors.grey;
    }
  }
} 