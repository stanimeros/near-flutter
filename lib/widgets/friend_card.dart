import 'package:flutter/material.dart';
import 'package:flutter_near/models/near_user.dart';
import 'package:flutter_near/pages/map_page.dart';
import 'package:lucide_icons/lucide_icons.dart';

class FriendCard extends StatelessWidget {
  final NearUser friend;
  final NearUser currentUser;

  const FriendCard({
    super.key,
    required this.friend,
    required this.currentUser,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundImage: friend.imageURL.isNotEmpty ? 
            NetworkImage(friend.imageURL) : null,
          child: friend.imageURL.isEmpty ? 
            Text(friend.username[0].toUpperCase()) : null,
        ),
        title: Text(friend.username),
        subtitle: Text(
          currentUser.getConvertedDistanceBetweenUser(friend),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: IconButton(
          icon: const Icon(LucideIcons.mapPin),
          onPressed: () => _suggestMeeting(context),
        ),
      ),
    );
  }

  void _suggestMeeting(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MapPage(
          mode: MapMode.suggestMeeting,
          friend: friend,
        ),
      ),
    );
  }
} 