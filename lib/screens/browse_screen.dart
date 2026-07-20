import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text('Filters',
                      style:
                          TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
              const SizedBox(height: 20),

              // Category filter
              const Text('Service Category',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('All'),
                    selected: tempCategoryId == null,
                    onSelected: (_) =>
                        setSheetState(() => tempCategoryId = null),
                  ),
                  ..._categories.map((cat) => ChoiceChip(
                        label: Text('${cat['icon'] ?? ''} ${cat['name']}'),
                        selected: tempCategoryId == cat['id'],
                        onSelected: (_) =>
                            setSheetState(() => tempCategoryId = cat['id']),
                      )),
                ],
              ),
              const SizedBox(height: 20),

              // Rating filter
              Text(
                'Minimum Rating: ${tempMinRating == 0 ? 'Any' : '${tempMinRating.toStringAsFixed(0)}+ stars'}',
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              const SizedBox(height: 8),
              Slider(
                value: tempMinRating,
                min: 0,
                max: 5,
                divisions: 5,
                label: tempMinRating == 0
                    ? 'Any'
                    : '${tempMinRating.toStringAsFixed(0)}+',
                onChanged: (v) => setSheetState(() => tempMinRating = v),
              ),
              const SizedBox(height: 12),

              // Price range filter
              Text(
                'Price Range: \$${tempPriceRange.start.toStringAsFixed(0)} — \$${tempPriceRange.end.toStringAsFixed(0)}',
                style:
                    const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              const SizedBox(height: 8),
              RangeSlider(
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
              const SizedBox(height: 20),

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
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text('Apply Filters'),
                ),
              ),
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
            child: IconButton(
              icon: const Icon(Icons.tune_rounded),
              tooltip: 'Filters',
              onPressed: _showFilterSheet,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Search by name or location...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {});
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),

          // Active filter chips
          if (_filtersApplied)
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  if (_selectedCategoryId != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: InputChip(
                        label: Text(_categories
                                .where((c) => c['id'] == _selectedCategoryId)
                                .map((c) => c['name'])
                                .firstOrNull ??
                            'Category'),
                        onDeleted: () =>
                            setState(() => _selectedCategoryId = null),
                      ),
                    ),
                  if (_minRating > 0)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: InputChip(
                        label: Text('${_minRating.toStringAsFixed(0)}+ stars'),
                        onDeleted: () => setState(() => _minRating = 0),
                      ),
                    ),
                  if (_priceRange.start > 0 || _priceRange.end < 500)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: InputChip(
                        label: Text(
                            '\$${_priceRange.start.toStringAsFixed(0)}–\$${_priceRange.end.toStringAsFixed(0)}'),
                        onDeleted: () => setState(
                            () => _priceRange = const RangeValues(0, 500)),
                      ),
                    ),
                ],
              ),
            ),

          // Results
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
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
                                          color: Colors.grey.shade400),
                                      const SizedBox(height: 16),
                                      const Text('No stylists found',
                                          style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'Try adjusting your search or filters.',
                                        style: TextStyle(
                                            color: Colors.grey, fontSize: 14),
                                      ),
                                      if (_filtersApplied) ...[
                                        const SizedBox(height: 16),
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
                            padding: const EdgeInsets.all(16),
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
        statusColor = Colors.green;
        statusLabel = 'Available';
        break;
      case 'busy':
        statusColor = Colors.orange;
        statusLabel = 'Busy';
        break;
      default:
        statusColor = Colors.grey;
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
          : '\$${minPrice.toStringAsFixed(0)} – \$${maxPrice.toStringAsFixed(0)}';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/provider/${p['provider_id']}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.pink.shade100,
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(location,
                          style:
                              const TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(statusLabel,
                            style: TextStyle(
                                color: statusColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                        if (totalReviews > 0) ...[
                          const SizedBox(width: 12),
                          Icon(Icons.star, size: 14, color: Colors.amber.shade700),
                          const SizedBox(width: 2),
                          Text(
                            '${rating.toStringAsFixed(1)} ($totalReviews)',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ],
                    ),
                    if (priceText.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(priceText,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.primary)),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
