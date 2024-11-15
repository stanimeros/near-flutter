import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_near/common/firestore_service.dart';
import 'package:flutter_near/common/db_helper.dart';
import 'package:flutter_near/common/location_service.dart';
import 'package:flutter_near/common/near_user.dart';
import 'package:flutter_near/widgets/custom_loader.dart';
import 'package:flutter_near/widgets/messenger.dart';
import 'package:flutter_near/widgets/profile_picture.dart';
import 'package:dart_jts/dart_jts.dart' as jts;
import 'package:flutter_near/common/globals.dart' as globals;

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

  void fetchData () async {
    setState(() {
      isLoading = true;
    });

    await DbHelper().emptyTable(DbHelper.pois);
    await DbHelper().emptyTable(DbHelper.keys);

    GeoPoint? pos = await LocationService().getCurrentPosition();
    if (pos != null){
      debugPrint('Location: ${pos.latitude.toString()}, ${pos.longitude.toString()}');

      jts.Envelope boundingBox = await DbHelper().createBoundingBox(pos.longitude, pos.latitude, 250);
      List<jts.Point> keys = await DbHelper().getPointsInBoundingBox(boundingBox, DbHelper.keys); 

      if (keys.isEmpty){
        await DbHelper().downloadPointsFromOSM(boundingBox);
        await DbHelper().addPointToDb(pos.longitude, pos.latitude, DbHelper.keys);
      } 

      jts.Point random = await DbHelper().getRandomKNN(globals.user!.kAnonymity, pos.longitude, pos.latitude, 50);
      debugPrint('New Location: ${random.getY()}, ${random.getX()}');
      await FirestoreService().setLocation(random.getX(), random.getY());
    }

    setState(() {
      isLoading = false;
      futureList = FirestoreService().getFriends();
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
                'Feed',
                style: TextStyle(
                  fontSize: 24
                ),
              ),
            ],
          ),
          const SizedBox(
            height: 16
          ),
          Expanded(
            child: globals.user!.location != null ?
            FutureBuilder(
              future: futureList, 
              builder: (context, snapshot){
                if (snapshot.hasData){
                  List<NearUser> friends = snapshot.data!;
                  List<NearUser> oFriends = globals.user!.getUsersOrderedByLocation(friends);

                  // if (!oFriends.any((friend) => friend.uid == 'device')){
                  //   NearUser device = NearUser(
                  //     uid: 'device', 
                  //     username: 'device', 
                  //     email: 'device', 
                  //     joined: globals.user!.joined,
                  //     location: globals.deviceLocation
                  //   );
                  //   oFriends.insert(0, device);
                  // }

                  if (!oFriends.any((friend) => friend.uid == globals.user!.uid)){
                    oFriends.insert(0, globals.user!);
                  }

                  if (oFriends.isNotEmpty){
                    return ListView.builder(
                      shrinkWrap: true,
                      itemCount: oFriends.length,
                      itemBuilder: (builder, index){
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: ProfilePicture(
                            user: oFriends[index],
                            size: 45,
                            color: globals.textColor, 
                            backgroundColor: globals.cachedImageColor
                          ),
                          title: Text(oFriends[index].username),
                          // trailing: Text(
                          //   globals.user!.getConvertedDistanceBetweenUser(oFriends[index])
                          // ),
                        );
                      }
                    );
                  }else{
                    return const Messenger(message: 'Error: Empty list');
                  }
                }else if (snapshot.hasError){
                  return Messenger(message: 'Error ${snapshot.error}');
                }
            
                return const CustomLoader();
              }
            ) :
            const Messenger(message: 'Please share your location to view your friend list')
          )
        ],
      ),
    );
  }
}