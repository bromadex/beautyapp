import 'package:go_router/go_router.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/home_screen.dart';
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
import 'supabase_client.dart';
import 'screens/browse_screen.dart';
import 'screens/review_screen.dart';
import 'screens/provider_reviews_screen.dart';
import 'screens/favorites_screen.dart';
import 'screens/promotion_management_screen.dart';
import 'screens/notifications_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/login',
  redirect: (context, state) {
    final session = supabase.auth.currentSession;
    final isAuth = session != null;
    final isAuthRoute =
        state.matchedLocation == '/login' ||
        state.matchedLocation == '/register';
    if (!isAuth && !isAuthRoute) return '/login';
    if (isAuth && isAuthRoute) return '/home';
    return null;
  },
  routes: [

    GoRoute(
    path: '/review/:bookingId',
    builder: (_, state) => ReviewScreen(
    bookingId: state.pathParameters['bookingId']!,
    ),
    ),
  GoRoute(
  path: '/provider/:id/reviews',
  builder: (_, state) => ProviderReviewsScreen(
    providerId: state.pathParameters['id']!,
  ),
  ),
    // ─────────────────────────────────────────────────────────────
    // Browse (Stage 11 placeholder)
    // ─────────────────────────────────────────────────────────────
    GoRoute(path: '/browse', builder: (_, __) => const BrowseScreen()),
    GoRoute(path: '/favorites', builder: (_, __) => const FavoritesScreen()),
    // ─────────────────────────────────────────────────────────────
    // Auth & Home
    // ─────────────────────────────────────────────────────────────
    GoRoute(path: '/login',    builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/register', builder: (_, __) => const RegisterScreen()),
    GoRoute(path: '/home',     builder: (_, __) => const HomeScreen()),

    // ─────────────────────────────────────────────────────────────
    // Identity Verification (Stage 2)
    // ─────────────────────────────────────────────────────────────
    GoRoute(path: '/verify', builder: (_, __) => const VerificationUploadScreen()),
    GoRoute(path: '/verify/pending', builder: (_, __) => const VerificationPendingScreen()),
    GoRoute(path: '/admin/verify',     builder: (_, __) => const AdminVerificationScreen()),
    GoRoute(path: '/admin/dashboard', builder: (_, __) => const AdminDashboardScreen()),
    GoRoute(path: '/admin/users',     builder: (_, __) => const AdminUsersScreen()),
    GoRoute(path: '/admin/bookings',  builder: (_, __) => const AdminBookingsScreen()),
    GoRoute(path: '/admin/analytics', builder: (_, __) => const AdminAnalyticsScreen()),

    // ─────────────────────────────────────────────────────────────
    // Provider Management (Stage 3)
    // ─────────────────────────────────────────────────────────────
    GoRoute(path: '/provider/profile/edit', builder: (_, __) => const ProviderProfileEditorScreen()),
    GoRoute(path: '/provider/services',     builder: (_, __) => const ServiceManagementScreen()),
    GoRoute(path: '/provider/gallery',      builder: (_, __) => const GalleryManagementScreen()),

    // ─────────────────────────────────────────────────────────────
    // Subscription (Stage 4)
    // ─────────────────────────────────────────────────────────────
    GoRoute(path: '/provider/subscription', builder: (_, __) => const SubscriptionScreen()),

    // ─────────────────────────────────────────────────────────────
    // Promotions (Stage 12)
    // ─────────────────────────────────────────────────────────────
    GoRoute(path: '/provider/promotions', builder: (_, __) => const PromotionManagementScreen()),

    // ─────────────────────────────────────────────────────────────
    // Notifications (Stage 13)
    // ─────────────────────────────────────────────────────────────
    GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),

    // ─────────────────────────────────────────────────────────────
    // Bookings (Stage 5)
    // ─────────────────────────────────────────────────────────────
    GoRoute(path: '/provider/bookings', builder: (_, __) => const ProviderBookingsScreen()),
    GoRoute(path: '/client/bookings',   builder: (_, __) => const ClientBookingsScreen()),

    // ─────────────────────────────────────────────────────────────
    // Booking Flows (Create, Detail, Navigation)
    // ─────────────────────────────────────────────────────────────
    GoRoute(
      path: '/book/:providerId/:serviceId',
      builder: (_, state) => BookingScreen(
        providerId: state.pathParameters['providerId']!,
        serviceId:  state.pathParameters['serviceId']!,
      ),
    ),
    GoRoute(
      path: '/booking/:id',
      builder: (_, state) => BookingDetailScreen(
        bookingId: state.pathParameters['id']!,
      ),
    ),

    // ─────────────────────────────────────────────────────────────
    // Chat (Stage 7)
    // ─────────────────────────────────────────────────────────────
    GoRoute(
      path: '/chat/:bookingId',
      builder: (_, state) => ChatScreen(
        bookingId: state.pathParameters['bookingId']!,
      ),
    ),

    // ─────────────────────────────────────────────────────────────
    // Live Tracking (Stage 6B)
    // ─────────────────────────────────────────────────────────────
    GoRoute(
      path: '/tracking/:bookingId',
      builder: (_, state) => TrackingScreen(
        bookingId: state.pathParameters['bookingId']!,
      ),
    ),

    // ─────────────────────────────────────────────────────────────
    // Payment & Earnings (Stage 8)
    // ─────────────────────────────────────────────────────────────
    GoRoute(
      path: '/payment/:bookingId',
      builder: (_, state) => PaymentScreen(
        bookingId: state.pathParameters['bookingId']!,
      ),
    ),
    GoRoute(
      path: '/earnings',
      builder: (_, __) => const ProviderEarningsScreen(),
    ),

    // ─────────────────────────────────────────────────────────────
    // DYNAMIC ROUTES – MUST BE LAST
    // ─────────────────────────────────────────────────────────────
    GoRoute(
      path: '/provider/:id',
      builder: (_, state) => ProviderPublicProfileScreen(
        providerId: state.pathParameters['id']!,
      ),
    ),
  ],
);