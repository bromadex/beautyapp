import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../supabase_client.dart';
import '../services/location_service.dart';
import '../theme.dart';
import '../widgets/travel_mode_sheet.dart';

class TrackingScreen extends StatefulWidget {
  final String bookingId;
  const TrackingScreen({super.key, required this.bookingId});

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  final _locationService = LocationService();

  Map<String, dynamic>? _booking;
  Map<String, dynamic>? _myLocation;
  Map<String, dynamic>? _otherLocation;

  bool _loading = true;
  bool _isProvider = false;
  String? _travelMode;
  String? _bookingStatus;

  StreamSubscription? _locationSub;
  StreamSubscription? _bookingSub;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    Map<String, dynamic> booking;
    try {
      booking = await supabase
          .from('bookings')
          .select('*, services(service_name, duration_minutes)')
          .eq('id', widget.bookingId)
          .single();
    } catch (_) {
      if (mounted) Navigator.of(context).pop();
      return;
    }

    _booking = booking;
    _isProvider = booking['provider_id'] == uid;
    _travelMode = booking['travel_mode'];
    _bookingStatus = booking['status'];

    setState(() => _loading = false);

    if (_travelMode == null && _bookingStatus == 'confirmed') {
      WidgetsBinding.instance.addPostFrameCallback((_) => _promptTravelMode());
    }

    _locationSub = supabase
        .from('booking_locations')
        .stream(primaryKey: ['id'])
        .eq('booking_id', widget.bookingId)
        .listen(_onLocationUpdate);

    _bookingSub = supabase
        .from('bookings')
        .stream(primaryKey: ['id'])
        .eq('id', widget.bookingId)
        .listen((rows) {
          if (rows.isNotEmpty) {
            final b = rows.first;
            setState(() {
              _travelMode = b['travel_mode'];
              _bookingStatus = b['status'];
            });
            if (_bookingStatus == 'completed' ||
                _bookingStatus == 'cancelled') {
              _locationService.stopSharing();
            }
          }
        });

    if (_bookingStatus == 'confirmed') {
      await _locationService.startSharing(widget.bookingId);
    }
  }

  void _onLocationUpdate(List<Map<String, dynamic>> rows) {
    final uid = supabase.auth.currentUser!.id;
    for (final row in rows) {
      if (row['user_id'] == uid) {
        _myLocation = row;
      } else {
        _otherLocation = row;
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _promptTravelMode() async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => TravelModeSheet(isProvider: _isProvider),
    );

    if (result != null) {
      await supabase
          .from('bookings')
          .update({'travel_mode': result})
          .eq('id', widget.bookingId);
      setState(() => _travelMode = result);
      if (result != 'fixed_location') {
        await _locationService.startSharing(widget.bookingId);
      }
    }
  }

  Future<void> _markEnRoute() async {
    await supabase.from('bookings').update({
      'en_route_at': DateTime.now().toIso8601String(),
    }).eq('id', widget.bookingId);
    await _locationService.startSharing(widget.bookingId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Location sharing started'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        ),
      );
    }
  }

  Future<void> _markArrived() async {
    await supabase.from('bookings').update({
      'arrived_at': DateTime.now().toIso8601String(),
    }).eq('id', widget.bookingId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Marked as Arrived'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        ),
      );
    }
  }

  Future<void> _openInMaps() async {
    if (_otherLocation == null) return;
    final lat = _otherLocation!['latitude'];
    final lng = _otherLocation!['longitude'];
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');
    if (await canLaunchUrl(uri)) launchUrl(uri);
  }

  String get _travelModeLabel {
    switch (_travelMode) {
      case 'provider_to_client':
        return _isProvider ? 'You are going to the client' : 'Stylist coming to you';
      case 'client_to_provider':
        return _isProvider ? 'Client is coming to you' : 'You are going to the stylist';
      case 'fixed_location':
        return 'Fixed salon location';
      default:
        return 'Travel mode not set';
    }
  }

  IconData get _travelModeIcon {
    switch (_travelMode) {
      case 'fixed_location':
        return Icons.store_rounded;
      case 'provider_to_client':
        return _isProvider ? Icons.directions_walk_rounded : Icons.my_location_rounded;
      case 'client_to_provider':
        return !_isProvider ? Icons.directions_walk_rounded : Icons.my_location_rounded;
      default:
        return Icons.swap_horiz_rounded;
    }
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _bookingSub?.cancel();
    _locationService.stopSharing();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    final bool iAmTravelling =
        (_travelMode == 'provider_to_client' && _isProvider) ||
        (_travelMode == 'client_to_provider' && !_isProvider);
    final bool otherIsTravelling =
        (_travelMode == 'provider_to_client' && !_isProvider) ||
        (_travelMode == 'client_to_provider' && _isProvider);
    final bool isFixed = _travelMode == 'fixed_location';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Tracking'),
        actions: [
          if (_travelMode == null && _bookingStatus == 'confirmed')
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: TextButton.icon(
                onPressed: _promptTravelMode,
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: const Text('Set Mode'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Travel mode banner with gradient
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: AppColors.primaryGradient,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: AppRadius.smAll,
                  ),
                  child: Icon(
                    _travelModeIcon,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    _travelModeLabel,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (_travelMode == null)
                  GestureDetector(
                    onTap: _promptTravelMode,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Set up',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Status indicator
          if (_bookingStatus != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0,
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: StatusColors.background(_bookingStatus!),
                  borderRadius: AppRadius.smAll,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: StatusColors.foreground(_bookingStatus!),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      StatusColors.label(_bookingStatus!),
                      style: TextStyle(
                        color: StatusColors.foreground(_bookingStatus!),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Location info card
          Expanded(
            child: Center(
              child: Padding(
                padding: AppSpacing.screenPadding,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Location pin with animated ring
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        shape: BoxShape.circle,
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.location_on_rounded,
                          size: 48,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    Text(
                      _otherLocation != null
                          ? '${_isProvider ? "Client" : "Stylist"} location found'
                          : 'Waiting for location data...',
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    if (_otherLocation != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        '${_otherLocation!['latitude'].toStringAsFixed(5)}, '
                        '${_otherLocation!['longitude'].toStringAsFixed(5)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.xxl),
                      FilledButton.icon(
                        onPressed: _openInMaps,
                        icon: const Icon(Icons.map_outlined, size: 18),
                        label: const Text('Navigate in Google Maps'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                        ),
                      ),
                    ],
                    if (_otherLocation == null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Location will appear once sharing begins',
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          // Action buttons
          if (_bookingStatus == 'confirmed')
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (iAmTravelling) ...[
                    FilledButton.icon(
                      onPressed: _markEnRoute,
                      icon: const Icon(Icons.navigation_rounded, size: 18),
                      label: const Text("I'm On My Way"),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    FilledButton.icon(
                      onPressed: _markArrived,
                      icon: const Icon(Icons.place_rounded, size: 18),
                      label: const Text("I've Arrived"),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.success,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ] else if (otherIsTravelling) ...[
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: AppColors.info.withValues(alpha: 0.08),
                        borderRadius: AppRadius.mdAll,
                        border: Border.all(
                          color: AppColors.info.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(AppSpacing.sm),
                            decoration: BoxDecoration(
                              color: AppColors.info.withValues(alpha: 0.12),
                              borderRadius: AppRadius.smAll,
                            ),
                            child: const Icon(Icons.directions_walk_rounded,
                                color: AppColors.info, size: 20),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'On their way',
                                  style: TextStyle(
                                    color: AppColors.info,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'The other party is heading to you',
                                  style: TextStyle(
                                    color: AppColors.info.withValues(alpha: 0.8),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }
}
