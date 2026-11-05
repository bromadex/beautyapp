import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import '../services/cart.dart';
import 'ui.dart';

class ClientShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;
  const ClientShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    Cart.instance.load();
    // Back button funnels to Home before exiting: on any other tab, back
    // returns to Home; only a second back from Home leaves the app.
    return PopScope(
      canPop: navigationShell.currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) navigationShell.goBranch(0);
      },
      child: ListenableBuilder(
        listenable: Cart.instance,
        builder: (context, _) => AdaptiveTabScaffold(
        subtitle: 'Book beauty pros',
        body: navigationShell,
        index: navigationShell.currentIndex,
        onTap: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        items: [
          (icon: TablerIcons.home, label: 'Home', badge: 0),
          (icon: TablerIcons.search, label: 'Browse', badge: 0),
          (icon: TablerIcons.calendar_event, label: 'Bookings', badge: 0),
          (icon: TablerIcons.shopping_bag, label: 'Shop', badge: Cart.instance.count),
          (icon: TablerIcons.heart, label: 'Saved', badge: 0),
        ],
      ),
      ),
    );
  }
}
