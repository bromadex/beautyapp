import 'dart:math';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../supabase_client.dart';
import '../theme.dart';

class LocationPickerSheet extends StatefulWidget {
  final String currentCity;
  final void Function(String cityName, double? lat, double? lng) onCitySelected;

  const LocationPickerSheet({
    super.key,
    required this.currentCity,
    required this.onCitySelected,
  });

  @override
  State<LocationPickerSheet> createState() => _LocationPickerSheetState();
}

class _LocationPickerSheetState extends State<LocationPickerSheet> {
  List<Map<String, dynamic>> _cities = [];
  List<Map<String, dynamic>> _filtered = [];
  final _searchCtrl = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCities();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCities() async {
    try {
      final data = await supabase
          .from('cities')
          .select()
          .eq('is_active', true)
          .order('name');
      if (mounted) {
        setState(() {
          _cities = List<Map<String, dynamic>>.from(data);
          _filtered = _cities;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _filter(String query) {
    final q = query.toLowerCase().trim();
    setState(() {
      _filtered = q.isEmpty
          ? _cities
          : _cities
              .where((c) =>
                  (c['name'] as String).toLowerCase().contains(q))
              .toList();
    });
  }

  Future<void> _selectCity(Map<String, dynamic> city) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_city', city['name']);
    widget.onCitySelected(
      city['name'] as String,
      (city['lat'] as num?)?.toDouble(),
      (city['lng'] as num?)?.toDouble(),
    );
    if (mounted) Navigator.pop(context);
  }

  void _selectAllZimbabwe() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_city', 'All Zimbabwe');
    widget.onCitySelected('All Zimbabwe', null, null);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      expand: false,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select Location',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Search city...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      border: OutlineInputBorder(borderRadius: AppRadius.mdAll),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onChanged: _filter,
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg),
                      children: [
                        _CityTile(
                          icon: Icons.public_rounded,
                          name: 'All Zimbabwe',
                          subtitle: 'Search nationwide',
                          isSelected: widget.currentCity == 'All Zimbabwe',
                          onTap: _selectAllZimbabwe,
                        ),
                        const Divider(height: 1),
                        ..._filtered.map((city) => _CityTile(
                              icon: Icons.location_city_rounded,
                              name: city['name'] as String,
                              subtitle: city['country'] as String? ?? 'Zimbabwe',
                              isSelected: widget.currentCity == city['name'],
                              onTap: () => _selectCity(city),
                            )),
                        if (_filtered.isEmpty && !_loading)
                          Padding(
                            padding: const EdgeInsets.all(AppSpacing.xxl),
                            child: Center(
                              child: Text(
                                'No cities found',
                                style: TextStyle(color: AppColors.textTertiary),
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CityTile extends StatelessWidget {
  final IconData icon;
  final String name;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  const _CityTile({
    required this.icon,
    required this.name,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.1)
              : Colors.grey.shade100,
          borderRadius: AppRadius.smAll,
        ),
        child: Icon(
          icon,
          color: isSelected ? AppColors.primary : AppColors.textTertiary,
          size: 20,
        ),
      ),
      title: Text(
        name,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          color: isSelected ? AppColors.primary : AppColors.textPrimary,
        ),
      ),
      subtitle: Text(subtitle,
          style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
      trailing: isSelected
          ? const Icon(Icons.check_circle_rounded,
              color: AppColors.primary, size: 22)
          : null,
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    );
  }
}

class LocationHelper {
  static Future<String> getSavedCity() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('selected_city') ?? 'All Zimbabwe';
  }

  static double haversineDistance(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  static double _toRad(double deg) => deg * pi / 180;
}
