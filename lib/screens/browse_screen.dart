import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../supabase_client.dart';
import '../theme.dart';
import '../utils/booking_helpers.dart';
import '../utils/feel.dart';
import '../utils/pro_photos.dart';
import '../widgets/location_picker_sheet.dart';
import '../widgets/ui.dart';

class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  List<Map<String, dynamic>> _providers = [];
  List<Map<String, dynamic>> _categories = [];
  bool _loading = true;
  Map<String, String> _covers = {};
  Set<String> _favourites = {};

  // Location
  String _selectedCity = 'All Zimbabwe';
  double? _cityLat;
  double? _cityLng;
  int _radiusKm = 100;
  static const List<int> _radiusOptions = [5, 10, 25, 50, 100];

  // Search & filters
  final _searchCtrl = TextEditingController();
  final Set<String> _selectedCategoryIds = {};
  String? _group;
  String _where = 'any'; // any | home | studio
  String _gender = 'any'; // any | woman | man
  double _minRating = 0;
  RangeValues _priceRange = const RangeValues(0, 500);
  String _sortBy = 'rating'; // rating | distance | price_low | newest

  @override
  void initState() {
    super.initState();
    _loadSavedCity();
    _loadCategories();
    _loadProviders();
    _consumeIntent();
    BrowseIntent.category.addListener(_consumeIntent);
    BrowseIntent.group.addListener(_consumeIntent);
  }

  void _consumeIntent() {
    final g = BrowseIntent.group.value;
    if (g != null) {
      BrowseIntent.group.value = null;
      setState(() {
        _group = g;
        _selectedCategoryIds.clear();
      });
    }
    final id = BrowseIntent.category.value;
    if (id == null) return;
    BrowseIntent.category.value = null;
    setState(() {
      _selectedCategoryIds
        ..clear()
        ..add(id);
    });
  }

  @override
  void dispose() {
    BrowseIntent.category.removeListener(_consumeIntent);
    BrowseIntent.group.removeListener(_consumeIntent);
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSavedCity() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('selected_city');
    if (saved != null && mounted) {
      setState(() => _selectedCity = saved);

      // Load city coordinates
      if (saved != 'All Zimbabwe') {
        try {
          final city = await supabase
              .from('cities')
              .select('lat, lng')
              .eq('name', saved)
              .maybeSingle();
          if (city != null && mounted) {
            setState(() {
              _cityLat = (city['lat'] as num?)?.toDouble();
              _cityLng = (city['lng'] as num?)?.toDouble();
            });
          }
        } catch (_) {}
      }
    }
    // Default: try to match user's profile location to a city
    if (saved == null) {
      try {
        final uid = supabase.auth.currentUser?.id;
        if (uid != null) {
          final profile = await supabase
              .from('profiles')
              .select('location')
              .eq('id', uid)
              .maybeSingle();
          final loc = (profile?['location'] ?? '').toString().toLowerCase();
          if (loc.isNotEmpty) {
            final cities = await supabase
                .from('cities')
                .select()
                .eq('is_active', true);
            for (final c in cities) {
              if (loc.contains((c['name'] as String).toLowerCase())) {
                if (mounted) {
                  setState(() {
                    _selectedCity = c['name'];
                    _cityLat = (c['lat'] as num?)?.toDouble();
                    _cityLng = (c['lng'] as num?)?.toDouble();
                  });
                  final prefs2 = await SharedPreferences.getInstance();
                  await prefs2.setString('selected_city', c['name']);
                }
                break;
              }
            }
          }
        }
      } catch (_) {}
    }
  }

  Future<void> _loadCategories() async {
    try {
      final data = await supabase
          .from('service_categories')
          .select('*, service_groups(name)')
          .order('sort_order', ascending: true);
      if (mounted) {
        setState(() {
          _categories = List<Map<String, dynamic>>.from(data);
        });
      }
    } catch (_) {}
  }

  Future<void> _loadProviders() async {
    setState(() => _loading = true);

    try {
      final data = await supabase
          .from('provider_profiles')
          .select('*, cities(name), profiles(full_name, location, avatar_url, is_verified, is_business_verified, whatsapp_number, '
              'services(id, service_name, price, category_id, is_active, location_mode), '
              'subscriptions(status, end_date))')
          .or('is_hidden.eq.false,is_hidden.is.null');

      // Only pros who have said where they work can be found.
      final providers = List<Map<String, dynamic>>.from(data)
          .where((p) => p['city_id'] != null && (p['area'] ?? '').toString().trim().isNotEmpty)
          .toList();
      for (final p in providers) {
        final prof = p['profiles'] as Map<String, dynamic>? ?? {};
        p['services'] = prof['services'] ?? [];
        final sub = prof['subscriptions'];
        p['subscriptions'] = sub == null ? [] : (sub is List ? sub : [sub]);
      }

      final uid = supabase.auth.currentUser?.id;
      final extras = await Future.wait<dynamic>([
        loadCoverPhotos(),
        if (uid != null) supabase.from('favorites').select('provider_id').eq('client_id', uid),
      ]);
      if (mounted) {
        setState(() {
          _providers = providers;
          _covers = extras[0] as Map<String, String>;
          if (extras.length > 1) _favourites = {for (final r in extras[1] as List) r['provider_id'] as String};
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading providers: $e')),
        );
      }
    }
  }

  Future<void> _toggleFavourite(String providerId) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    final saved = _favourites.contains(providerId);
    Haptics.firm();
    setState(() => saved ? _favourites.remove(providerId) : _favourites.add(providerId));
    try {
      if (saved) {
        await supabase.from('favorites').delete().eq('client_id', uid).eq('provider_id', providerId);
      } else {
        await supabase.from('favorites').insert({'client_id': uid, 'provider_id': providerId});
      }
    } catch (_) {
      if (mounted) setState(() => saved ? _favourites.add(providerId) : _favourites.remove(providerId));
    }
  }

  double? _distanceToProvider(Map<String, dynamic> p) {
    if (_cityLat == null || _cityLng == null) return null;
    final pLat = (p['latitude'] as num?)?.toDouble();
    final pLng = (p['longitude'] as num?)?.toDouble();
    if (pLat == null || pLng == null) {
      // Fallback: match by location string
      return null;
    }
    return _haversine(_cityLat!, _cityLng!, pLat, pLng);
  }

  static double _haversine(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  static double _toRad(double deg) => deg * pi / 180;

  bool _matchesLocation(Map<String, dynamic> p) {
    if (_selectedCity == 'All Zimbabwe') return true;
    final city = (p['cities'] as Map?)?['name']?.toString().toLowerCase();
    if (city != null && city == _selectedCity.toLowerCase()) return true;
    final loc =
        (p['profiles']?['location'] ?? '').toString().toLowerCase();
    final cityLower = _selectedCity.toLowerCase();
    if (loc.contains(cityLower)) return true;
    // Check distance if coords available
    final dist = _distanceToProvider(p);
    if (dist != null && dist <= _radiusKm) return true;
    return false;
  }

  List<Map<String, dynamic>> get _filteredProviders {
    final query = _searchCtrl.text.trim().toLowerCase();

    final filtered = _providers.where((p) {
      final name =
          (p['profiles']?['full_name'] ?? '').toString().toLowerCase();
      final location =
          (p['profiles']?['location'] ?? '').toString().toLowerCase();
      final rating = (p['average_rating'] as num?)?.toDouble() ?? 0.0;
      final services = p['services'] as List? ?? [];

      // Location filter
      if (!_matchesLocation(p)) return false;

      // Search by name, location, or service name
      if (query.isNotEmpty) {
        final matchesName = name.contains(query);
        final matchesLocation = location.contains(query);
        final matchesService = services.any((s) =>
            (s['service_name'] ?? '').toString().toLowerCase().contains(query));
        if (!matchesName && !matchesLocation && !matchesService) return false;
      }

      // Minimum rating filter
      if (_minRating > 0 && rating < _minRating) return false;

      // Service group
      if (_group != null) {
        final groupOf = {for (final c in _categories) c['id']: c['service_groups']?['name']};
        if (!services.any((s) => s['is_active'] == true && groupOf[s['category_id']] == _group)) {
          return false;
        }
      }

      // The pro's gender (e.g. for massage)
      if (_gender != 'any' && p['gender'] != _gender) return false;

      // Where the service happens
      if (_where != 'any') {
        final want = _where == 'home' ? 'client' : 'studio';
        if (!services.any((s) => s['is_active'] == true && (s['location_mode'] == want || s['location_mode'] == 'either'))) {
          return false;
        }
      }

      // Category filter (multi-select)
      if (_selectedCategoryIds.isNotEmpty) {
        final hasCategory = services.any((s) =>
            _selectedCategoryIds.contains(s['category_id']) &&
            s['is_active'] == true);
        if (!hasCategory) return false;
      }

      // Price range filter
      if (_priceRange.start > 0 || _priceRange.end < 500) {
        final activeServices =
            services.where((s) => s['is_active'] == true).toList();
        if (activeServices.isEmpty) return false;
        final prices = activeServices
            .map((s) => (s['price'] as num?)?.toDouble() ?? 0)
            .toList();
        final minPrice = prices.reduce((a, b) => a < b ? a : b);
        final maxPrice = prices.reduce((a, b) => a > b ? a : b);
        if (minPrice > _priceRange.end || maxPrice < _priceRange.start) {
          return false;
        }
      }

      return true;
    }).toList();

    // Sort
    filtered.sort((a, b) {
      // Featured always first
      final featA = _isFeatured(a) ? 1 : 0;
      final featB = _isFeatured(b) ? 1 : 0;
      if (featA != featB) return featB.compareTo(featA);

      switch (_sortBy) {
        case 'distance':
          final dA = _distanceToProvider(a) ?? 9999;
          final dB = _distanceToProvider(b) ?? 9999;
          return dA.compareTo(dB);
        case 'price_low':
          final pA = _minServicePrice(a);
          final pB = _minServicePrice(b);
          return pA.compareTo(pB);
        case 'newest':
          final cA = a['created_at'] ?? '';
          final cB = b['created_at'] ?? '';
          return cB.compareTo(cA);
        default: // rating
          final rA = (a['average_rating'] as num?)?.toDouble() ?? 0.0;
          final rB = (b['average_rating'] as num?)?.toDouble() ?? 0.0;
          return rB.compareTo(rA);
      }
    });

    return filtered;
  }

  double _minServicePrice(Map<String, dynamic> p) {
    final services = (p['services'] as List? ?? [])
        .where((s) => s['is_active'] == true)
        .toList();
    if (services.isEmpty) return 999;
    return services
        .map((s) => (s['price'] as num?)?.toDouble() ?? 999)
        .reduce((a, b) => a < b ? a : b);
  }

  static bool _isFeatured(Map<String, dynamic> provider) {
    final until = DateTime.tryParse((provider['featured_until'] ?? '').toString());
    return until != null && until.isAfter(DateTime.now());
  }

  int get _activeFilterCount {
    int count = 0;
    if (_minRating > 0) count++;
    if (_where != 'any') count++;
    if (_gender != 'any') count++;
    if (_selectedCategoryIds.isNotEmpty) count++;
    if (_priceRange.start > 0 || _priceRange.end < 500) count++;
    if (_selectedCity != 'All Zimbabwe') count++;
    return count;
  }

  void _openLocationPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true, // above the bottom tab bar
      showDragHandle: false, // the sheet draws its own
      backgroundColor: Colors.transparent,
      builder: (_) => LocationPickerSheet(
        currentCity: _selectedCity,
        onCitySelected: (city, lat, lng) {
          setState(() {
            _selectedCity = city;
            _cityLat = lat;
            _cityLng = lng;
          });
        },
      ),
    );
  }

  void _showFilterSheet() {
    double tempMinRating = _minRating;
    RangeValues tempPriceRange = _priceRange;
    String tempSort = _sortBy;
    int tempRadius = _radiusKm;
    String tempWhere = _where;
    String tempGender = _gender;

    showModalBottomSheet(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      builder: (_) => SheetScroll(child: StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.xxl,
            right: AppSpacing.xxl,
            top: AppSpacing.sm,
            bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.xxl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Filters',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      setSheetState(() {
                        tempMinRating = 0;
                        tempPriceRange = const RangeValues(0, 500);
                        tempSort = 'rating';
                        tempRadius = 100;
                        tempWhere = 'any';
                        tempGender = 'any';
                      });
                    },
                    child: const Text('Reset'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // Where
              Text('Where', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  _SortChip('Anywhere', 'any', tempWhere, (v) => setSheetState(() => tempWhere = v)),
                  _SortChip('Comes to me', 'home', tempWhere, (v) => setSheetState(() => tempWhere = v)),
                  _SortChip('I go to them', 'studio', tempWhere, (v) => setSheetState(() => tempWhere = v)),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),

              // Pro's gender, e.g. for massage
              Text('Beauty pro', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 2),
              Text('Handy for massage and other close-contact services.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  _SortChip('Anyone', 'any', tempGender, (v) => setSheetState(() => tempGender = v)),
                  _SortChip('A woman', 'woman', tempGender, (v) => setSheetState(() => tempGender = v)),
                  _SortChip('A man', 'man', tempGender, (v) => setSheetState(() => tempGender = v)),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),

              // Sort by
              Text('Sort by', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  _SortChip('Best Rated', 'rating', tempSort,
                      (v) => setSheetState(() => tempSort = v)),
                  _SortChip('Closest', 'distance', tempSort,
                      (v) => setSheetState(() => tempSort = v)),
                  _SortChip('Price: Low', 'price_low', tempSort,
                      (v) => setSheetState(() => tempSort = v)),
                  _SortChip('Newest', 'newest', tempSort,
                      (v) => setSheetState(() => tempSort = v)),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),

              // Radius
              if (_selectedCity != 'All Zimbabwe') ...[
                Text(
                  'Radius: ${tempRadius}km from $_selectedCity',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: AppSpacing.sm,
                  children: _radiusOptions.map((r) {
                    final selected = tempRadius == r;
                    return ChoiceChip(
                      label: Text('${r}km'),
                      selected: selected,
                      onSelected: (_) =>
                          setSheetState(() => tempRadius = r),
                      selectedColor:
                          AppColors.primary.withValues(alpha: 0.15),
                      labelStyle: TextStyle(
                        color: selected
                            ? AppColors.primary
                            : AppColors.textSecondary,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                      checkmarkColor: AppColors.primary,
                    );
                  }).toList(),
                ),
                const SizedBox(height: AppSpacing.xl),
              ],

              // Rating
              Text(
                'Minimum Rating: ${tempMinRating == 0 ? 'Any' : '${tempMinRating.toStringAsFixed(1)}+'}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  for (int i = 1; i <= 5; i++)
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setSheetState(() =>
                            tempMinRating =
                                tempMinRating == i.toDouble() ? 0 : i.toDouble()),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: tempMinRating >= i
                                ? AppColors.primary.withValues(alpha: 0.1)
                                : AppColors.surfaceMuted,
                            borderRadius: AppRadius.smAll,
                            border: Border.all(
                              color: tempMinRating >= i
                                  ? AppColors.primary.withValues(alpha: 0.3)
                                  : AppColors.borderStrong,
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(TablerIcons.star_filled,
                                  size: 20,
                                  color: tempMinRating >= i
                                      ? AppColors.warning
                                      : AppColors.textTertiary),
                              Text('$i+',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: tempMinRating >= i
                                          ? AppColors.primary
                                          : AppColors.textTertiary)),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),

              // Price range
              Text(
                'Price: \$${tempPriceRange.start.toStringAsFixed(0)} - \$${tempPriceRange.end.toStringAsFixed(0)}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: AppColors.primary,
                  thumbColor: AppColors.primary,
                  inactiveTrackColor:
                      AppColors.primary.withValues(alpha: 0.15),
                ),
                child: RangeSlider(
                  values: tempPriceRange,
                  min: 0,
                  max: 500,
                  divisions: 50,
                  labels: RangeLabels(
                    '\$${tempPriceRange.start.toStringAsFixed(0)}',
                    '\$${tempPriceRange.end.toStringAsFixed(0)}',
                  ),
                  onChanged: (v) =>
                      setSheetState(() => tempPriceRange = v),
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    setState(() {
                      _minRating = tempMinRating;
                      _priceRange = tempPriceRange;
                      _sortBy = tempSort;
                      _where = tempWhere;
                      _gender = tempGender;
                      _radiusKm = tempRadius;
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Apply Filters'),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredProviders;

    Widget chip(String label, bool selected, VoidCallback onTap, {String? photo}) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(label),
            selected: selected,
            showCheckmark: false,
            avatar: photo == null
                ? null
                : ClipOval(child: Image.asset(photo, width: 26, height: 26, fit: BoxFit.cover, cacheWidth: 78)),
            labelPadding: EdgeInsets.only(left: photo == null ? 8 : 6, right: 8),
            onSelected: (_) {
              Haptics.light();
              onTap();
            },
          ),
        );

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kPageMaxWidth),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(children: [
                    Expanded(child: Text('Browse', style: Theme.of(context).textTheme.displaySmall)),
                    InkWell(
                      onTap: _openLocationPicker,
                      borderRadius: AppRadius.pill,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: AppRadius.pill,
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(TablerIcons.map_pin_filled, size: 16, color: AppColors.primary),
                          const SizedBox(width: 4),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 110),
                            child: Text(
                              _selectedCity,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary),
                            ),
                          ),
                          Icon(TablerIcons.chevron_down, size: 18, color: AppColors.primary),
                        ]),
                      ),
                    ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (_) => setState(() {}),
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search beauty pros or services',
                      prefixIcon: Icon(TablerIcons.search, color: AppColors.primary),
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (_searchCtrl.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(TablerIcons.x, size: 20),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() {});
                            },
                          ),
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Badge(
                            isLabelVisible: _activeFilterCount > 0,
                            label: Text('$_activeFilterCount'),
                            backgroundColor: AppColors.primary,
                            child: IconButton(
                              tooltip: 'Filters',
                              onPressed: _showFilterSheet,
                              style: IconButton.styleFrom(backgroundColor: AppColors.primarySoft),
                              icon: Icon(TablerIcons.adjustments_horizontal, size: 20, color: AppColors.primary),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),

                SizedBox(
                  height: 56,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 12, 12, 4),
                    children: [
                      chip('All', _group == null && _selectedCategoryIds.isEmpty, () => setState(() {
                            _group = null;
                            _selectedCategoryIds.clear();
                          })),
                      for (final g in ServiceGroup.all)
                        chip(g.name, _group == g.name, () => setState(() {
                              _group = _group == g.name ? null : g.name;
                              _selectedCategoryIds.clear();
                            }), photo: g.photo),
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
                  child: Row(children: [
                    Text(
                      '${filtered.length} pro${filtered.length == 1 ? '' : 's'}'
                      '${_selectedCity != 'All Zimbabwe' ? ' in $_selectedCity' : ''}',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _showFilterSheet,
                      icon: const Icon(TablerIcons.arrows_sort, size: 18),
                      label: Text(_sortLabel),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ]),
                ),

                Expanded(
                  child: _loading
                      ? const LoadingPlaceholder()
                      : RefreshIndicator.adaptive(
                          onRefresh: _loadProviders,
                          child: filtered.isEmpty
                              ? _buildEmptyState()
                              : ListView(
                                  padding: EdgeInsets.fromLTRB(20, 4, 20, 12 + tabBarSpace(context)),
                                  children: [
                                    // A grid of pros on wide screens, a list on phones.
                                    AdaptiveGrid(minTileWidth: 340, children: [
                                      for (final p in filtered)
                                        _ProviderCard(
                                          provider: p,
                                          distance: _distanceToProvider(p),
                                          isFeatured: _isFeatured(p),
                                          categories: _categories,
                                          photo: coverFor(_covers, p['provider_id'] as String,
                                              (p['profiles'] as Map?)?['avatar_url'] as String?),
                                          saved: _favourites.contains(p['provider_id']),
                                          onSave: () => _toggleFavourite(p['provider_id'] as String),
                                        ),
                                    ]),
                                  ],
                                ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _sortLabel {
    switch (_sortBy) {
      case 'distance':
        return 'Closest';
      case 'price_low':
        return 'Price';
      case 'newest':
        return 'Newest';
      default:
        return 'Top Rated';
    }
  }

  Widget _buildEmptyState() {
    final local = _selectedCity != 'All Zimbabwe';
    return ListView(children: [
      const SizedBox(height: 40),
      EmptyState(
        icon: TablerIcons.search_off,
        title: 'No beauty pros found',
        message: local
            ? 'Nobody matches in $_selectedCity yet. Try searching all of Zimbabwe.'
            : 'Try a different search or clear some filters.',
        actionLabel: local ? 'Search all Zimbabwe' : null,
        onAction: local
            ? () => setState(() {
                  _selectedCity = 'All Zimbabwe';
                  _cityLat = null;
                  _cityLng = null;
                })
            : null,
      ),
      const SizedBox(height: 8),
      Center(
        child: TextButton.icon(
          onPressed: _requestArea,
          icon: const Icon(TablerIcons.map_pin_plus, size: 18),
          label: const Text('Not in your area yet? Request it'),
        ),
      ),
    ]);
  }

  Future<void> _requestArea() async {
    final cityCtrl = TextEditingController(text: _selectedCity == 'All Zimbabwe' ? '' : _selectedCity);
    String? category = _selectedCategoryIds.length == 1
        ? _categories.where((c) => c['id'] == _selectedCategoryIds.first).map((c) => c['name'] as String).firstOrNull
        : null;
    final sent = await showModalBottomSheet<bool>(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        bool sending = false;
        return SheetScroll(child: StatefulBuilder(
          builder: (ctx, setSheet) => Padding(
            padding: EdgeInsets.fromLTRB(
                20, 0, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom + MediaQuery.of(ctx).padding.bottom),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Bring BeauTap to your area', style: Theme.of(ctx).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text('Tell us where you are. We invite beauty pros to the areas people ask for most.',
                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 16),
              TextField(
                controller: cityCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Town or suburb', hintText: 'e.g. Chitungwiza, Kwekwe'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: category,
                decoration: const InputDecoration(labelText: 'Service you want (optional)'),
                items: [
                  for (final c in _categories)
                    DropdownMenuItem(value: c['name'] as String, child: Text(c['name'] as String)),
                ],
                onChanged: (v) => category = v,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: sending
                    ? null
                    : () async {
                        if (cityCtrl.text.trim().length < 2) return;
                        setSheet(() => sending = true);
                        try {
                          await supabase.rpc('request_area',
                              params: {'p_city': cityCtrl.text.trim(), 'p_category': category});
                          if (ctx.mounted) Navigator.pop(ctx, true);
                        } catch (_) {
                          setSheet(() => sending = false);
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(content: Text('Could not send. Check your connection.')));
                          }
                        }
                      },
                child: Text(sending ? 'Sending…' : 'Request my area'),
              ),
            ]),
          ),
        ));
      },
    );
    cityCtrl.dispose();
    if (sent == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thanks! We\'ll let beauty pros know people are waiting there.')));
    }
  }
}

