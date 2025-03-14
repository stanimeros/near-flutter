import 'package:flutter/material.dart';
import 'package:flutter_near/models/meeting.dart';
import 'package:flutter_near/models/near_user.dart';
import 'package:flutter_near/pages/map_page.dart';
import 'package:flutter_near/services/firestore.dart';
import 'package:flutter_near/services/meeting_service.dart';
import 'package:flutter_near/widgets/custom_loader.dart';
import 'package:flutter_near/widgets/profile_picture.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class FriendPage extends StatefulWidget {
  final NearUser friend;
  final NearUser currentUser;

  const FriendPage({
    super.key,
    required this.friend,
    required this.currentUser,
  });

  @override
  State<FriendPage> createState() => _FriendPageState();
}

class _FriendPageState extends State<FriendPage> {
  final MeetingService _meetingService = MeetingService();
  List<Meeting> _meetings = [];
  bool _isLoading = true;
  
  @override
  void initState() {
    super.initState();
    _loadMeetings();
  }
  
  Future<void> _loadMeetings() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      final meetingTokens = await  FirestoreService().getMeetingTokens(widget.currentUser.uid, widget.friend.uid);
      final meetingsData = await Future.wait(meetingTokens.map((token) => _meetingService.getMeeting(token)));
      final meetings = meetingsData.where((meeting) => meeting != null).map((meeting) => meeting!).toList();
      
      setState(() {
        _meetings = meetings;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading meetings: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _confirmDeleteFriend(BuildContext context) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Friend'),
        content: Text('Are you sure you want to remove ${widget.friend.username} from your friends?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      await FirestoreService().removeFriend(widget.currentUser.uid, widget.friend.uid);
      if (context.mounted) {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: ValueKey('friend_page_${widget.friend.uid}'),
      appBar: AppBar(
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(LucideIcons.chevronLeft),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            ProfilePicture(
              user: widget.friend,
              size: 42,
              color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black,
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
            ),
            const SizedBox(width: 12),
            Text(widget.friend.username),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.userX),
            color: Theme.of(context).colorScheme.error,
            onPressed: () => _confirmDeleteFriend(context),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Distance info
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(LucideIcons.locate),
                  const SizedBox(width: 8),
                  Text(
                    'Approximately ${widget.currentUser.getConvertedDistanceBetweenUser(widget.friend)} away',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Suggest Meeting Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => MapPage(
                        friend: widget.friend,
                        currentUser: widget.currentUser,
                      ),
                    ),
                  ).then((_) => _loadMeetings()); // Refresh meetings when returning from map
                },
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(LucideIcons.mapPin),
                    SizedBox(width: 8),
                    Text('Suggest Meeting'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Meeting History with Refresh Button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Meeting History',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                IconButton(
                  icon: const Icon(LucideIcons.refreshCw),
                  onPressed: _loadMeetings,
                  tooltip: 'Refresh meetings',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _isLoading
                  ? const CustomLoader()
                  : _meetings.isEmpty
                      ? Center(
                          child: Text(
                            'No meetings yet',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                          ),
                        )
                      : ListView.builder(
                          key: const PageStorageKey('meetings_list'),
                          itemCount: _meetings.length,
                          itemBuilder: (context, index) {
                            final meeting = _meetings[index];

                            return Card(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8.0),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: ListTile(
                                leading: Icon(
                                  LucideIcons.arrowRight,
                                  color: meeting.status.color,
                                ),
                                title: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Suggested meeting',
                                    ),
                                    // Smaller Badge for meeting status
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: meeting.status.color.withAlpha(50),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        meeting.status.displayName,
                                        style: TextStyle(
                                          color: meeting.status.color,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Datetime: ${formatDateTime(meeting.datetime)}'),
                                    Text('Created on: ${formatDateTime(meeting.createdAt)}'),
                                  ],
                                ),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => MapPage(
                                        friend: widget.friend,
                                        currentUser: widget.currentUser,
                                        suggestedMeeting: meeting,
                                      ),
                                    ),
                                  ).then((_) => _loadMeetings()); // Refresh meetings when returning from map
                                },
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
} 