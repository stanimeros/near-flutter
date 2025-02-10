import 'package:flutter/material.dart';
import 'package:flutter_near/services/firestore.dart';
import 'package:flutter_near/services/near_user.dart';
import 'package:flutter_near/widgets/custom_loader.dart';
import 'package:flutter_near/widgets/messenger.dart';
import 'package:flutter_near/widgets/profile_picture.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_near/services/user_provider.dart';
import 'package:provider/provider.dart';

class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key});

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  NearUser? nearUser;
  Future<List<NearUser>>? futureList;

  @override
  void initState() {
    super.initState();
    final userProvider = context.read<UserProvider>();
    nearUser = userProvider.nearUser;
    futureList = FirestoreService().getFriends(nearUser!.uid);
  }

  @override
  Widget build(BuildContext context) {
    if (nearUser == null) {
      return const Center(child: Text('No user data available'));
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Row(
            children: [
              Text(
                'Friends',
                style: TextStyle(fontSize: 24),
              ),
            ],
          ),
          Expanded(
            child: FutureBuilder(
              future: futureList,
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  List<NearUser> friends = snapshot.data!;
                  if (friends.isNotEmpty) {
                    return ListView.builder(
                      itemCount: friends.length,
                      itemBuilder: (context, index) {
                        return Dismissible(
                          key: UniqueKey(),
                          background: Container(
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.error,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const ListTile(
                              trailing: Icon(LucideIcons.delete),
                            ),
                          ),
                          direction: DismissDirection.endToStart,
                          onDismissed: (direction) {
                            FirestoreService().rejectRequest(nearUser!.uid, friends[index].uid);
                            FirestoreService().rejectRequest(friends[index].uid, nearUser!.uid);
                            setState(() {
                              friends.removeAt(index);
                            });
                          },
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(4),
                            leading: ProfilePicture(
                              user: friends[index],
                              size: 40,
                              color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black,
                              backgroundColor: Theme.of(context).colorScheme.surface,
                            ),
                            title: Text(friends[index].username),
                          ),
                        );
                      },
                    );
                  }
                  return const Messenger(message: 'You don\'t have any friends yet');
                } else if (snapshot.hasError) {
                  return Messenger(message: 'Error ${snapshot.error}');
                }
                return const CustomLoader();
              },
            ),
          ),
        ],
      ),
    );
  }
}