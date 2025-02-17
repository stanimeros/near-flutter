import 'package:flutter/material.dart';
import 'package:flutter_near/models/meeting.dart';
import 'package:flutter_near/models/near_user.dart';
import 'package:flutter_near/pages/map_page.dart';
import 'package:flutter_near/services/firestore.dart';
import 'package:flutter_near/widgets/custom_loader.dart';
import 'package:lucide_icons/lucide_icons.dart';

class FriendPage extends StatelessWidget {
  final NearUser friend;
  final NearUser currentUser;

  const FriendPage({
    super.key,
    required this.friend,
    required this.currentUser,
  });

  Future<void> _confirmDeleteFriend(BuildContext context) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Friend'),
        content: Text('Are you sure you want to remove ${friend.username} from your friends?'),
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
      await FirestoreService().removeFriend(currentUser.uid, friend.uid);
      if (context.mounted) {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: ValueKey('friend_page_${friend.uid}'),
      appBar: AppBar(
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: Row(
          children: [
            Hero(
              tag: 'profile-${friend.uid}',
              child: CircleAvatar(
                radius: 20,
                backgroundImage: friend.imageURL.isNotEmpty ? 
                  NetworkImage(friend.imageURL) : null,
                child: friend.imageURL.isEmpty ? 
                  Text(
                    friend.username[0].toUpperCase(),
                    style: const TextStyle(fontSize: 20),
                  ) : null,
              ),
            ),
            const SizedBox(width: 12),
            Text(friend.username),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.trash2),
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
                  const Icon(LucideIcons.map),
                  const SizedBox(width: 12),
                  Text(
                    'Currently ${currentUser.getConvertedDistanceBetweenUser(friend)} away',
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
                        friend: friend,
                        currentUser: currentUser,
                      ),
                    ),
                  );
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

            // Meeting History
            Text(
              'Meeting History',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: StreamBuilder<List<Meeting>>(
                stream: FirestoreService().getMeetingsWithFriend(
                  currentUser.uid,
                  friend.uid,
                ),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    debugPrint('StreamBuilder error: ${snapshot.error}');
                    return Center(
                      child: Text('Error: ${snapshot.error}'),
                    );
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const CustomLoader();
                  }

                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return Center(
                      child: Text(
                        'No meetings yet',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    );
                  }

                  final meetings = snapshot.data!;

                  return ListView.builder(
                    key: const PageStorageKey('meetings_list'),
                    itemCount: meetings.length,
                    itemBuilder: (context, index) {
                      final meeting = meetings[index];
                      final isSender = meeting.senderId == currentUser.uid;

                      return Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8.0),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: ListTile(
                          leading: Icon(
                            isSender ? LucideIcons.arrowRight : LucideIcons.arrowLeft,
                            color: meeting.status.color,
                          ),
                          title: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                isSender ? 'You suggested' : '${friend.username} suggested',
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
                              Text('Time: ${formatDateTime(meeting.time)}'),
                              Text('Created on: ${formatDateTime(meeting.createdAt)}'),
                            ],
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => MapPage(
                                  friend: friend,
                                  currentUser: currentUser,
                                  suggestedMeeting: meeting,
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    },
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