import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_near/services/firestore.dart';
import 'package:flutter_near/services/db_helper.dart';
import 'package:flutter_near/services/location.dart';
import 'package:flutter_near/services/near_user.dart';
import 'package:flutter_near/widgets/custom_loader.dart';
import 'package:flutter_near/widgets/messenger.dart';
import 'package:flutter_near/widgets/profile_picture.dart';
import 'package:dart_jts/dart_jts.dart' as jts;
import 'package:provider/provider.dart';
import 'package:flutter_near/services/user_provider.dart';

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
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
    final userProvider = context.read<UserProvider>();
    final nearUser = userProvider.nearUser;
    if (nearUser == null) return;

    setState(() {
      isLoading = true;
    });

    // await DbHelper().emptyTable(DbHelper.pois);
    // await DbHelper().emptyTable(DbHelper.keys);

    GeoPoint? pos = await LocationService().getCurrentPosition();
    if (pos != null) {
      debugPrint('Location: ${pos.latitude.toString()}, ${pos.longitude.toString()}');

      jts.Point random = await DbHelper().getRandomKNN(nearUser.kAnonymity, pos.longitude, pos.latitude, 50);
      debugPrint('New Location: ${random.getY()}, ${random.getX()}');
      await FirestoreService().setLocation(nearUser.uid, random.getX(), random.getY());
    }

    setState(() {
      isLoading = false;
      futureList = FirestoreService().getFriends(nearUser.uid);
    });
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();
    final nearUser = userProvider.nearUser;
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
                'Feed',
                style: TextStyle(fontSize: 24),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: nearUser.location != null
                ? FutureBuilder(
                    future: futureList,
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        List<NearUser> friends = snapshot.data!;
                        List<NearUser> oFriends = nearUser.getUsersOrderedByLocation(friends);

                        if (!oFriends.any((friend) => friend.uid == nearUser.uid)) {
                          oFriends.insert(0, nearUser);
                        }

                        if (oFriends.isNotEmpty) {
                          return ListView.builder(
                            shrinkWrap: true,
                            itemCount: oFriends.length,
                            itemBuilder: (builder, index) {
                              return ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: ProfilePicture(
                                  user: oFriends[index],
                                  size: 45,
                                  color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black,
                                  backgroundColor: Theme.of(context).colorScheme.surface,
                                ),
                                title: Text(oFriends[index].username),
                              );
                            },
                          );
                        } else {
                          return const Messenger(message: 'Error: Empty list');
                        }
                      } else if (snapshot.hasError) {
                        return Messenger(message: 'Error ${snapshot.error}');
                      }

                      return const CustomLoader();
                    },
                  )
                : const Messenger(message: 'Please share your location to view your friend list'),
          ),
        ],
      ),
    );
  }
}