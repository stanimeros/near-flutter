import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_near/models/meeting.dart';

class MeetingService {
  static const String baseUrl = 'https://snf-78417.ok-kno.grnetcloud.net';
  
  // Create a new meeting
  Future<Meeting?> createMeeting() async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/meetings'),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final meetingData = data['meeting'];
          return Meeting(
            token: meetingData['token'],
            datetime: DateTime.parse(meetingData['datetime']),
            location: const GeoPoint(0, 0), // Will be set when suggesting location
            updatedAt: DateTime.parse(meetingData['updated_at']),
            createdAt: DateTime.parse(meetingData['created_at']),
            status: MeetingStatus.pending,
          );
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error creating meeting: $e');
      return null;
    }
  }
  
  // Suggest a meeting location
  Future<Meeting?> suggestMeeting(String token, double longitude, double latitude, DateTime time) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/meetings/$token/suggest'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'longitude': longitude,
          'latitude': latitude,
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final meetingData = data['meeting'];
          final meeting = Meeting.fromApi(meetingData);
          // Update the time since the API doesn't store it
          meeting.datetime = time;
          return meeting;
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error suggesting meeting: $e');
      return null;
    }
  }
  
  // Re-suggest a meeting location (counter-proposal)
  Future<Meeting?> resuggestMeeting(String token, double longitude, double latitude, DateTime time) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/meetings/$token/resuggest'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'longitude': longitude,
          'latitude': latitude,
        }),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final meetingData = data['meeting'];
          final meeting = Meeting.fromApi(meetingData);
          // Update the time since the API doesn't store it
          meeting.datetime = time;
          return meeting;
        }
      }
      return null;
    } catch (e) {
      debugPrint('Error re-suggesting meeting: $e');
      return null;
    }
  }
  
  // Accept a meeting
  Future<bool> acceptMeeting(String token) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/meetings/$token/accept'),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      debugPrint('Error accepting meeting: $e');
      return false;
    }
  }
  
  // Reject a meeting
  Future<bool> rejectMeeting(String token) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/meetings/$token/reject'),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      debugPrint('Error rejecting meeting: $e');
      return false;
    }
  }
  
  // Cancel a meeting
  Future<bool> cancelMeeting(String token) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/meetings/$token/cancel'),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      debugPrint('Error cancelling meeting: $e');
      return false;
    }
  }
  
  // Get a meeting by token
  Future<Meeting?> getMeeting(String token) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/meetings/$token'),
      );
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final meetingData = data['meeting'];
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