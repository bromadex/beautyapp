import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:geolocator/geolocator.dart';
import '../widgets/permission_explainer.dart';
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
          'updated_at': DateTime.now().toUtc().toIso8601String(),
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

  /// Get current position once. With a [context], explains why before the
  /// phone asks, and helps if location is off or was blocked before.
  Future<Position?> getCurrentPosition({BuildContext? context, String? reason}) async {
    final ok = context == null ? await _ensurePermission() : await ensurePermissionWithExplainer(context, reason: reason);
    if (!ok) return null;
    return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
  }

  Future<bool> ensurePermissionWithExplainer(BuildContext context, {String? reason}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (!context.mounted) return false;
        final go = await PermissionExplainer.show(
          context,
          icon: TablerIcons.map_pin_off,
          title: 'Location is switched off',
          body: 'Turn on location on your phone so BeauTap can find where you are.',
          allowLabel: 'Open location settings',
        );
        if (go) await Geolocator.openLocationSettings();
        return false;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.deniedForever) {
        if (!context.mounted) return false;
        final go = await PermissionExplainer.show(
          context,
          icon: TablerIcons.map_pin_off,
          title: 'Location is blocked for BeauTap',
          body: 'You turned location off for BeauTap before. To use it, allow Location in the app settings.',
          allowLabel: 'Open settings',
        );
        if (go) await Geolocator.openAppSettings();
        return false;
      }
      if (perm == LocationPermission.denied) {
        if (!context.mounted) return false;
        final go = await PermissionExplainer.show(
          context,
          icon: TablerIcons.map_pin,
          title: 'Use your location?',
          body: reason ?? 'BeauTap uses your location to fill in where you are.',
          points: const [
            'Only when you tap this button, never in the background',
            'Other clients never see where you are',
            'You can type an address instead',
          ],
          allowLabel: 'Allow location',
        );
        if (!go) return false;
        perm = await Geolocator.requestPermission();
      }
      return perm == LocationPermission.whileInUse || perm == LocationPermission.always;
    } catch (_) {
      return false;
    }
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
}