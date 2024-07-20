import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_near/common/firestore_service.dart';
import 'package:flutter_near/common/near_user.dart';
import 'package:flutter_near/common/slide_page_route.dart';
import 'package:flutter_near/common/globals.dart' as globals;
import 'package:flutter_near/widgets/chat.dart';
import 'package:flutter_near/widgets/messenger.dart';
import 'package:flutter_near/widgets/profile_picture.dart';
import 'package:flutter_near/widgets/skeleton_chat.dart';

class ChatsPage extends StatefulWidget {
  final authUser = FirebaseAuth.instance.currentUser!;

  ChatsPage({super.key});

  @override
  State<ChatsPage> createState() => _ChatsPageState();
}

class _ChatsPageState extends State<ChatsPage>{

  @override
  Widget build(BuildContext context) {
    
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Row(
            children: [
              Text(
                'Chats',
                style: TextStyle(
                  fontSize: 24
                ),
              ),
            ],
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirestoreService().getChatsSnapshot(),
              builder: (context, chatsSnapshot) {
                if (chatsSnapshot.hasData) {
                  var chatsDocs = chatsSnapshot.data!.docs;
                  if (chatsDocs.isNotEmpty) {
                    return ListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: chatsDocs.length ,
                      itemBuilder: (context, index) {
                        var chatData = chatsDocs[index].data() as Map<String, dynamic>;
                        var chatUsers = chatData['users'] as List<dynamic>;
                        chatUsers.remove(widget.authUser.uid);
                        String friendUid = chatUsers[0];
                        return FutureBuilder<NearUser?>(
                          future: FirestoreService().getUser(friendUid),
                          builder: (context, friendSnapshot) {
                            if (friendSnapshot.hasData){
                              NearUser? friend = friendSnapshot.data;

                              if (friend != null){
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  child: ListTile(
                                    tileColor: globals.skeletonTileColor,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    leading: ProfilePicture(
                                      user: friend, 
                                      size: 42, 
                                      color: globals.textColor, 
                                      backgroundColor: globals.cachedImageColor
                                    ),
                                    title: Row(
                                      children: [
                                        Text(
                                          friend.username,
                                          style: const TextStyle(
                                            fontSize: 20
                                          ),
                                        )
                                      ],
                                    ),
                                    subtitle: Text(
                                      chatData['messages'].last['uid'] == widget.authUser.uid ?
                                      'Me: ${chatData['messages'].last['content']}' :
                                      '${friend.username}: ${chatData['messages'].last['content']}',
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        SlidePageRoute(page: Chat(friend: friend))
                                      );
                                    },
                                  ),
                                );
                              }
                            }

                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: SkeletonChat(height: 66),
                            );
                          }
                        );
                      },
                    );
                  } else {
                    return const Messenger(message: "No chat conversations found");
                  }
                } else if (chatsSnapshot.hasError) {
                  return Messenger(message: "Error: ${chatsSnapshot.error}");
                } else {
                  return const Row();
                }
              }
            ),
          ),
        ]
      )
    );
  }
}