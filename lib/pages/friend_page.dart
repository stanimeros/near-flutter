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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        title: Text(friend.username),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Profile Section
            Center(
              child: Hero(
                tag: 'profile-${friend.uid}',
                child: CircleAvatar(
                  radius: 60,
                  backgroundImage: friend.imageURL.isNotEmpty ? 
                    NetworkImage(friend.imageURL) : null,
                  child: friend.imageURL.isEmpty ? 
                    Text(
                      friend.username[0].toUpperCase(),
                      style: const TextStyle(fontSize: 40),
                    ) : null,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              friend.username,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(
              currentUser.getConvertedDistanceBetweenUser(friend),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),

            // Suggest Meeting Button
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => MapPage(
                      mode: MapMode.suggestMeeting,
                      friend: friend,
                      currentUser: currentUser,
                    ),
                  ),
                );
              },
              icon: const Icon(LucideIcons.mapPin),
              label: const Text('Suggest Meeting'),
            ),
            const SizedBox(height: 24),

            // Pending Meetings Section
            const Text(
              'Meeting Requests',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: StreamBuilder<List<Meeting>>(
                stream: FirestoreService().getMeetingsWithFriend(
                  currentUser.uid,
                  friend.uid,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const CustomLoader();
                  }

                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(
                      child: Text('No meeting requests'),
                    );
                  }

                  return ListView.builder(
                    itemCount: snapshot.data!.length,
                    itemBuilder: (context, index) {
                      final meeting = snapshot.data![index];
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
                              if (meeting.message != null)
                                Text('Message: ${meeting.message}'),
                            ],
                          ),
                          trailing: meeting.status == MeetingStatus.pending && !isSender
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(LucideIcons.check),
                                      color: Colors.green,
                                      onPressed: () => _respondToMeeting(
                                        context,
                                        meeting,
                                        MeetingStatus.accepted,
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(LucideIcons.x),
                                      color: Colors.red,
                                      onPressed: () => _respondToMeeting(
                                        context,
                                        meeting,
                                        MeetingStatus.rejected,
                                      ),
                                    ),
                                  ],
                                )
                              : null,
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

  Future<void> _respondToMeeting(
    BuildContext context,
    Meeting meeting,
    MeetingStatus newStatus,
  ) async {
    try {
      await FirestoreService().updateMeetingStatus(
        meeting.id,
        newStatus,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Meeting ${newStatus.displayName.toLowerCase()}'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error updating meeting status'),
          ),
        );
      }
    }
  }
} 