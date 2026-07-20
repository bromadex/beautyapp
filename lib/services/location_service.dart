import 'dart:async';
import 'package:geolocator/geolocator.dart';
import '../supabase_client.dart';

class LocationService {
  StreamSubscription<Position>? _positionSub;
  bool _isSharing = false;

  bool get isSharing => _isSharing;

  /// Start broadcasting this user's location to Supabase every 4 seconds.
  Future<void> startSharing(String bookingId) async {
    if (_isSharing) return;

    final permission = await _ensurePermission();
    if (!permission) return;

    _isSharing = true;
    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // update every 10 metres moved
    );

    _positionSub = Geolocator.getPositionStream(locationSettings: settings)
        .listen((pos) async {
      try {
        await supabase.from('booking_locations').upsert({
          'booking_id': bookingId,
          'user_id': supabase.auth.currentUser!.id,
          'latitude': pos.latitude,
          'longitude': pos.longitude,
          'heading': pos.heading,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'booking_id,user_id');
      } catch (_) {}
    });
  }

  /// Stop broadcasting.
  Future<void> stopSharing() async {
    await _positionSub?.cancel();
    _positionSub = null;
    _isSharing = false;
  }

  /// Get current position once.
  Future<Position?> getCurrentPosition() async {
    final ok = await _ensurePermission();
    if (!ok) return null;
    return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
  }

  Future<bool> _ensurePermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    return perm == LocationPermission.whileInUse ||
        perm == LocationPermission.always;
  }
}nameu  