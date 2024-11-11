import 'package:flutter/material.dart';
import 'package:flutter_near/common/firestore_service.dart';
import 'package:flutter_near/common/near_user.dart';
import 'package:flutter_near/common/slide_page_route.dart';
import 'package:flutter_near/pages/requests_page.dart';
import 'package:flutter_near/widgets/chat.dart';
import 'package:flutter_near/widgets/custom_loader.dart';
import 'package:flutter_near/widgets/messenger.dart';
import 'package:flutter_near/widgets/profile_picture.dart';
import 'package:flutter_near/common/globals.dart' as globals;
import 'package:lucide_icons/lucide_icons.dart';

class FriendsPage extends StatefulWidget {
  const FriendsPage({super.key});

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  Future<List<NearUser>>? futureList;

  @override
  void initState() {
    super.initState();
    futureList = FirestoreService().getFriends();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              const Text(
                'Friends',
                style: TextStyle(
                  fontSize: 24
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () {
                  Navigator.push(
                    context, 
                    SlidePageRoute(page: const RequestsPage()),
                  ).then((value) => setState((){
                    futureList = FirestoreService().getFriends();
                  }));
                }, 
                icon: const Icon(
                  size: 24,
                  LucideIcons.userPlus2
                )
              )
            ],
          ),
          Expanded(
            child: FutureBuilder(
              future: futureList, 
              builder: (context, snapshot){
                if (snapshot.hasData){
                  List<NearUser> friends = snapshot.data!;
                  if (friends.isNotEmpty){
                    return ListView.builder(
                      itemCount: friends.length,
                      itemBuilder: (context, index){
                        return Dismissible(
                          key: UniqueKey(),
                          background: Container(
                            decoration: BoxDecoration(
                              color: globals.rejectColor,
                              borderRadius: BorderRadius.circular(10)
                            ),
                            child: const ListTile(
                              trailing: Icon(LucideIcons.delete),
                            ),
                          ),
                          direction: DismissDirection.endToStart,
                          onDismissed: (direction) {
                            FirestoreService().rejectRequest(globals.user!.uid, friends[index].uid);
                            FirestoreService().rejectRequest(friends[index].uid, globals.user!.uid);
                            setState(() {
                              friends.removeAt(index);
                            });
                          },
                          child: ListTile(
                            contentPadding: const EdgeInsets.all(4),
                            leading: ProfilePicture(
                              user: friends[index],
                              size: 40,
                              color: globals.textColor, 
                              backgroundColor: globals.cachedImageColor
                            ),
                            title: Text(friends[index].username),
                            trailing: IconButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  SlidePageRoute(page: Chat(friend: friends[index]))
                                ).then((value) => setState(() {
                                  futureList = FirestoreService().getFriends();
                                }));
                              },
                              icon: const Icon(
                                LucideIcons.messageCircle
                              ),
                            ),
                          ),
                        );
                      }
                    );
                  }
                  return const Messenger(message: 'You don’t have any friends yet');
                }else if (snapshot.hasError){
                  return Messenger(message: 'Error ${snapshot.error}');
                }
                return const CustomLoader();
              }
            ),
          ),
        ],
      ),
    );
  }
}