import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import 'ui.dart';

class ProviderShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const ProviderShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    // Back button funnels to Home before exiting: on any other tab, back
    // returns to Home; only a second back from Home leaves the app.
    return PopScope(
      canPop: navigationShell.currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) navigationShell.goBranch(0);
      },
      child: Scaffold(
      body: navigationShell,
      bottomNavigationBar: BeauNavBar(
        index: navigationShell.currentIndex,
        onTap: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        items: const [
          (icon: TablerIcons.sun, label: 'Today', badge: 0),
          (icon: TablerIcons.calendar_event, label: 'Calendar', badge: 0),
          (icon: TablerIcons.users, label: 'Clients', badge: 0),
          (icon: TablerIcons.user_circle, label: 'Me', badge: 0),
        ],
      ),
      ),
    );
  }
}
