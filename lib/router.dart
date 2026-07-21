import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/client_home_screen.dart';
import 'screens/provider_home_screen.dart';
import 'screens/provider_profile_hub_screen.dart';
import 'screens/verification_upload_screen.dart';
import 'screens/verification_pending_screen.dart';
import 'screens/admin_verification_screen.dart';
import 'screens/admin_dashboard_screen.dart';
import 'screens/admin_users_screen.dart';
import 'screens/admin_bookings_screen.dart';
import 'screens/admin_analytics_screen.dart';
import 'screens/provider_profile_editor_screen.dart';
import 'screens/service_management_screen.dart';
import 'screens/gallery_management_screen.dart';
import 'screens/provider_public_profile_screen.dart';
import 'screens/subscription_screen.dart';
import 'screens/booking_screen.dart';
import 'screens/client_bookings_screen.dart';
import 'screens/provider_bookings_screen.dart';
import 'screens/booking_detail_screen.dart';
import 'screens/chat_screen.dart';
import 'screens/tracking_screen.dart';
import 'screens/payment_screen.dart';
import 'screens/provider_earnings_screen.dart';
import 'screens/browse_screen.dart';
import 'screens/review_screen.dart';
import 'screens/provider_reviews_screen.dart';
import 'screens/favorites_screen.dart';
import 'screens/promotion_management_screen.dart';
import 'screens/notifications_screen.dart';
import 'screens/smart_match_screen.dart';
import 'widgets/client_shell.dart';
import 'widgets/provider_shell.dart';
import 'supabase_client.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

bool _isProvider() {
  final meta = supabase.auth.currentUser?.userMetadata;
  return meta?['user_type'] == 'provider';
}

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/home',
  redirect: (context, state) {
    final session = supabase.auth.currentSession;
    final isAuth = session != null;
    final loc = state.matchedLocation;
    final isAuthRoute = loc == '/login' || loc == '/register';

    if (!isAuth) return isAuthRoute ? null : '/login';

    // Authenticated: route away from auth screens and root to the right shell
    if (isAuthRoute || loc == '/') {
      return _isProvider() ? '/provider/home' : '/home';
    }
    // Providers landing on client home go to their own home
    if (loc == '/home' && _isProvider()) return '/provider/home';
    // Clients landing on provider home go to theirs
    if (loc == '/provider/home' && !_isProvider()) return '/home';

    return null;
  },
  routes: [
    // ─────────────────────────────────────────────────────────────
    // Root redirect (fixes GoException: no routes for /)
    // ─────────────────────────────────────────────────────────────
    GoRoute(
      path: '/',
      redirect: (_, __) => '/home',
    ),

    // ─────────────────────────────────────────────────────────────
    // Auth (no shell)
    // ─────────────────────────────────────────────────────────────
    GoRoute(path: '/login',    builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),

    // ─────────────────────────────────────────────────────────────
    // CLIENT SHELL — bottom nav: Home | Browse | Bookings | Favourites
    // ─────────────────────────────────────────────────────────────
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          ClientShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(path: '/home', builder: (_, __) => const ClientHomeScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/browse', builder: (_, __) => const BrowseScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/client/bookings', builder: (_, __) => const ClientBookingsScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/favorites', builder: (_, __) => const FavoritesScreen()),
        ]),
      ],
    ),

    // ─────────────────────────────────────────────────────────────
    // PROVIDER SHELL — bottom nav: Home | Bookings | Earnings | Profile
    // ─────────────────────────────────────────────────────────────
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          ProviderShell(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(path: '/provider/home', builder: (_, __) => const ProviderHomeScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/provider/bookings', builder: (_, __) => const ProviderBookingsScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/earnings', builder: (_, __) => const ProviderEarningsScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/provider/profile', builder: (_, __) => const ProviderProfileHubScreen()),
        ]),
      ],
    ),

    // ─────────────────────────────────────────────────────────────
    // Full-screen routes (no shell) — pushed on root navigator
    // ─────────────────────────────────────────────────────────────

    // Identity Verification (Stage 2)
    GoRoute(
      path: '/verify',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (_, __) => const VerificationUploadScreen(),
    ),
    GoRoute(
      path: '/verify/pending',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (_, __) => const VerificationPendingScreen(),
    ),

    // Admin (Stage 14)
    GoRoute(
      path: '/admin/verify',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (_, __) => const AdminVerificationScreen(),
    ),
    GoRoute(
      path: '/admin/dashboard',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (_, __) => const AdminDashboardScreen(),
    ),
    GoRoute(
      path: '/admin/users',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (_, __) => const AdminUsersScreen(),
    ),
    GoRoute(
      path: '/admin/bookings',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (_, __) => const AdminBookingsScreen(),
    ),
    GoRoute(
      path: '/admin/analytics',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (_, __) => const AdminAnalyticsScreen(),
    ),

    // Provider Management (Stage 3)
    GoRoute(
      path: '/provider/profile/edit',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (_, __) => const ProviderProfileEditorScreen(),
    ),
    GoRoute(
      path: '/provider/services',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (_, __) => const ServiceManagementScreen(),
    ),
    GoRoute(
      path: '/provider/gallery',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (_, __) => const GalleryManagementScreen(),
    ),

    // Subscription (Stage 4)
    GoRoute(
      path: '/provider/subscription',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (_, __) => const SubscriptionScreen(),
    ),

    // Promotions (Stage 12)
    GoRoute(
      path: '/provider/promotions',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (_, __) => const PromotionManagementScreen(),
    ),

    // Notifications (Stage 13) & Smart Match (Stage 15)
    GoRoute(
      path: '/notifications',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (_, __) => const NotificationsScreen(),
    ),
    GoRoute(
      path: '/recommended',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (_, __) => const SmartMatchScreen(),
    ),

    // Booking Flows (Create, Detail)
    GoRoute(
      path: '/book/:providerId/:serviceId',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (_, state) => BookingScreen(
        providerId: state.pathParameters['providerId']!,
        serviceId:  state.pathParameters['serviceId']!,
      ),
    ),
    GoRoute(
      path: '/booking/:id',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (_, state) => BookingDetailScreen(
        bookingId: state.pathParameters['id']!,
      ),
    ),

    // Chat (Stage 7)
    GoRoute(
      path: '/chat/:bookingId',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (_, state) => ChatScreen(
        bookingId: state.pathParameters['bookingId']!,
      ),
    ),

    // Live Tracking (Stage 6B)
    GoRoute(
      path: '/tracking/:bookingId',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (_, state) => TrackingScreen(
        bookingId: state.pathParameters['bookingId']!,
      ),
    ),

    // Payment (Stage 8)
    GoRoute(
      path: '/payment/:bookingId',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (_, state) => PaymentScreen(
        bookingId: state.pathParameters['bookingId']!,
      ),
    ),

    // Reviews (Stage 9)
    GoRoute(
      path: '/review/:bookingId',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (_, state) => ReviewScreen(
        bookingId: state.pathParameters['bookingId']!,
      ),
    ),
    GoRoute(
      path: '/provider/:id/reviews',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (_, state) => ProviderReviewsScreen(
        providerId: state.pathParameters['id']!,
      ),
    ),

    // ─────────────────────────────────────────────────────────────
    // DYNAMIC ROUTES – MUST BE LAST
    // ─────────────────────────────────────────────────────────────
    GoRoute(
      path: '/provider/:id',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (_, state) => ProviderPublicProfileScreen(
        providerId: state.pathParameters['id']!,
      ),
    ),
  ],
);
