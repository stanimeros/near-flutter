import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_near/common/near_user.dart';
import 'package:flutter_near/widgets/profile_picture.dart';
import 'package:image_picker/image_picker.dart';

class PickProfilePicture extends StatefulWidget {
  final NearUser user;
  final Function pickImage;

  final double size;
  final Color color;
  final Color backgroundColor;

  const PickProfilePicture({
    super.key,
    required this.user,
    required this.pickImage,
    required this.size,
    required this.color,
    required this.backgroundColor,
  });

  @override
  State<PickProfilePicture> createState() => _PickProfilePictureState();
}

class _PickProfilePictureState extends State<PickProfilePicture> {
  XFile? newProfilePicture;
  final ImagePicker picker = ImagePicker();

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async{
        XFile? temp = await widget.pickImage();
        setState(() {
          newProfilePicture = temp;
        });
      },
      child: Container(
        clipBehavior: Clip.hardEdge,
        decoration: const BoxDecoration(
          shape: BoxShape.circle
        ),
        alignment: Alignment.center,
        child: newProfilePicture != null ?
        Image.file(
          width: 50,
          height: 50,
          fit: BoxFit.cover,
          File(newProfilePicture!.path)
        ) : ProfilePicture(
          user: widget.user,
          size: widget.size,
          color: widget.color,
          backgroundColor: widget.backgroundColor
        )
      ),
    );
  }
}