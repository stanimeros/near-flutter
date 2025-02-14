import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_near/models/near_user.dart';

class ProfilePicture extends StatelessWidget {

  final NearUser user;
  final double size;
  final Color color;
  final Color backgroundColor;

  const ProfilePicture({
    super.key,
    required this.user,
    required this.size,
    required this.color,
    required this.backgroundColor
  });


  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.hardEdge,
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            user.username.substring(0,1).toUpperCase(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: size/2.5,
              fontWeight: FontWeight.bold,
              color: color
            ),
          ),
          Visibility(
            visible: user.imageURL.isNotEmpty,
            child: CachedNetworkImage(
              width: size,
              height: size,
              fit: BoxFit.cover,
              imageUrl: user.imageURL
            ),
          ),
        ],
      )
    );
  }
}