import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_near/services/firestore.dart';
import 'package:flutter_near/services/location.dart';
import 'package:flutter_near/models/near_user.dart';
import 'package:flutter_near/services/spatial_db.dart';
import 'package:flutter_near/services/user_provider.dart';
import 'package:flutter_near/widgets/custom_loader.dart';
import 'package:flutter_near/widgets/profile_picture.dart';
import 'package:flutter_near/pages/friend_page.dart';
import 'package:flutter_near/widgets/slide_page_route.dart';
import 'package:provider/provider.dart';

class FriendsPage extends StatefulWidget {
  const FriendsPage({
    super.key,
  });

  @override
  State<FriendsPage> createState() => _FriendsPageState();
}

class _FriendsPageState extends State<FriendsPage> {
  bool isLoading = false;
  NearUser? currentUser;
  Future<List<NearUser>>? futureList;
  String locationPermissionStatus = 'Not asked';

  @override
  void initState() {
    super.initState();
    final userProvider = context.read<UserProvider>();
    currentUser = userProvider.nearUser;
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
      Point random = await SpatialDb().getRandomKNN(
        currentUser!.kAnonymity,
        pos.longitude,
        pos.latitude,
        50
      );
      await FirestoreService().setLocation(currentUser!.uid, random.lon, random.lat);
    }

    setState(() {
      isLoading = false;
      futureList = FirestoreService().getFriends(currentUser!.uid);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: const Row(
            children: [
              Text(
                'Friends',
                style: TextStyle(fontSize: 24),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: currentUser!.location != null
            ? FutureBuilder(
              future: futureList,
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  List<NearUser> friends = snapshot.data!;
                  List<NearUser> oFriends = currentUser!
                      .getUsersOrderedByLocation(friends);
    
                  return ListView.builder(
                    itemCount: oFriends.length,
                    itemBuilder: (context, index) {
                      return ListTile(
                        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                              .surfaceContainerHigh,
                        ),
                        title: Text(oFriends[index].username),
                        onTap: () {
                          Navigator.push(
                            context,
                            SlidePageRoute(
                              page: FriendPage(
                                friend: oFriends[index],
                                currentUser: currentUser!,
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
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Location permission is required to view friends nearby. Please grant permission.',
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () async {
                      final String? permissionStatus = await LocationService().askForPermissions();
                      if (permissionStatus == null) {
                        setState(() {
                          locationPermissionStatus = 'Granted';
                        });
                      } else {
                        setState(() {
                          locationPermissionStatus = permissionStatus;
                        });
                      }
                    },
                    child: Text(locationPermissionStatus),
                  ),
                ],
              ),
            ),
        ),
      ],
    );
  }
}