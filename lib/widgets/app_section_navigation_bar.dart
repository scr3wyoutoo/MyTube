import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';

class AppSectionNavigationBar extends StatelessWidget {
  const AppSectionNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.keyPrefix,
  });

  static const double compactHeight = 52;

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      key: ValueKey('$keyPrefix-section-navigation'),
      height: compactHeight,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      destinations: [
        NavigationDestination(
          key: ValueKey('$keyPrefix-section-search'),
          icon: const Icon(Icons.search_outlined),
          selectedIcon: const Icon(Icons.search),
          label: context.l10n.search,
        ),
        NavigationDestination(
          key: ValueKey('$keyPrefix-section-hot-music'),
          icon: const Icon(Icons.music_note_outlined, size: 27),
          selectedIcon: const Icon(
            Icons.music_note,
            size: 27,
            color: Colors.deepOrange,
          ),
          label: context.l10n.hotMusic,
        ),
        NavigationDestination(
          key: ValueKey('$keyPrefix-section-profile'),
          icon: const Icon(Icons.person_outline),
          selectedIcon: const Icon(Icons.person),
          label: context.l10n.myProfile,
        ),
      ],
    );
  }
}
