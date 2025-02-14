import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_near/services/firestore.dart';
import 'package:flutter_near/services/location.dart';
import 'package:flutter_near/models/near_user.dart';
import 'package:flutter_near/services/spatial_db.dart';
import 'package:flutter_near/widgets/custom_loader.dart';
import 'package:flutter_near/widgets/profile_picture.dart';
import 'package:dart_jts/dart_jts.dart' as jts;
import 'package:flutter_near/pages/friend_page.dart';
import 'package:flutter_near/widgets/slide_page_route.dart';

class FriendsPage extends StatefulWidget {
  final NearUser currentUser;

  const FriendsPage({
    super.key,
    required this.currentUser,
  });

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  bool isLoading = false;
  Future<List<NearUser>>? futureList;

  @override
  void initState() {
    super.initState();
    fetchData();
  }

  @override
  void dispose() {
    super.dispose();
    futureList = null;
  }

  void fetchData() async {
    setState(() {
      isLoading = true;
    });

    GeoPoint? pos = await LocationService().getCurrentPosition();
    if (pos != null) {
      jts.Point random = await SpatialDb().getRandomKNN(
        widget.currentUser.kAnonymity,
        pos.longitude,
        pos.latitude,
        50
      );
      await FirestoreService().setLocation(widget.currentUser.uid, random.getX(), random.getY());
    }

    setState(() {
      isLoading = false;
      futureList = FirestoreService().getFriends(widget.currentUser.uid);
    });
  }

  @override
  Widget build(BuildContext context) {
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
          const SizedBox(height: 16),
          Expanded(
            child: widget.currentUser.location != null
                ? FutureBuilder(
                    future: futureList,
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        List<NearUser> friends = snapshot.data!;
                        List<NearUser> oFriends = widget.currentUser
                            .getUsersOrderedByLocation(friends);

                        if (!oFriends.any((friend) => 
                            friend.uid == widget.currentUser.uid)) {
                          oFriends.insert(0, widget.currentUser);
                        }

                        return ListView.builder(
                          itemCount: oFriends.length,
                          itemBuilder: (context, index) {
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: ProfilePicture(
                                user: oFriends[index],
                                size: 45,
                                color: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.color ?? 
                                    Colors.black,
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .surface,
                              ),
                              title: Text(oFriends[index].username),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  SlidePageRoute(
                                    page: FriendPage(
                                      friend: oFriends[index],
                                      currentUser: widget.currentUser,
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        );
                      } else if (snapshot.hasError) {
                        return Text('Error: ${snapshot.error}');
                      }
                      return const CustomLoader();
                    },
                  )
                : const Text('Please share your location'),
          ),
        ],
      ),
    );
  }
}