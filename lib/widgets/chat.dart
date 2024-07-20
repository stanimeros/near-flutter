import 'package:flutter/material.dart';
import 'package:flutter_near/common/near_user.dart';
import 'package:flutter_near/widgets/messenger.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:flutter_near/widgets/custom_loader.dart';
import 'package:flutter_near/common/globals.dart' as globals;
import 'package:flutter_near/common/firestore_service.dart';
import 'package:flutter_near/widgets/profile_picture.dart';

class Chat extends StatefulWidget {
  final NearUser friend;

  const Chat({
    super.key,
    required this.friend
  });

  @override
  State<Chat> createState() => _ChatState();
}

class _ChatState extends State<Chat>{

  TextEditingController messageController = TextEditingController();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {    
    return Scaffold(
      resizeToAvoidBottomInset: true,
      extendBodyBehindAppBar: true,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () {
                      Navigator.pop(context);
                    }, 
                    icon: const Icon(
                      LucideIcons.arrowLeft
                    )
                  ),
                  const SizedBox(
                    width: 12,
                  ),
                  ProfilePicture(
                    user: widget.friend, 
                    size: 40, 
                    color: globals.textColor, 
                    backgroundColor: globals.cachedImageColor
                  ),
                  const SizedBox(width: 12),
                  Text(
                    widget.friend.username,
                    style: const TextStyle(
                      fontSize: 24
                    ),
                  ),
                ],
              ),
              Expanded(
                child: StreamBuilder(
                  stream: FirestoreService().getChatSnapshot(widget.friend),
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      var chatData = snapshot.data!.data() as Map<String, dynamic>?;
                      if (chatData != null) {
                        var messages = (chatData['messages'] as List<dynamic>).cast<Map<String, dynamic>>();
                        return ListView(
                          reverse: true,
                          shrinkWrap: true,
                          children: messages.reversed.map<Widget>((message) {
                            bool userMessage = message['uid'] == globals.user!.uid;
                            return ListTile(
                              contentPadding: const EdgeInsets.all(0),
                              title: Row(
                                mainAxisAlignment: userMessage ? MainAxisAlignment.end : MainAxisAlignment.start,
                                children: userMessage ? [
                                  Flexible(
                                    child: Text(
                                      message['content'],
                                      textAlign: TextAlign.end,
                                    )
                                  ),
                                  const SizedBox(width: 8),
                                  ProfilePicture(
                                    user: globals.user!,
                                    size: 36,
                                    color: globals.textColor, 
                                    backgroundColor: globals.cachedImageColor
                                  ),
                                ]:[
                                  ProfilePicture(
                                    user: widget.friend,
                                    size: 36,
                                    color: globals.textColor, 
                                    backgroundColor: globals.cachedImageColor
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(message['content'])
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        );
                      } else {
                        return const Messenger(message: 'No messages to display');
                      }
                    }else{
                      return const CustomLoader();
                    }
                  }
                ),
              ),
              TextField(
                controller: messageController,
                decoration: InputDecoration(
                  suffixIcon: IconButton(
                    onPressed: () async {
                      FirestoreService().sendMessage(widget.friend, messageController.text);
                      messageController.clear();
                    }, 
                    icon: const Icon(
                      size: 24,
                      LucideIcons.send
                    )
                  ),
                ),
              )
            ],
          )
        ),
      ),
    );
  }
}