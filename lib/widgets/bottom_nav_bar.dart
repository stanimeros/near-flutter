import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class BottomNavBar extends StatelessWidget {
  final Function changePage;
  final int currentIndex;

  const BottomNavBar({
    super.key,
    required this.changePage,
    required this.currentIndex,
  });

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: currentIndex,
      onDestinationSelected: (index) => changePage(index),
      destinations: const [
        NavigationDestination(
          icon: Icon(LucideIcons.users),
          label: 'Friends',
        ),
        NavigationDestination(
          icon: Icon(LucideIcons.mapPin),
          label: 'Map',
        ),
        NavigationDestination(
          icon: Icon(LucideIcons.bell),
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