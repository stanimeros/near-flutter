import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_near/common/globals.dart' as globals;

class SkeletonChat extends StatelessWidget {
  final double height;

  const SkeletonChat({
    super.key,
    required this.height
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: globals.skeletonTileColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: globals.skeletonShadowColor,
              spreadRadius: 12,
              blurRadius: 24,
            )
          ]
        ),
      )
      .animate(
        onComplete: (controller) {
          controller.repeat();
        },
      ).slideX(
        duration: const Duration(milliseconds: 2500),
        curve: Curves.linear,
        begin: -1.5,
        end: 1.5,
      ),
    );
  }
}