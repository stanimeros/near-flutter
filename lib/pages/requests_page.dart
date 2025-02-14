import 'package:flutter/material.dart';
import 'package:flutter_near/services/firestore.dart';
import 'package:flutter_near/models/near_user.dart';
import 'package:flutter_near/widgets/custom_loader.dart';
import 'package:flutter_near/widgets/messenger.dart';
import 'package:flutter_near/widgets/profile_picture.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_near/services/user_provider.dart';
import 'package:provider/provider.dart';

class RequestsPage extends StatefulWidget {
  const RequestsPage({super.key});

  @override
  State<RequestsPage> createState() => _RequestsPageState();
}

class _RequestsPageState extends State<RequestsPage> {
  NearUser? nearUser;
  Future<List<NearUser>>? futureList;
  TextEditingController uController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final userProvider = context.read<UserProvider>();
    nearUser = userProvider.nearUser;
    futureList = FirestoreService().getUsersRequested(nearUser!.uid);
  }

  @override
  Widget build(BuildContext context) {
    if (nearUser == null) {
      return const Center(child: Text('No user data available'));
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Row(
                children: [
                  Text(
                    'Requests',
                    style: TextStyle(fontSize: 24),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: uController,
                decoration: InputDecoration(
                  labelText: 'Username',
                  suffixIcon: IconButton(
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      if (uController.text.length > 3 && uController.text.length < 13) {
                        FirestoreService().sendRequest(nearUser!.uid, uController.text);
                        uController.clear();
                      }
                    },
                    icon: const Icon(LucideIcons.userCheck),
                  ),
                ),
              ),
              const SizedBox(height: 30),
              const Row(
                children: [
                  Text(
                    'Your requests',
                    style: TextStyle(fontSize: 16),
                  ),
                ],
              ),
              Expanded(
                child: FutureBuilder(
                  future: futureList,
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      List<NearUser> usersRequested = snapshot.data!;
                      if (usersRequested.isNotEmpty) {
                        return ListView.builder(
                          itemCount: usersRequested.length,
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
                                FirestoreService().rejectRequest(
                                  usersRequested[index].uid,
                                  nearUser!.uid,
                                );
                                setState(() {
                                  usersRequested.removeAt(index);
                                });
                              },
                              child: ListTile(
                                contentPadding: const EdgeInsets.all(4),
                                leading: ProfilePicture(
                                  user: usersRequested[index],
                                  size: 40,
                                  color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black,
                                  backgroundColor: Theme.of(context).colorScheme.surface,
                                ),
                                title: Text(usersRequested[index].username),
                                trailing: IconButton(
                                  onPressed: () {
                                    FirestoreService().acceptRequest(usersRequested[index].uid);
                                    setState(() {
                                      usersRequested.removeAt(index);
                                    });
                                  },
                                  icon: const Icon(LucideIcons.check),
                                ),
                              ),
                            );
                          },
                        );
                      } else {
                        return const Messenger(message: 'You have no pending requests');
                      }
                    } else if (snapshot.hasError) {
                      return Messenger(message: 'Error: ${snapshot.error}');
                    }
                    return const CustomLoader();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}