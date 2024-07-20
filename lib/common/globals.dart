library flutter_memoire.globals;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_near/common/near_user.dart';

NearUser? user;
GeoPoint? deviceLocation;

Color backgroundColor = const Color.fromARGB(255, 25, 25, 25);
Color backgroundColor2 = const Color.fromARGB(255, 45, 45, 45);
Color backgroundColor3 = const Color.fromARGB(255, 65, 65, 65);
Color textColor = const Color.fromARGB(255, 230, 230, 230);
Color textColor2 = const Color.fromARGB(255, 210, 210, 210);

Color rejectColor = const Color.fromARGB(255, 200, 15, 0);
Color cachedImageColor = const Color.fromARGB(15, 255, 255, 255);
Color skeletonTileColor = const Color.fromARGB(5, 255, 255, 255);
Color skeletonShadowColor = const Color.fromARGB(10, 255, 255, 255);






