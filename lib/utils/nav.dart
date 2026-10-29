import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../supabase_client.dart';

/// Where "back" goes when there's no earlier page (a link was opened, the
/// page was refreshed, or the app was opened from a notification).
/// Every page has a sensible parent, ending at the user's home tab.

const _tabs = {
  '/home', '/browse', '/client/bookings', '/favorites',
  '/provider/home', '/provider/calendar', '/provider/clients', '/provider/profile',
};

/// Pages that are never under anything (sign-in and sign-up).
const _roots = {'/login', '/register', '/welcome', '/'};

/// Pro tools reached from the pro's Profile tab.
const _proTools = {
  'profile', 'services', 'gallery', 'subscription', 'promotions', 'availability', 'referrals',
  'salon', 'location', 'products', 'settings', 'service-requests',
};

bool get _isPro => supabase.auth.currentUser?.userMetadata?['user_type'] == 'provider';

String homeTab() => _isPro ? '/provider/home' : '/home';

bool isTab(String path) => _tabs.contains(path);

bool isRoot(String path) => _roots.contains(path) || _tabs.contains(path);

/// The parent of [path], or null for tabs and sign-in pages.
String? parentOf(String path) {
  if (isRoot(path)) return null;
  final s = Uri.parse(path).pathSegments;
  if (s.isEmpty) return null;

  switch (s[0]) {
    case 'booking':
      return _isPro ? '/provider/bookings' : '/client/bookings';
    case 'chat':
    case 'pay':
    case 'payment':
    case 'review':
    case 'dispute':
      return s.length > 1 ? '/booking/${s[1]}' : homeTab();
    case 'book':
      return s.length > 1 ? '/provider/${s[1]}' : '/browse';
    case 'salon':
      return '/browse';
    case 'admin':
      return path == '/admin/dashboard' ? '/account/settings' : '/admin/dashboard';
    case 'earnings':
      return '/provider/home';
    case 'verify':
      return _isPro ? '/provider/profile' : '/account/settings';
    case 'client-notes':
      return '/provider/clients';
    case 'pay-beautap':
      return '/provider/profile';
    case 'service-requests':
      return homeTab();
    case 'service-request':
      if (s.length > 1 && s[1] == 'create') return '/service-requests';
      if (s.length > 2 && s[2] == 'quote') return '/service-request/${s[1]}';
      return _isPro ? '/provider/service-requests' : '/service-requests';
    case 'provider':
      if (s.length < 2) return homeTab();
      final second = s[1];
      if (second == 'bookings') return '/provider/home';
      if (second == 'add-booking') return '/provider/calendar';
      if (second == 'clients') return '/provider/clients';
      if (second == 'profile' && s.length > 2) return '/provider/profile';
      if (_proTools.contains(second)) return '/provider/profile';
      // A pro's public page, or its reviews.
      if (s.length > 2 && s[2] == 'reviews') return '/provider/$second';
      return _isPro ? homeTab() : '/browse';
  }
  if (path.startsWith('/@')) return '/browse';
  return homeTab();
}

/// The pages under [path], from the home tab down to its parent.
List<String> parentChain(String path) {
  final chain = <String>[];
  var p = parentOf(path);
  while (p != null && chain.length < 6 && !chain.contains(p)) {
    chain.insert(0, p);
    p = parentOf(p);
  }
  if (chain.isEmpty || !isTab(chain.first)) chain.insert(0, homeTab());
  return chain;
}

String _here(BuildContext context) => GoRouterState.of(context).uri.path;

/// Back: the previous page if there is one, otherwise this page's parent.
void goBack(BuildContext context) {
  if (context.canPop()) {
    context.pop();
    return;
  }
  final parent = parentOf(_here(context));
  context.go(parent ?? homeTab());
}

/// Open [location] with its parent pages underneath, so back works:
/// e.g. after booking, Bookings sits under the new booking.
void openWithParents(BuildContext context, String location) => openRoute(GoRouter.of(context), location);

/// Same as [openWithParents], for code without a BuildContext (notifications).
void openRoute(GoRouter router, String location) {
  final path = Uri.parse(location).path;
  if (isRoot(path)) {
    router.go(location);
    return;
  }
  final chain = parentChain(path);
  router.go(chain.first);
  for (final p in chain.skip(1)) {
    router.push(p);
  }
  router.push(location);
}

/// The back arrow for custom headers. AppBars get it automatically.
class AppBackButton extends StatelessWidget {
  final Color? color;
  const AppBackButton({super.key, this.color});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Back',
        icon: Icon(TablerIcons.chevron_left, size: 26, color: color),
        onPressed: () => goBack(context),
      );
}
