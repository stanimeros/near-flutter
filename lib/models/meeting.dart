import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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

  // Update this meeting with data from API response
  void updateFromApi(Map<String, dynamic> data) {
    // Update status
    if (data['status'] != null) {
      switch (data['status']) {
        case 'accepted':
          status = MeetingStatus.accepted;
          break;
        case 'rejected':
          status = MeetingStatus.rejected;
          break;
        case 'suggested':
          status = MeetingStatus.suggested;
          break;
      }
    }
    
    // Update datetime
    if (data['datetime'] != null) {
      try {
        datetime = DateTime.parse(data['datetime']);
      } catch (e) {
        debugPrint('Error parsing datetime: ${data['datetime']}');
      }
    }
    
    // Update location
    if (data['location_lon'] != null && data['location_lat'] != null) {
      location = GeoPoint(
        data['location_lat'] ?? 0, 
        data['location_lon'] ?? 0
      );
    }
    
    // Update updatedAt
    if (data['updated_at'] != null) {
      try {
        updatedAt = DateTime.parse(data['updated_at']);
      } catch (e) {
        debugPrint('Error parsing updated_at: ${data['updated_at']}');
      }
    }
  }

  factory Meeting.fromApi(Map<String, dynamic> data) {
    MeetingStatus status;
    switch (data['status']) {
      case 'accepted':
        status = MeetingStatus.accepted;
        break;
      case 'rejected':
        status = MeetingStatus.rejected;
        break;
      default:
        status = MeetingStatus.suggested;
        break;
    }
    
    DateTime createdAt;
    try {
      createdAt = DateTime.parse(data['created_at']);
    } catch (e) {
      debugPrint('Error parsing created_at: ${data['created_at']}');
      createdAt = DateTime.now();
    }
    
    DateTime updatedAt;
    try {
      updatedAt = data['updated_at'] != null 
          ? DateTime.parse(data['updated_at']) 
          : createdAt;
    } catch (e) {
      debugPrint('Error parsing updated_at: ${data['updated_at']}');
      updatedAt = createdAt;
    }
    
    DateTime datetime;
    try {
      datetime = data['datetime'] != null 
          ? DateTime.parse(data['datetime']) 
          : DateTime.now();
    } catch (e) {
      debugPrint('Error parsing datetime: ${data['datetime']}');
      datetime = DateTime.now();
    }
    
    return Meeting(
      token: data['token'],
      datetime: datetime,
      location: GeoPoint(
        data['location_lat'] ?? 0, 
        data['location_lon'] ?? 0
      ),
      updatedAt: updatedAt,
      createdAt: createdAt,
      status: status,
    );
  }
  
  // Convert MeetingStatus to API status string
  String get apiStatus {
    switch (status) {
      case MeetingStatus.accepted:
        return 'accepted';
      case MeetingStatus.rejected:
        return 'rejected';
      case MeetingStatus.suggested:
        return 'suggested';
    }
  }
}

String formatDateTime(DateTime dateTime) {
  final DateFormat formatter = DateFormat('EEE, d MMM yyyy \'at\' h:mm a');
  return formatter.format(dateTime);
}

bool isMeetingPast(DateTime time) {
  return time.isBefore(DateTime.now());
}

enum MeetingStatus {
  suggested,
  accepted,
  rejected,
}

extension MeetingStatusExtension on MeetingStatus {
  String get displayName {
    switch (this) {
      case MeetingStatus.accepted:
        return 'Accepted';
      case MeetingStatus.rejected:
        return 'Rejected';
      case MeetingStatus.suggested:
        return 'Suggested';
    }
  }

  Color get color {
    switch (this) {
      case MeetingStatus.accepted:
        return Colors.green;
      case MeetingStatus.rejected:
        return Colors.red;
      case MeetingStatus.suggested:
        return Colors.orange;
    }
  }
} 