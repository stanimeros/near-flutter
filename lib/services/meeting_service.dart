import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_near/models/meeting.dart';

class MeetingService {
  static const String baseUrl = 'https://snf-78417.ok-kno.grnetcloud.net';
  
  // Format date for API
  String _formatDateForApi(DateTime? dateTime) {
    if (dateTime == null) return '';
    return dateTime.toUtc().toIso8601String();
  }
  
  // Create a new meeting
  Future<Meeting?> createMeeting({double? longitude, double? latitude, DateTime? datetime}) async {
    try {
      final Uri uri = Uri.parse('$baseUrl/api/meetings');
      final Map<String, dynamic> requestBody = {};
      
      // Add location and datetime to request if provided
      if (longitude != null && latitude != null) {
        requestBody['longitude'] = longitude;
        requestBody['latitude'] = latitude;
        
        if (datetime != null) {
          requestBody['datetime'] = _formatDateForApi(datetime);
        }
      }
      
      final response = await http.post(
        uri,
        headers: requestBody.isNotEmpty ? {'Content-Type': 'application/json'} : null,
        body: requestBody.isNotEmpty ? jsonEncode(requestBody) : null,
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final meetingData = data['meeting'];
          
          // If location was provided, the API will return a fully formed meeting
          if (meetingData['location_lon'] != null && meetingData['location_lat'] != null) {
            return Meeting.fromApi(meetingData);
          } else {
            // Otherwise, create a basic meeting object
            return Meeting(
              token: meetingData['token'],
              datetime: DateTime.now().add(const Duration(days: 1)), // Default to tomorrow
              location: const GeoPoint(0, 0), // Will be set when suggesting location
              updatedAt: meetingData['updated_at'] != null 
                  ? DateTime.parse(meetingData['updated_at']) 
                  : DateTime.parse(meetingData['created_at']),
              createdAt: DateTime.parse(meetingData['created_at']),
              status: MeetingStatus.suggested,
            );
          }
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error creating meeting: $e');
      return null;
    }
  }
  
  // Suggest a meeting location
  Future<Meeting?> suggestMeeting(String token, double longitude, double latitude, DateTime time, {Meeting? currentMeeting}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/meetings/$token/suggest'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'longitude': longitude,
          'latitude': latitude,
          'datetime': _formatDateForApi(time),
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final meetingData = data['meeting'];
          
          // If we have a current meeting object, update it and return it
          if (currentMeeting != null) {
            currentMeeting.updateFromApi(meetingData);
            return currentMeeting;
          }
          
          // Otherwise create a new meeting object
          return Meeting.fromApi(meetingData);
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error suggesting meeting: $e');
      return null;
    }
  }
  
  // Accept a meeting
  Future<bool> acceptMeeting(String token, {Meeting? currentMeeting}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/meetings/$token/accept'),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // If we have a current meeting object, update it
        if (data['success'] == true && currentMeeting != null && data['meeting'] != null) {
          currentMeeting.updateFromApi(data['meeting']);
        }
        
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      debugPrint('Error accepting meeting: $e');
      return false;
    }
  }
  
  // Reject a meeting
  Future<bool> rejectMeeting(String token, {Meeting? currentMeeting}) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/meetings/$token/reject'),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // If we have a current meeting object, update it
        if (data['success'] == true && currentMeeting != null && data['meeting'] != null) {
          currentMeeting.updateFromApi(data['meeting']);
        }
        
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      debugPrint('Error rejecting meeting: $e');
      return false;
    }
  }
  
  // Get a meeting by token
  Future<Meeting?> getMeeting(String token, {Meeting? currentMeeting}) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/meetings/$token'),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final meetingData = data['meeting'];
          
          // If we have a current meeting object, update it and return it
          if (currentMeeting != null) {
            currentMeeting.updateFromApi(meetingData);
            return currentMeeting;
          }
          
          // Otherwise create a new meeting object
          return Meeting.fromApi(meetingData);
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error getting meeting: $e');
      return null;
    }
  }
} 