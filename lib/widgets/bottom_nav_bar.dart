import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

class BottomNavBar extends StatefulWidget {
  final Function changePage;
  final int currentIndex;

  const BottomNavBar({
    super.key,
    required this.changePage,
    required this.currentIndex,
  });

  @override
  State<BottomNavBar> createState() => _BottomNavBarState();
}

class _BottomNavBarState extends State<BottomNavBar> {
  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: widget.currentIndex,
      onDestinationSelected: (index) => widget.changePage(index),
      destinations: const [
        NavigationDestination(
          icon: Icon(LucideIcons.users),
          label: 'Friends',
        ),
        NavigationDestination(
          icon: Icon(LucideIcons.userSearch),
          label: 'Requests',
        ),
        NavigationDestination(
          icon: Icon(LucideIcons.user),
          label: 'Profile',
        ),
      ],
    );
  }
}