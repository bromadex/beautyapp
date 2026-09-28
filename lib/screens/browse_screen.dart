import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../supabase_client.dart';
import '../theme.dart';
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

  // Location
  String _selectedCity = 'All Zimbabwe';
  double? _cityLat;
  double? _cityLng;
  int _radiusKm = 100;
  static const List<int> _radiusOptions = [5, 10, 25, 50, 100];

  // Search & filters
  final _searchCtrl = TextEditingController();
  final Set<String> _selectedCategoryIds = {};
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
  }

  void _consumeIntent() {
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
          .select()
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
          .select('*, profiles(full_name, location, avatar_url, is_verified, is_business_verified, '
              'services(id, service_name, price, category_id, is_active), '
              'subscriptions(status, end_date))')
          .or('is_hidden.eq.false,is_hidden.is.null');

      final providers = List<Map<String, dynamic>>.from(data);
      for (final p in providers) {
        final prof = p['profiles'] as Map<String, dynamic>? ?? {};
        p['services'] = prof['services'] ?? [];
        final sub = prof['subscriptions'];
        p['subscriptions'] = sub == null ? [] : (sub is List ? sub : [sub]);
      }

      if (mounted) {
        setState(() {
          _providers = providers;
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
    final subs = provider['subscriptions'] as List? ?? [];
    for (final s in subs) {
      if (s['tier'] == 'featured' && s['status'] == 'active') {
        final end = DateTime.tryParse(s['end_date'] ?? '');
        if (end != null && end.isAfter(DateTime.now())) return true;
      }
    }
    return false;
  }

  int get _activeFilterCount {
    int count = 0;
    if (_minRating > 0) count++;
    if (_selectedCategoryIds.isNotEmpty) count++;
    if (_priceRange.start > 0 || _priceRange.end < 500) count++;
    if (_selectedCity != 'All Zimbabwe') count++;
    return count;
  }

  void _openLocationPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
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
                      });
                    },
                    child: const Text('Reset'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

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
                              Icon(Icons.star_rounded,
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredProviders;

    Widget chip(String label, bool selected, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(label),
            selected: selected,
            showCheckmark: false,
            onSelected: (_) => onTap(),
            labelStyle: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              color: selected ? AppColors.primary : AppColors.textSecondary,
            ),
            side: BorderSide(color: selected ? AppColors.primary.withValues(alpha: 0.35) : AppColors.border),
          ),
        );

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(children: [
                    Expanded(child: Text('Find a stylist', style: Theme.of(context).textTheme.headlineSmall)),
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
                          const Icon(Icons.location_on_rounded, size: 16, color: AppColors.primary),
                          const SizedBox(width: 4),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 110),
                            child: Text(
                              _selectedCity,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primary),
                            ),
                          ),
                          const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppColors.primary),
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
                      hintText: 'Search stylists or services',
                      prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primary),
                      contentPadding: const EdgeInsets.symmetric(vertical: 14),
                      suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (_searchCtrl.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 20),
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
                              icon: const Icon(Icons.tune_rounded, size: 20, color: AppColors.primary),
                            ),
                          ),
                        ),
                      ]),
                    ),
                  ),
                ),

                if (_categories.isNotEmpty)
                  SizedBox(
                    height: 56,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
                      children: [
                        chip('All', _selectedCategoryIds.isEmpty,
                            () => setState(() => _selectedCategoryIds.clear())),
                        ..._categories.map((cat) {
                          final id = cat['id'] as String;
                          final selected = _selectedCategoryIds.contains(id);
                          return chip('${cat['name']}', selected, () {
                            setState(() {
                              selected ? _selectedCategoryIds.remove(id) : _selectedCategoryIds.add(id);
                            });
                          });
                        }),
                      ],
                    ),
                  ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 12, 0),
                  child: Row(children: [
                    Text(
                      '${filtered.length} stylist${filtered.length == 1 ? '' : 's'}'
                      '${_selectedCity != 'All Zimbabwe' ? ' in $_selectedCity' : ''}',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _showFilterSheet,
                      icon: const Icon(Icons.swap_vert_rounded, size: 18),
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
                      ? const Center(child: CircularProgressIndicator())
                      : RefreshIndicator(
                          onRefresh: _loadProviders,
                          child: filtered.isEmpty
                              ? _buildEmptyState()
                              : ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                                  itemCount: filtered.length,
                                  itemBuilder: (_, i) => _ProviderCard(
                                    provider: filtered[i],
                                    distance: _distanceToProvider(filtered[i]),
                                    isFeatured: _isFeatured(filtered[i]),
                                    categories: _categories,
                                  ),
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
        icon: Icons.search_off_rounded,
        title: 'No stylists found',
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
    ]);
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

  const _ProviderCard({
    required this.provider,
    this.distance,
    required this.isFeatured,
    required this.categories,
  });

  @override
  Widget build(BuildContext context) {
    final p = provider;
    final prof = p['profiles'] as Map? ?? {};
    final name = prof['full_name'] ?? 'Stylist';
    final location = (prof['location'] ?? '').toString();
    final status = p['availability_status'] ?? 'offline';
    final rating = (p['average_rating'] as num?)?.toDouble() ?? 0.0;
    final totalReviews = (p['total_reviews'] as num?)?.toInt() ?? 0;
    final verified = prof['is_verified'] == true || prof['is_business_verified'] == true;
    final services = (p['services'] as List? ?? []).where((s) => s['is_active'] == true).toList();

    final statusColor = switch (status) {
      'available' => AppColors.available,
      'busy' => AppColors.busy,
      _ => AppColors.offline,
    };

    String priceText = '';
    if (services.isNotEmpty) {
      final prices = services.map((s) => (s['price'] as num?)?.toDouble() ?? 0).toList();
      final minPrice = prices.reduce((a, b) => a < b ? a : b);
      priceText = '\$${minPrice.toStringAsFixed(0)}';
    }

    final catNames = <String>{};
    for (final s in services) {
      final c = categories.firstWhere((c) => c['id'] == s['category_id'], orElse: () => const {});
      if (c['name'] != null) catNames.add(c['name']);
    }

    String? distanceText;
    if (distance != null) {
      distanceText = distance! < 1
          ? '${(distance! * 1000).toStringAsFixed(0)} m away'
          : '${distance!.toStringAsFixed(1)} km away';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.lgAll,
          side: BorderSide(color: isFeatured ? AppColors.secondary.withValues(alpha: 0.5) : AppColors.border),
        ),
        child: InkWell(
          onTap: () => context.push('/provider/${p['provider_id']}'),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Stack(children: [
                  PersonAvatar(name: name, url: prof['avatar_url'], size: 58),
                  Positioned(
                    right: 1,
                    bottom: 1,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ]),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Flexible(
                        child: Text(name,
                            overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
                      ),
                      if (verified) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.verified_rounded, size: 17, color: AppColors.info),
                      ],
                    ]),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (location.isNotEmpty) location,
                        if (distanceText != null) distanceText,
                      ].join(' · '),
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      RatingPill(rating: rating, reviews: totalReviews),
                      if (isFeatured) ...[
                        const SizedBox(width: 8),
                        const Pill(label: 'Featured', color: AppColors.secondary, icon: Icons.star_rounded),
                      ],
                    ]),
                  ]),
                ),
                if (priceText.isNotEmpty)
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('from', style: Theme.of(context).textTheme.bodySmall),
                    Text(priceText,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primary)),
                  ]),
              ]),
              if (catNames.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: catNames
                      .take(3)
                      .map((n) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceMuted,
                              borderRadius: AppRadius.pill,
                            ),
                            child: Text(n,
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                          ))
                      .toList(),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
