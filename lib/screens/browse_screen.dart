import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../theme.dart';
import '../widgets/star_rating_widget.dart';

class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  List<Map<String, dynamic>> _providers = [];
  List<Map<String, dynamic>> _categories = [];
  bool _loading = true;

  // Search & filters
  final _searchCtrl = TextEditingController();
  String? _selectedCategoryId;
  double _minRating = 0;
  RangeValues _priceRange = const RangeValues(0, 500);
  bool _filtersApplied = false;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadProviders();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    final data = await supabase
        .from('service_categories')
        .select()
        .order('sort_order');
    if (mounted) {
      setState(() {
        _categories = List<Map<String, dynamic>>.from(data);
      });
    }
  }

  Future<void> _loadProviders() async {
    setState(() => _loading = true);

    // Load providers with their profiles and services
    final data = await supabase
        .from('provider_profiles')
        .select('*, profiles(full_name, location), '
            'services(id, price, category_id, is_active), '
            'subscriptions:subscriptions!subscriptions_provider_id_fkey(status)')
        .eq('is_hidden', false);

    if (mounted) {
      setState(() {
        _providers = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredProviders {
    final query = _searchCtrl.text.trim().toLowerCase();

    return _providers.where((p) {
      final name = (p['profiles']?['full_name'] ?? '').toString().toLowerCase();
      final location = (p['profiles']?['location'] ?? '').toString().toLowerCase();
      final rating = (p['average_rating'] as num?)?.toDouble() ?? 0.0;
      final services = p['services'] as List? ?? [];
      final subs = p['subscriptions'];

      // Hide providers without active subscription
      bool hasActiveSub = false;
      if (subs is List && subs.isNotEmpty) {
        hasActiveSub = subs.any((s) => s['status'] == 'active');
      }
      if (!hasActiveSub) return false;

      // Search by name or location
      if (query.isNotEmpty) {
        if (!name.contains(query) && !location.contains(query)) return false;
      }

      // Minimum rating filter
      if (_minRating > 0 && rating < _minRating) return false;

      // Category filter
      if (_selectedCategoryId != null) {
        final hasCategory = services.any((s) =>
            s['category_id'] == _selectedCategoryId && s['is_active'] == true);
        if (!hasCategory) return false;
      }

      // Price range filter
      if (_filtersApplied) {
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
    }).toList()
      ..sort((a, b) {
        final ratingA = (a['average_rating'] as num?)?.toDouble() ?? 0.0;
        final ratingB = (b['average_rating'] as num?)?.toDouble() ?? 0.0;
        return ratingB.compareTo(ratingA);
      });
  }

  void _showFilterSheet() {
    double tempMinRating = _minRating;
    String? tempCategoryId = _selectedCategoryId;
    RangeValues tempPriceRange = _priceRange;

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
                  Text('Filters', style: Theme.of(context).textTheme.headlineSmall),
                  const Spacer(),
                  TextButton(
                    onPressed: () {
                      setSheetState(() {
                        tempMinRating = 0;
                        tempCategoryId = null;
                        tempPriceRange = const RangeValues(0, 500);
                      });
                    },
                    child: const Text('Reset'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),

              // Category filter
              Text('Service Category', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  _FilterChip(
                    label: 'All',
                    selected: tempCategoryId == null,
                    onSelected: (_) => setSheetState(() => tempCategoryId = null),
                  ),
                  ..._categories.map((cat) => _FilterChip(
                        label: '${cat['icon'] ?? ''} ${cat['name']}',
                        selected: tempCategoryId == cat['id'],
                        onSelected: (_) =>
                            setSheetState(() => tempCategoryId = cat['id']),
                      )),
                ],
              ),
              const SizedBox(height: AppSpacing.xxl),

              // Rating filter
              Text(
                'Minimum Rating: ${tempMinRating == 0 ? 'Any' : '${tempMinRating.toStringAsFixed(0)}+ stars'}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: AppColors.primary,
                  thumbColor: AppColors.primary,
                  inactiveTrackColor: AppColors.primary.withValues(alpha: 0.15),
                  overlayColor: AppColors.primary.withValues(alpha: 0.1),
                ),
                child: Slider(
                  value: tempMinRating,
                  min: 0,
                  max: 5,
                  divisions: 5,
                  label: tempMinRating == 0
                      ? 'Any'
                      : '${tempMinRating.toStringAsFixed(0)}+',
                  onChanged: (v) => setSheetState(() => tempMinRating = v),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Price range filter
              Text(
                'Price Range: \$${tempPriceRange.start.toStringAsFixed(0)} - \$${tempPriceRange.end.toStringAsFixed(0)}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: AppColors.primary,
                  thumbColor: AppColors.primary,
                  inactiveTrackColor: AppColors.primary.withValues(alpha: 0.15),
                  overlayColor: AppColors.primary.withValues(alpha: 0.1),
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
                  onChanged: (v) => setSheetState(() => tempPriceRange = v),
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),

              // Apply button
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    setState(() {
                      _minRating = tempMinRating;
                      _selectedCategoryId = tempCategoryId;
                      _priceRange = tempPriceRange;
                      _filtersApplied = tempMinRating > 0 ||
                          tempCategoryId != null ||
                          tempPriceRange.start > 0 ||
                          tempPriceRange.end < 500;
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

  int get _activeFilterCount {
    int count = 0;
    if (_minRating > 0) count++;
    if (_selectedCategoryId != null) count++;
    if (_priceRange.start > 0 || _priceRange.end < 500) count++;
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredProviders;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Browse Stylists'),
        actions: [
          Badge(
            isLabelVisible: _activeFilterCount > 0,
            label: Text('$_activeFilterCount'),
            backgroundColor: AppColors.primary,
            child: IconButton(
              icon: const Icon(Icons.tune_rounded),
              tooltip: 'Filters',
              onPressed: _showFilterSheet,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: Column(
        children: [
          // Premium search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.cardLight,
                borderRadius: AppRadius.lgAll,
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Search by name or location...',
                  prefixIcon: Icon(Icons.search_rounded, color: AppColors.textTertiary),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear_rounded, color: AppColors.textTertiary),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: AppRadius.lgAll,
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: AppRadius.lgAll,
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: AppRadius.lgAll,
                    borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                  ),
                  filled: true,
                  fillColor: Colors.transparent,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
          ),

          // Active filter chips
          if (_filtersApplied)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: SizedBox(
                height: 38,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                  children: [
                    if (_selectedCategoryId != null)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.sm),
                        child: InputChip(
                          label: Text(_categories
                                  .where((c) => c['id'] == _selectedCategoryId)
                                  .map((c) => c['name'])
                                  .firstOrNull ??
                              'Category'),
                          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                          selectedColor: AppColors.primary.withValues(alpha: 0.15),
                          labelStyle: TextStyle(color: AppColors.primary, fontSize: 13),
                          deleteIconColor: AppColors.primary,
                          side: BorderSide.none,
                          onDeleted: () =>
                              setState(() => _selectedCategoryId = null),
                        ),
                      ),
                    if (_minRating > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.sm),
                        child: InputChip(
                          label: Text('${_minRating.toStringAsFixed(0)}+ stars'),
                          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                          labelStyle: TextStyle(color: AppColors.primary, fontSize: 13),
                          deleteIconColor: AppColors.primary,
                          side: BorderSide.none,
                          onDeleted: () => setState(() => _minRating = 0),
                        ),
                      ),
                    if (_priceRange.start > 0 || _priceRange.end < 500)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.sm),
                        child: InputChip(
                          label: Text(
                              '\$${_priceRange.start.toStringAsFixed(0)} - \$${_priceRange.end.toStringAsFixed(0)}'),
                          backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                          labelStyle: TextStyle(color: AppColors.primary, fontSize: 13),
                          deleteIconColor: AppColors.primary,
                          side: BorderSide.none,
                          onDeleted: () => setState(
                              () => _priceRange = const RangeValues(0, 500)),
                        ),
                      ),
                  ],
                ),
              ),
            ),

          // Results
          Expanded(
            child: _loading
                ? Center(child: CircularProgressIndicator(color: AppColors.primary))
                : RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: _loadProviders,
                    child: filtered.isEmpty
                        ? ListView(
                            children: [
                              SizedBox(
                                height:
                                    MediaQuery.of(context).size.height * 0.5,
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.search_off_rounded,
                                          size: 64,
                                          color: AppColors.textTertiary),
                                      const SizedBox(height: AppSpacing.lg),
                                      Text(
                                        'No stylists found',
                                        style: Theme.of(context).textTheme.titleLarge,
                                      ),
                                      const SizedBox(height: AppSpacing.sm),
                                      const Text(
                                        'Try adjusting your search or filters.',
                                        style: TextStyle(
                                            color: AppColors.textSecondary, fontSize: 14),
                                      ),
                                      if (_filtersApplied) ...[
                                        const SizedBox(height: AppSpacing.xl),
                                        OutlinedButton(
                                          onPressed: () {
                                            setState(() {
                                              _minRating = 0;
                                              _selectedCategoryId = null;
                                              _priceRange =
                                                  const RangeValues(0, 500);
                                              _filtersApplied = false;
                                              _searchCtrl.clear();
                                            });
                                          },
                                          child: const Text('Clear All Filters'),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg,
                              vertical: AppSpacing.sm,
                            ),
                            itemCount: filtered.length,
                            itemBuilder: (_, i) =>
                                _ProviderCard(provider: filtered[i]),
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: onSelected,
      selectedColor: AppColors.primary.withValues(alpha: 0.15),
      labelStyle: TextStyle(
        color: selected ? AppColors.primary : AppColors.textSecondary,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
      ),
      checkmarkColor: AppColors.primary,
      backgroundColor: AppColors.surfaceLight,
      side: BorderSide(
        color: selected ? AppColors.primary.withValues(alpha: 0.3) : Colors.grey.shade300,
      ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  final Map<String, dynamic> provider;
  const _ProviderCard({required this.provider});

  @override
  Widget build(BuildContext context) {
    final p = provider;
    final name = p['profiles']?['full_name'] ?? 'Stylist';
    final location = p['profiles']?['location'] ?? '';
    final status = p['availability_status'] ?? 'offline';
    final rating = (p['average_rating'] as num?)?.toDouble() ?? 0.0;
    final totalReviews = p['total_reviews'] ?? 0;
    final services = (p['services'] as List? ?? [])
        .where((s) => s['is_active'] == true)
        .toList();

    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'available':
        statusColor = AppColors.available;
        statusLabel = 'Available';
        break;
      case 'busy':
        statusColor = AppColors.busy;
        statusLabel = 'Busy';
        break;
      default:
        statusColor = AppColors.offline;
        statusLabel = 'Offline';
    }

    // Price range text
    String priceText = '';
    if (services.isNotEmpty) {
      final prices =
          services.map((s) => (s['price'] as num?)?.toDouble() ?? 0).toList();
      final minPrice = prices.reduce((a, b) => a < b ? a : b);
      final maxPrice = prices.reduce((a, b) => a > b ? a : b);
      priceText = minPrice == maxPrice
          ? '\$${minPrice.toStringAsFixed(0)}'
          : '\$${minPrice.toStringAsFixed(0)} - \$${maxPrice.toStringAsFixed(0)}';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Material(
        color: AppColors.cardLight,
        borderRadius: AppRadius.lgAll,
        child: InkWell(
          borderRadius: AppRadius.lgAll,
          onTap: () => context.push('/provider/${p['provider_id']}'),
          child: Container(
            padding: AppSpacing.cardPadding,
            decoration: BoxDecoration(
              borderRadius: AppRadius.lgAll,
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                // Avatar with gradient background
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: Theme.of(context).textTheme.titleMedium),
                      if (location.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(Icons.location_on_outlined, size: 14, color: AppColors.textTertiary),
                            const SizedBox(width: 2),
                            Expanded(
                              child: Text(
                                location,
                                style: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          // Status dot
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: statusColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs + 2),
                          Text(statusLabel,
                              style: TextStyle(
                                  color: statusColor,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                          if (totalReviews > 0) ...[
                            const SizedBox(width: AppSpacing.md),
                            Icon(Icons.star_rounded, size: 14, color: AppColors.warning),
                            const SizedBox(width: 2),
                            Text(
                              '${rating.toStringAsFixed(1)} ($totalReviews)',
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.textSecondary),
                            ),
                          ],
                        ],
                      ),
                      if (priceText.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(priceText,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary)),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
