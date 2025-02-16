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
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.map),
                  const SizedBox(width: 12),
                  Text(
                    currentUser.getConvertedDistanceBetweenUser(friend),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Suggest Meeting Button
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
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
                icon: const Icon(LucideIcons.mapPin),
                label: const Text('Suggest Meeting'),
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
                  debugPrint('StreamBuilder rebuild: ${snapshot.connectionState}');
                  
                  if (snapshot.hasError) {
                    debugPrint('StreamBuilder error: ${snapshot.error}');
                    return Center(
                      child: Text('Error: ${snapshot.error}'),
                    );
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    debugPrint('StreamBuilder waiting');
                    return const CustomLoader();
                  }

                  debugPrint('StreamBuilder has data: ${snapshot.hasData}');
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
                  debugPrint('Building list with ${meetings.length} meetings');

                  return ListView.builder(
                    key: const PageStorageKey('meetings_list'),
                    itemCount: meetings.length,
                    itemBuilder: (context, index) {
                      final meeting = meetings[index];
                      final isSender = meeting.senderId == currentUser.uid;

                      return Card(
                        child: ListTile(
                          leading: Icon(
                            isSender ? LucideIcons.arrowRight : LucideIcons.arrowLeft,
                            color: meeting.status.color,
                          ),
                          title: Text(
                            isSender ? 'You suggested' : 'Friend suggested',
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Status: ${meeting.status.displayName}'),
                              Text('Time: ${meeting.time.toString()}'),
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