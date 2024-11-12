import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class BottomNavBar extends StatefulWidget {
  final Function changePage;
  
  const BottomNavBar({
    super.key,
    required this.changePage
  });

  @override
  State<BottomNavBar> createState() => _BottomNavBarState();
}

class _BottomNavBarState extends State<BottomNavBar> {

  int currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      currentIndex: currentIndex,
      onTap:(index) {
        widget.changePage(index);
        setState(() {
          currentIndex = index;
        });
      },
      items: const [
        BottomNavigationBarItem(
          icon: Icon(LucideIcons.home),
          label: 'Feed',
        ),
        BottomNavigationBarItem(
          icon: Icon(LucideIcons.users),
          label: 'Friends',
        ),
        BottomNavigationBarItem(
          icon: Icon(LucideIcons.plusCircle),
          label: 'Requests',
        ),
        BottomNavigationBarItem(
          icon: Icon(LucideIcons.user2),
          label: 'Profile',
        ),
      ]
    );
  }
}