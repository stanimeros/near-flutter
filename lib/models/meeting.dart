import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// Helper function to parse dates in different formats
DateTime parseDate(String? dateStr) {
  if (dateStr == null) return DateTime.now();
  
  try {
    // Try standard ISO format first
    return DateTime.parse(dateStr);
  } catch (e) {
    try {
      // Try HTTP date format (RFC 1123)
      // Example: "Fri, 14 Mar 2025 10:44:49 GMT"
      final httpFormat = DateFormat('EEE, dd MMM yyyy HH:mm:ss \'GMT\'');
      return httpFormat.parse(dateStr);
    } catch (e) {
      try {
        // Try alternative HTTP date format with day as single digit
        // Example: "Fri, 4 Mar 2025 10:44:49 GMT"
        final httpFormatSingleDigitDay = DateFormat('EEE, d MMM yyyy HH:mm:ss \'GMT\'');
        return httpFormatSingleDigitDay.parse(dateStr);
      } catch (e) {
        try {
          // Try without seconds
          // Example: "Fri, 14 Mar 2025 10:44 GMT"
          final httpFormatNoSeconds = DateFormat('EEE, dd MMM yyyy HH:mm \'GMT\'');
          return httpFormatNoSeconds.parse(dateStr);
        } catch (e) {
          debugPrint('Error parsing date: $dateStr');
          return DateTime.now();
        }
      }
    }
  }
}

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
      datetime = parseDate(data['datetime']);
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
      updatedAt = parseDate(data['updated_at']);
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
    
    final createdAt = parseDate(data['created_at']);
    final updatedAt = data['updated_at'] != null 
        ? parseDate(data['updated_at']) 
        : createdAt;
    final datetime = data['datetime'] != null 
        ? parseDate(data['datetime']) 
        : DateTime.now();
    
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