class _SortChip extends StatelessWidget {
  final String label;
  final String value;
  final String current;
  final ValueChanged<String> onSelected;

  const _SortChip(this.label, this.value, this.current, this.onSelected);

  @override
  Widget build(BuildContext context) {
    final selected = current == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(value),
      selectedColor: AppColors.primary.withValues(alpha: 0.15),
      labelStyle: TextStyle(
        fontSize: 12,
        color: selected ? AppColors.primary : AppColors.textSecondary,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
      ),
      checkmarkColor: AppColors.primary,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _ProviderCard extends StatelessWidget {
  final Map<String, dynamic> provider;
  final double? distance;
  final bool isFeatured;
  final List<Map<String, dynamic>> categories;
  final String? photo;
  final bool saved;
  final VoidCallback onSave;

  const _ProviderCard({
    required this.provider,
    this.distance,
    required this.isFeatured,
    required this.categories,
    required this.photo,
    required this.saved,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    final p = provider;
    final prof = p['profiles'] as Map? ?? {};
    final name = (prof['full_name'] ?? 'Beauty pro').toString();
    final area = (p['area'] ?? prof['location'] ?? '').toString();
    final available = p['availability_status'] == 'available';
    final rating = (p['average_rating'] as num?)?.toDouble() ?? 0.0;
    final totalReviews = (p['total_reviews'] as num?)?.toInt() ?? 0;
    final verified = prof['is_verified'] == true || prof['is_business_verified'] == true;
    final services = (p['services'] as List? ?? []).where((s) => s['is_active'] == true).toList();
    // WhatsApp only for pros who chose it as how clients should reach them.
    final whatsapp = (prof['whatsapp_number'] ?? '').toString().trim();
    final showWhatsApp = whatsapp.isNotEmpty && ['whatsapp', 'both'].contains(p['preferred_contact']);

    String priceText = '';
    if (services.isNotEmpty) {
      final prices = services.map((s) => (s['price'] as num?)?.toDouble() ?? 0).toList();
      priceText = '\$${prices.reduce((a, b) => a < b ? a : b).toStringAsFixed(0)}';
    }

    final catNames = <String>{};
    for (final s in services) {
      final c = categories.firstWhere((c) => c['id'] == s['category_id'], orElse: () => const {});
      if (c['name'] != null) catNames.add(c['name']);
    }

    // Measured from the chosen city's centre, not the client's phone, so
    // very small distances (a pro pinned at the centre) aren't shown.
    final distanceText = (distance != null && distance! >= 1)
        ? '${distance!.toStringAsFixed(distance! < 10 ? 1 : 0)} km'
        : null;
    final secondary = TextStyle(fontSize: 12.5, color: AppColors.textSecondary);
    final open = () => context.push('/provider/${p['provider_id']}');

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        shape: isFeatured
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24), side: BorderSide(color: AppColors.gold.withValues(alpha: 0.7)))
            : null,
        child: InkWell(
          onTap: open,
          child: Padding(
            padding: const EdgeInsets.all(10),
            // Fixed height: the photo sets it, the text column fits beside it.
            child: SizedBox(
              height: 118,
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SizedBox(
                  width: 100,
                  child: Stack(fit: StackFit.expand, children: [
                    ProPhoto(name: name, url: photo, radius: 18, showNoPhotoNote: true),
                    Positioned(top: 6, right: 6, child: HeartButton(saved: saved, onTap: onSave, size: 28)),
                  ]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      if (available) ...[
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(color: AppColors.available, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      ),
                      if (verified) ...[
                        const SizedBox(width: 4),
                        Icon(TablerIcons.rosette_discount_check_filled, size: 16, color: AppColors.info),
                      ],
                    ]),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (catNames.isNotEmpty) catNames.take(2).join(' & '),
                        if (area.isNotEmpty) area,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: secondary,
                    ),
                    const SizedBox(height: 6),
                    Row(children: [
                      if (totalReviews > 0) ...[
                        Text('★ ${rating.toStringAsFixed(1)}',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                        Text(' ($totalReviews)', style: secondary),
                      ] else
                        Text('New on BeauTap', style: secondary.copyWith(fontWeight: FontWeight.w600)),
                      if (distanceText != null) ...[const SizedBox(width: 10), Text(distanceText, style: secondary)],
                      if (isFeatured) ...[const SizedBox(width: 8), const PhotoBadge(text: 'Featured', gold: true)],
                    ]),
                    const Spacer(),
                    Row(children: [
                      if (priceText.isNotEmpty)
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                            Text('from', style: secondary.copyWith(fontSize: 11.5)),
                            Text(priceText,
                                style: TextStyle(
                                    fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: AppColors.textPrimary)),
                          ]),
                        )
                      else
                        const Spacer(),
                      if (showWhatsApp) ...[
                        Material(
                          color: AppColors.surfaceMuted,
                          shape: const CircleBorder(),
                          child: IconButton(
                            tooltip: 'WhatsApp $name',
                            onPressed: () => shareOnWhatsApp('Hi $name, I found you on BeauTap.', phone: whatsapp),
                            icon: const Icon(TablerIcons.brand_whatsapp, color: Color(0xFF25A55F), size: 20),
                            constraints: const BoxConstraints.tightFor(width: 38, height: 38),
                            padding: EdgeInsets.zero,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      FilledButton(
                        onPressed: open,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 38),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        child: const Text('Book'),
                      ),
                    ]),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
