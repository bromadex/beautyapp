import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../supabase_client.dart';
import '../services/location_service.dart';
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
    final uid = supabase.auth.currentUser!.id;

    final booking = await supabase
        .from('bookings')
        .select('*, services(service_name, duration_minutes)')
        .eq('id', widget.bookingId)
        .single();

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
        const SnackBar(content: Text('✅ Location sharing started')),
      );
    }
  }

  Future<void> _markArrived() async {
    await supabase.from('bookings').update({
      'arrived_at': DateTime.now().toIso8601String(),
    }).eq('id', widget.bookingId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('📍 Marked as Arrived')),
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final bool iAmTravelling = (_travelMode == 'provider_to_client' && _isProvider) ||
        (_travelMode == 'client_to_provider' && !_isProvider);
    final bool otherIsTravelling = (_travelMode == 'provider_to_client' && !_isProvider) ||
        (_travelMode == 'client_to_provider' && _isProvider);
    final bool isFixed = _travelMode == 'fixed_location';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Live Tracking'),
        actions: [
          if (_travelMode == null && _bookingStatus == 'confirmed')
            TextButton.icon(
              onPressed: _promptTravelMode,
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Set Mode'),
            ),
        ],
      ),
      body: Column(
        children: [
          // Travel mode banner
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.primaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                Icon(
                  isFixed
                      ? Icons.store_rounded
                      : iAmTravelling
                          ? Icons.directions_walk_rounded
                          : Icons.my_location_rounded,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_travelModeLabel,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                if (_travelMode == null)
                  GestureDetector(
                    onTap: _promptTravelMode,
                    child: const Text('Set →',
                        style: TextStyle(
                            decoration: TextDecoration.underline,
                            fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
          ),

          // Location info card (instead of a map for web simplicity)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.location_on_rounded,
                        size: 64, color: Colors.pink),
                    const SizedBox(height: 16),
                    Text(
                      _otherLocation != null
                          ? '${_isProvider ? "Client" : "Stylist"} is at:\n'
                              '${_otherLocation!['latitude'].toStringAsFixed(5)}, '
                              '${_otherLocation!['longitude'].toStringAsFixed(5)}'
                          : 'Waiting for location data...',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    if (_otherLocation != null)
                      ElevatedButton.icon(
                        onPressed: _openInMaps,
                        icon: const Icon(Icons.map_outlined),
                        label: const Text('Navigate in Google Maps'),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Action buttons
          if (_bookingStatus == 'confirmed') ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (iAmTravelling) ...[
                    ElevatedButton.icon(
                      onPressed: _markEnRoute,
                      icon: const Icon(Icons.navigation_rounded),
                      label: const Text('I\'m On My Way'),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _markArrived,
                      icon: const Icon(Icons.place_rounded),
                      label: const Text('I\'ve Arrived'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white),
                    ),
                  ] else if (otherIsTravelling) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.directions_walk_rounded,
                              color: Colors.blue),
                          SizedBox(width: 10),
                          Text('The other party is on their way'),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}