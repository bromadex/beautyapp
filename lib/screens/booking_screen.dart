import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../supabase_client.dart';
import '../services/location_service.dart';
import '../utils/pay_methods.dart';
import '../theme.dart';
import '../widgets/booking_bits.dart';
import '../widgets/offers.dart';
import '../widgets/slot_picker.dart';
import '../utils/feel.dart';
import '../widgets/ui.dart';
import '../utils/nav.dart';

/// Step-by-step booking: Service → Time → Pay → Done.
class BookingScreen extends StatefulWidget {
  final String providerId;
  final String serviceId;
  final String? packageId;
  /// Option and extras already picked on the pro's profile.
  final String? initialTierId;
  final List<String> initialAddonIds;
  const BookingScreen({
    super.key,
    required this.providerId,
    required this.serviceId,
    this.packageId,
    this.initialTierId,
    this.initialAddonIds = const [],
  });
  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  static const _stepTitles = ['Service', 'Time', 'Pay', 'Done'];

  bool _loading = true;
  String? _error;
  bool _submitting = false;
  int _step = 0;

  Map<String, dynamic>? _provider;
  Map<String, dynamic>? _providerProfile;
  Map<String, dynamic>? _policy;
  Map<String, dynamic>? _me;
  bool _isGuest = false;

  List<Map<String, dynamic>> _services = [];
  String? _serviceId;
  List<Map<String, dynamic>> _tiers = [];
  String? _tierId;
  bool _appliedInitial = false;
  List<Map<String, dynamic>> _addons = [];
  final Set<String> _addonIds = {};

  DateTime? _day;
  String? _time;

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _promoCtrl = TextEditingController();
  String _payment = 'cash';
  double? _lat;
  double? _lng;
  bool _locating = false;

  Map<String, dynamic>? _promo;
  double _discount = 0;
  String? _promoError;
  Map<String, dynamic>? _loyalty;
  bool _atStudio = false;
  bool _ack = false;
  bool _applyingPromo = false;
  bool _editDetails = false;

  // Salon team, for "Choose your specialist".
  String? _salonId;
  String? _salonName;
  List<Map<String, dynamic>> _team = [];
  List<Map<String, dynamic>> _teamServices = [];
  String? _cover;

  // Done step
  String _doneId = '';
  String _doneRef = '';
  double _doneDeposit = 0;

  // Monthly package with this pro (paid this month), if any.
  Map<String, dynamic>? _pkg;
  bool _usePkg = true;

  Map<String, dynamic>? get _pkgItem {
    final items = List<Map<String, dynamic>>.from(_pkg?['items'] as List? ?? const []);
    return items
        .where((i) => i['service_id'] == _serviceId && ((i['used'] as num?) ?? 0) < ((i['included'] as num?) ?? 0))
        .firstOrNull;
  }

  bool get _usingPkg => _usePkg && _pkgItem != null;

  List<BoxShadow>? get _shadow => AppColors.isDark ? null : AppShadows.lifted;

  @override
  void initState() {
    super.initState();
    _serviceId = widget.serviceId;
    _load();
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl, _phoneCtrl, _addressCtrl, _noteCtrl, _promoCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  // ---------------- data ----------------

  Future<void> _load() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        if (mounted) context.go('/login');
        return;
      }
      _isGuest = user.isAnonymous;
      final results = await Future.wait([
        supabase.from('profiles').select().eq('id', widget.providerId).maybeSingle(),
        supabase.from('provider_profiles').select().eq('provider_id', widget.providerId).maybeSingle(),
        supabase
            .from('services')
            .select('*, service_categories(name, studio_only, needs_certificate, min_age, patch_test)')
            .eq('provider_id', widget.providerId)
            .eq('is_active', true)
            .order('created_at', ascending: true),
        supabase.from('cancellation_policies').select().eq('provider_id', widget.providerId).maybeSingle(),
        supabase.from('profiles').select().eq('id', user.id).maybeSingle(),
      ]);
      _provider = results[0] as Map<String, dynamic>?;
      _providerProfile = results[1] as Map<String, dynamic>?;
      if (_methods.isNotEmpty) _payment = _methods.first.id;
      _services = List<Map<String, dynamic>>.from(results[2] as List);
      _policy = results[3] as Map<String, dynamic>?;
      _me = results[4] as Map<String, dynamic>?;
      if (_provider == null || _services.isEmpty) {
        setState(() {
          _error = 'This pro has no services to book yet.';
          _loading = false;
        });
        return;
      }
      if (!_services.any((s) => s['id'] == _serviceId)) _serviceId = _services.first['id'];
      final name = (_me?['full_name'] ?? '').toString();
      _nameCtrl.text = name == 'User' ? '' : name;
      _phoneCtrl.text = _me?['phone'] ?? '';
      _addressCtrl.text = _me?['location'] ?? '';
      if (((_providerProfile?['loyalty_visits'] as num?) ?? 0) > 0) {
        try {
          _loyalty = Map<String, dynamic>.from(
              await supabase.rpc('loyalty_status', params: {'p_provider': widget.providerId}) as Map);
        } catch (_) {}
      }
      await Future.wait([_loadServiceExtras(), _loadTeam()]);
      if (mounted) setState(() => _loading = false);
      // Came from a public offer: fill the code in and apply it.
      final code = OfferMemory.take(widget.providerId);
      if (code != null && code.isNotEmpty && mounted) {
        _promoCtrl.text = code;
        await _applyPromo();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load booking details. Check your connection and try again.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadServiceExtras() async {
    final results = await Future.wait([
      supabase
          .from('service_tiers')
          .select()
          .eq('service_id', _serviceId!)
          .eq('is_active', true)
          .order('sort_order', ascending: true)
          .order('price', ascending: true),
      supabase
          .from('service_addons')
          .select()
          .eq('service_id', _serviceId!)
          .eq('is_active', true)
          .order('sort_order', ascending: true),
    ]);
    _tiers = List<Map<String, dynamic>>.from(results[0] as List);
    _addons = List<Map<String, dynamic>>.from(results[1] as List);
    _tierId = _tiers.isNotEmpty ? _tiers.first['id'] : null;
    _addonIds.clear();
    if (!_appliedInitial && _serviceId == widget.serviceId) {
      _appliedInitial = true;
      if (_tiers.any((t) => t['id'] == widget.initialTierId)) _tierId = widget.initialTierId;
      _addonIds.addAll(widget.initialAddonIds.where((id) => _addons.any((a) => a['id'] == id)));
    }
    _time = null;
  }

  /// The salon this pro works at, its team and their services, so the
  /// client can pick a different specialist for the same kind of service.
  Future<void> _loadTeam() async {
    try {
      final mine = await supabase.rpc('my_packages') as List;
      _pkg = mine.cast<Map>().map((m) => Map<String, dynamic>.from(m)).where((m) =>
          m['provider_id'] == widget.providerId && m['status'] == 'active' && m['pay_status'] == 'paid').firstOrNull;
    } catch (_) {}
    try {
      final g = await supabase
          .from('hairstyle_gallery')
          .select('image_url')
          .eq('provider_id', widget.providerId)
          .eq('is_approved', true)
          .order('uploaded_at', ascending: false)
          .limit(1);
      if ((g as List).isNotEmpty) _cover = g.first['image_url'] as String?;
    } catch (_) {}
    try {
      final m = await supabase
          .from('salon_members')
          .select('salon_id, salons(id, name)')
          .eq('provider_id', widget.providerId)
          .maybeSingle();
      final salon = (m?['salons'] as Map?)?.cast<String, dynamic>();
      if (salon == null) return;
      _salonId = salon['id'] as String?;
      _salonName = salon['name'] as String?;
      final members = await supabase
          .from('salon_members')
          .select('profiles!salon_members_provider_id_fkey(id, full_name, avatar_url)')
          .eq('salon_id', _salonId!)
          .order('joined_at');
      final ids = [for (final r in members as List) (r['profiles'] as Map?)?['id']].whereType<String>().toList();
      if (ids.length < 2) return;
      final res = await Future.wait([
        supabase
            .from('provider_profiles')
            .select('provider_id, average_rating, total_reviews, is_hidden')
            .inFilter('provider_id', ids),
        supabase
            .from('services')
            .select('id, provider_id, category_id, service_name')
            .inFilter('provider_id', ids)
            .eq('is_active', true),
      ]);
      final pps = {for (final p in res[0] as List) p['provider_id']: p};
      _team = [
        for (final r in members)
          if (r['profiles'] != null && pps[(r['profiles'] as Map)['id']]?['is_hidden'] != true)
            {
              ...Map<String, dynamic>.from(r['profiles'] as Map),
              ...?(pps[(r['profiles'] as Map)['id']] as Map?)?.cast<String, dynamic>(),
            },
      ];
      _teamServices = List<Map<String, dynamic>>.from(res[1] as List);
    } catch (_) {}
  }

  /// Team members who offer this kind of service, each with the service to book.
  List<Map<String, dynamic>> get _specialists {
    if (_team.length < 2) return const [];
    final cat = _service['category_id'];
    final name = (_service['service_name'] ?? '').toString().toLowerCase();
    final out = <Map<String, dynamic>>[];
    for (final p in _team) {
      if (p['id'] == widget.providerId) {
        out.add({...p, 'service_id': _serviceId});
        continue;
      }
      final mine = _teamServices.where((s) => s['provider_id'] == p['id'] && s['category_id'] == cat).toList();
      if (mine.isEmpty) continue;
      final same = mine.where((s) => (s['service_name'] ?? '').toString().toLowerCase() == name);
      out.add({...p, 'service_id': (same.isNotEmpty ? same.first : mine.first)['id']});
    }
    out.sort((a, b) => (a['id'] == widget.providerId ? 0 : 1).compareTo(b['id'] == widget.providerId ? 0 : 1));
    return out;
  }

  void _pickSpecialist(Map<String, dynamic> p) {
    if (p['id'] == widget.providerId) return;
    Haptics.light();
    context.pushReplacement('/book/${p['id']}/${p['service_id']}');
  }

  Map<String, dynamic> get _service => _services.firstWhere((s) => s['id'] == _serviceId);
  Map<String, dynamic>? get _tier =>
      _tierId == null ? null : _tiers.firstWhere((t) => t['id'] == _tierId, orElse: () => const {});

  double get _basePrice => ((_tier?['price'] ?? _service['price']) as num?)?.toDouble() ?? 0;
  int get _baseMinutes => ((_tier?['duration_minutes'] ?? _service['duration_minutes']) as num?)?.toInt() ?? 60;
  double get _addonsTotal => _addons
      .where((a) => _addonIds.contains(a['id']))
      .fold(0.0, (s, a) => s + ((a['price'] as num?)?.toDouble() ?? 0));
  int get _addonsMinutes => _addons
      .where((a) => _addonIds.contains(a['id']))
      .fold(0, (s, a) => s + ((a['duration_minutes'] as num?)?.toInt() ?? 0));
  int get _totalMinutes => _baseMinutes + _addonsMinutes;

  String get _mode => (_service['location_mode'] ?? 'either') as String;
  bool get _studio => _mode == 'studio' || (_mode == 'either' && _atStudio);
  Map<String, dynamic>? get _cat => _service['service_categories'] as Map<String, dynamic>?;
  bool get _isMassage => _cat?['studio_only'] == true && _cat?['needs_certificate'] == true;
  int? get _minAge => (_cat?['min_age'] as num?)?.toInt();
  bool get _needsAck => _isMassage || _minAge != null;
  String get _studioArea {
    final area = (_providerProfile?['area'] ?? '').toString().trim();
    if (area.isNotEmpty) return area;
    final a = (_provider?['location'] ?? '').toString();
    return a.isEmpty ? 'their area' : a.split(',').first.trim();
  }

  double get _travelFee {
    if (_studio) return 0;
    final pp = _providerProfile;
    final perKm = (pp?['travel_fee_per_km'] as num?)?.toDouble() ?? 0;
    final lat = (pp?['latitude'] as num?)?.toDouble();
    final lng = (pp?['longitude'] as num?)?.toDouble();
    if (perKm <= 0 || lat == null || lng == null || _lat == null) return 0;
    double rad(double d) => d * math.pi / 180;
    final a = math.pow(math.sin(rad(_lat! - lat) / 2), 2) +
        math.cos(rad(lat)) * math.cos(rad(_lat!)) * math.pow(math.sin(rad(_lng! - lng) / 2), 2);
    final km = 6371 * 2 * math.asin(math.sqrt(a));
    final free = (pp?['free_travel_radius_km'] as num?)?.toDouble() ?? 0;
    final maxFee = (pp?['max_travel_fee'] as num?)?.toDouble() ?? 20;
    return (math.min(maxFee, math.max(0, km - free) * perKm) * 100).roundToDouble() / 100;
  }

  double get _loyaltyDiscount => _loyalty?['available'] == true
      ? (_basePrice * ((_loyalty!['percent'] as num).toDouble()) / 100 * 100).roundToDouble() / 100
      : 0;
  double get _total => _usingPkg
      ? _addonsTotal + _travelFee // the service itself is covered by the package
      : math.max(0, _basePrice - _discount - _loyaltyDiscount) + _addonsTotal + _travelFee;
  List<PayMethod> get _methods {
    final m = payMethodsOf(_providerProfile);
    return m.isEmpty ? const [PayMethod('cash', 'Cash', TablerIcons.cash)] : m;
  }

  bool get _takesTransfers => _methods.any((m) => m.isTransfer);

  // Matches the server: no deposit if the pro has nowhere to receive it.
  int get _depositPercent => _usingPkg
      ? 0
      : _takesTransfers ? (_providerProfile?['deposit_percent'] as num?)?.toInt() ?? 0 : 0;
  double get _deposit => (_total * _depositPercent / 100 * 100).roundToDouble() / 100;

  String _money(double v) => '\$${v.toStringAsFixed(v % 1 == 0 ? 0 : 2)}';

  // ---------------- actions ----------------

  Future<void> _selectService(String id) async {
    if (id == _serviceId) return;
    setState(() {
      _serviceId = id;
      _promo = null;
      _discount = 0;
    });
    await _loadServiceExtras();
    if (mounted) setState(() {});
  }

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    try {
      final pos = await LocationService().getCurrentPosition(
          context: context,
          reason: 'So your pro knows where to come and the travel fee is worked out correctly.');
      if (pos != null && mounted) {
        setState(() {
          _lat = pos.latitude;
          _lng = pos.longitude;
        });
      } else if (mounted) {
        _toast('Location unavailable — the pro will agree any travel fee with you.');
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _applyPromo() async {
    final code = _promoCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _applyingPromo = true;
      _promoError = null;
    });
    try {
      final rows = await supabase.rpc('check_promo', params: {
        'p_provider': widget.providerId,
        'p_code': code,
        'p_amount': _basePrice,
      }) as List;
      final res = rows.isNotEmpty ? rows.first as Map<String, dynamic> : null;
      setState(() {
        if (res == null || res['error'] != null) {
          _promoError = res?['error'] ?? 'Invalid promo code';
          _promo = null;
          _discount = 0;
        } else {
          _promo = {'code': code.toUpperCase()};
          _discount = (res['discount'] as num).toDouble();
        }
      });
    } catch (_) {
      setState(() => _promoError = 'Could not check the code');
    } finally {
      if (mounted) setState(() => _applyingPromo = false);
    }
  }

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? AppColors.error : null),
    );
  }

  bool _validateStep() {
    switch (_step) {
      case 1:
        if (_day == null || _time == null) {
          _toast('Pick a day and a time');
          return false;
        }
      case 2:
        if (_nameCtrl.text.trim().isEmpty) {
          setState(() => _editDetails = true);
          _toast('Please enter your name');
          return false;
        }
        if (_phoneCtrl.text.trim().replaceAll(RegExp(r'\D'), '').length < 9) {
          setState(() => _editDetails = true);
          _toast('Please enter a phone number the pro can reach you on');
          return false;
        }
        if (!_studio && _addressCtrl.text.trim().isEmpty) {
          _toast('Please enter where the pro should come');
          return false;
        }
        if (_needsAck && !_ack) {
          _toast('Please tick the box to accept the rules for this service');
          return false;
        }
    }
    return true;
  }

  void _next() {
    if (!_validateStep()) {
      Haptics.warn();
      return;
    }
    if (_step < 2) {
      Haptics.light();
      setState(() => _step++);
    } else {
      _confirm();
    }
  }

  Future<void> _confirm() async {
    setState(() => _submitting = true);
    try {
      final uid = supabase.auth.currentUser!.id;
      final name = _nameCtrl.text.trim();
      final phone = _phoneCtrl.text.trim();
      if (name != (_me?['full_name'] ?? '') || phone != (_me?['phone'] ?? '')) {
        await supabase.from('profiles').update({'full_name': name, 'phone': phone}).eq('id', uid);
      }

      final inserted = await supabase
          .from('bookings')
          .insert({
            'client_id': uid,
            'provider_id': widget.providerId,
            'service_id': _serviceId,
            if (_tierId != null) 'tier_id': _tierId,
            'booking_time': slotToDateTime(_day!, _time!).toIso8601String(),
            'address': _studio ? 'At the pro\'s place' : _addressCtrl.text.trim(),
            'at_studio': _studio,
            'client_ack': _ack,
            'status': 'pending',
            'total_price': _total,
            'promo_code': _usingPkg ? null : _promo?['code'],
            if (_usingPkg) 'package_period_id': _pkg!['period_id'],
            'payment_method': _payment,
            if (_lat != null) 'client_lat': _lat,
            if (_lng != null) 'client_lng': _lng,
            'client_note': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
          })
          .select('id, ref')
          .single();
      final bookingId = inserted['id'] as String;

      if (_addonIds.isNotEmpty) {
        await supabase.from('booking_addons').insert(_addons
            .where((a) => _addonIds.contains(a['id']))
            .map((a) => {
                  'booking_id': bookingId,
                  'addon_id': a['id'],
                  'addon_name': a['name'],
                  'addon_price': a['price'],
                  'addon_duration': a['duration_minutes'] ?? 0,
                })
            .toList());
      }

      final fresh = await supabase.from('bookings').select('deposit_amount').eq('id', bookingId).single();
      final deposit = ((fresh['deposit_amount'] as num?) ?? 0).toDouble();

      if (!mounted) return;
      Haptics.firm();
      setState(() {
        _doneId = bookingId;
        _doneRef = (inserted['ref'] ?? '').toString();
        _doneDeposit = deposit;
        _step = 3;
      });
    } on PostgrestException catch (e) {
      if (mounted) _toast(e.message, error: true);
    } catch (e) {
      if (mounted) _toast('Something went wrong: $e', error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ---------------- UI ----------------

  static const _wideAt = 900.0;

  void _back() {
    if (_step == 3) {
      openWithParents(context, '/booking/$_doneId');
    } else if (_step > 0) {
      setState(() => _step--);
    } else {
      goBack(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingPlaceholder(kind: PlaceholderKind.detail));
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: TablerIcons.calendar_x,
          title: 'Can\'t book right now',
          message: _error!,
          actionLabel: 'Go back',
          onAction: () => context.canPop() ? context.pop() : context.go('/home'),
        ),
      );
    }

    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: _step == 3 ? 'Close' : 'Back',
            icon: Icon(_step == 3 ? TablerIcons.x : TablerIcons.chevron_left, size: 26),
            onPressed: _back,
          ),
          title: Text(_step == 3 ? 'Booked' : 'Book'),
        ),
        body: LayoutBuilder(builder: (context, box) {
          final wide = box.maxWidth >= _wideAt;
          final steps = Padding(
            padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
            child: BookingStepBar(
              step: _step,
              titles: _stepTitles,
              onTapStep: _step == 3 ? null : (i) => setState(() => _step = i),
            ),
          );
          final content = AnimatedSwitcher(
            duration: Motion.of(context),
            switchInCurve: Motion.curve,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween(begin: const Offset(0.04, 0), end: Offset.zero).animate(anim),
                child: child,
              ),
            ),
            child: KeyedSubtree(
              key: ValueKey(_step),
              child: switch (_step) {
                0 => _serviceStep(),
                1 => _whenStep(),
                2 => _payStep(),
                _ => _doneStep(),
              },
            ),
          );

          if (wide && _step < 3) {
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 640, child: steps),
                  Expanded(
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(
                        child: ListView(padding: const EdgeInsets.fromLTRB(20, 14, 20, 32), children: [content]),
                      ),
                      SizedBox(
                        width: 370,
                        child: ListView(padding: const EdgeInsets.fromLTRB(8, 14, 20, 32), children: [
                          _summaryCard(),
                          const SizedBox(height: 14),
                          _action(),
                        ]),
                      ),
                    ]),
                  ),
                ]),
              ),
            );
          }

          return Column(children: [
            Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: kReadableMaxWidth), child: steps)),
            Expanded(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: kReadableMaxWidth),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                    children: [content],
                  ),
                ),
              ),
            ),
            if (_step < 3)
              Container(
                color: Theme.of(context).scaffoldBackgroundColor,
                padding: EdgeInsets.fromLTRB(20, 8, 20, 12 + MediaQuery.of(context).padding.bottom),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: kReadableMaxWidth),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      if (_step == 1 && _day != null && _time != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(_whenRange(), style: Theme.of(context).textTheme.bodySmall),
                        ),
                      _action(),
                    ]),
                  ),
                ),
              ),
          ]);
        }),
      ),
    );
  }

  /// The main button: "$40 · Continue", or Slide to book on the Pay step.
  Widget _action() {
    if (_step == 2) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        SlideToBook(
          busy: _submitting,
          onConfirm: _submitting ? null : _next,
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: _submitting ? null : _next,
          style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary, minimumSize: const Size(0, 36)),
          child: const Text('or tap here to book', style: TextStyle(fontSize: 13, decoration: TextDecoration.underline)),
        ),
      ]);
    }
    return BigPriceButton(
      price: _money(_total),
      label: _step == 0 ? 'Choose a time' : 'Continue',
      onPressed: _next,
    );
  }

  String get _firstName => (_provider?['full_name'] ?? 'your pro').toString().split(' ').first;

  Widget _heading(String title, String sub) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: TextStyle(
                  fontFamily: AppTheme.displayFamily,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.5,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(sub, style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
        ]),
      );

  Widget _label(String t, {Widget? trailing}) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
        child: Row(children: [
          Expanded(
            child: Text(t.toUpperCase(),
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.textSecondary)),
          ),
          ?trailing,
        ]),
      );

  Widget _serviceStep() {
    final where = _salonName != null
        ? '$_salonName${_studioArea != 'their area' ? ' · $_studioArea' : ''}'
        : 'with ${_provider?['full_name'] ?? 'your pro'}';
    final others = _services.where((s) => s['id'] != _serviceId).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _heading('What would you like?', where),
      _chosenServiceCard(),
      if (_pkgItem != null) ...[
        const SizedBox(height: 10),
        _PackageUse(
          name: _pkg!['name'] ?? 'Package',
          left: (((_pkgItem!['included'] as num?) ?? 0) - ((_pkgItem!['used'] as num?) ?? 0)).toInt(),
          on: _usePkg,
          onChanged: (v) {
            Haptics.light();
            setState(() => _usePkg = v);
          },
        ),
      ],
      if (_specialists.length > 1) ...[
        _label('Choose your specialist',
            trailing: _salonId == null
                ? null
                : GestureDetector(
                    onTap: () => context.push('/salon/$_salonId'),
                    child: Text('About the team',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.goldText)),
                  )),
        SizedBox(
          height: 112,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _specialists.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) => _SpecialistChip(
              pro: _specialists[i],
              selected: _specialists[i]['id'] == widget.providerId,
              onTap: () => _pickSpecialist(_specialists[i]),
            ),
          ),
        ),
      ],
      if (others.isNotEmpty) ...[
        _label('Or choose another service'),
        ...others.map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _SelectCard(
                selected: false,
                onTap: () {
                  Haptics.light();
                  _selectService(s['id']);
                },
                leading: CategoryBadge(name: s['service_categories']?['name'], size: 40),
                title: s['service_name'] ?? 'Service',
                subtitle: _durationLabel(((s['duration_minutes'] as num?) ?? 60).toInt()),
                trailing: _money(((s['price'] as num?) ?? 0).toDouble()),
              ),
            )),
      ],
    ]);
  }

  /// The service being booked, with its options and extras inside.
  Widget _chosenServiceCard() {
    final cover = _cover;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.lgAll, boxShadow: _shadow),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          SizedBox(
            width: 52,
            height: 52,
            child: ProPhoto(name: _service['service_name'] ?? '', url: cover ?? _provider?['avatar_url'], radius: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_service['service_name'] ?? 'Service',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text(
                  '${_durationLabel(_totalMinutes)}${_tiers.isNotEmpty || _addons.isNotEmpty ? ' · ${_tiers.length + _addons.length} options' : ''}',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            ]),
          ),
          Text(_money(_total - _travelFee),
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        ]),
        if (_tiers.isNotEmpty || _addons.isNotEmpty) ...[
          const SizedBox(height: 10),
          Divider(height: 1, color: AppColors.border),
          for (final t in _tiers)
            _OptionLine(
              title: t['name'] ?? '',
              price: _money(((t['price'] as num?) ?? 0).toDouble()),
              selected: _tierId == t['id'],
              radio: true,
              onTap: () {
                Haptics.light();
                setState(() {
                  _tierId = t['id'];
                  _time = null;
                });
              },
            ),
          for (final a in _addons)
            _OptionLine(
              title: a['name'] ?? '',
              price: '+${_money(((a['price'] as num?) ?? 0).toDouble())}',
              selected: _addonIds.contains(a['id']),
              onTap: () {
                Haptics.light();
                setState(() {
                  _addonIds.contains(a['id']) ? _addonIds.remove(a['id']) : _addonIds.add(a['id']);
                  _time = null;
                });
              },
            ),
        ],
      ]),
    );
  }

  String _durationLabel(int mins) =>
      mins >= 60 ? '${mins ~/ 60} h${mins % 60 > 0 ? ' ${mins % 60} min' : ''}' : '$mins min';

  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  String _dayLabel(DateTime d) => '${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

  String _whenRange() {
    final h = int.parse(_time!.substring(0, 2));
    final m = int.parse(_time!.substring(3, 5));
    final end = h * 60 + m + _totalMinutes;
    final e = '${(end ~/ 60 % 24).toString().padLeft(2, '0')}:${(end % 60).toString().padLeft(2, '0')}';
    return '${_dayLabel(_day!)} · $_time – $e';
  }

  Widget _whenStep() {
    final notice = (_providerProfile?['min_notice_hours'] as num?)?.toInt() ?? 2;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _heading('When suits you?', '${_durationLabel(_totalMinutes)} with ${_provider?['full_name'] ?? 'your pro'}'),
      SlotPicker(
        key: ValueKey('$_serviceId-$_totalMinutes'),
        providerId: widget.providerId,
        minutes: _totalMinutes,
        allowWaitlist: true,
        serviceId: _serviceId,
        initialDate: _day,
        initialTime: _time,
        onChanged: (d, t) => setState(() {
          _day = d;
          _time = t;
        }),
      ),
      if (notice > 0)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('Only free times are shown. Book at least $notice ${notice == 1 ? 'hour' : 'hours'} ahead.',
              style: Theme.of(context).textTheme.bodySmall),
        ),
    ]);
  }

  Widget _payStep() {
    final hasTravel = ((_providerProfile?['travel_fee_per_km'] as num?) ?? 0) > 0;
    final detailsKnown = _nameCtrl.text.trim().isNotEmpty &&
        _phoneCtrl.text.trim().replaceAll(RegExp(r'\D'), '').length >= 9 &&
        !_editDetails;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _heading('Almost done', _day != null && _time != null ? _whenRange() : 'Check the details and book'),
      if (_mode == 'either') ...[
        _label('Where'),
        _Segment(
          options: const ['Come to me', 'At the pro\'s place'],
          icons: const [TablerIcons.home, TablerIcons.building_store],
          selected: _atStudio ? 1 : 0,
          onChanged: (i) {
            Haptics.light();
            setState(() => _atStudio = i == 1);
          },
        ),
        const SizedBox(height: 10),
      ] else
        _label('Where'),
      if (_studio)
        _note(TablerIcons.building_store,
            'At $_firstName\'s place${_salonName != null ? ' ($_salonName)' : ''} in $_studioArea. '
            'You\'ll see the exact address once your booking is confirmed.')
      else ...[
        if (_mode == 'client') _note(TablerIcons.home, '$_firstName comes to you for this service.'),
        if (_mode == 'client') const SizedBox(height: 10),
        TextField(
          controller: _addressCtrl,
          maxLines: 2,
          minLines: 1,
          decoration: const InputDecoration(
            labelText: 'Where should the pro come?',
            hintText: 'e.g. 12 Borrowdale Rd, Harare',
            prefixIcon: Icon(TablerIcons.map_pin),
          ),
        ),
        if (hasTravel)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _locating ? null : _useMyLocation,
              icon: _locating
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator.adaptive(strokeWidth: 2))
                  : const Icon(TablerIcons.current_location, size: 18),
              label: Text(_lat == null
                  ? 'Use my location to work out travel fee'
                  : _travelFee > 0
                      ? 'Travel fee: ${_money(_travelFee)}'
                      : 'You\'re within the free travel area'),
            ),
          ),
      ],
      _label('How will you pay?'),
      LayoutBuilder(builder: (context, box) {
        final w = (box.maxWidth - 8) / 2;
        return Wrap(spacing: 8, runSpacing: 8, children: [
          for (final m in _methods)
            SizedBox(
              width: w,
              child: _PayTile(
                method: m,
                note: m.id == 'cash' ? 'on the day' : '$_firstName accepts',
                selected: _payment == m.id,
                onTap: () {
                  Haptics.light();
                  setState(() => _payment = m.id);
                },
              ),
            ),
        ]);
      }),
      const SizedBox(height: 8),
      Text(
        _depositPercent > 0
            ? 'After you book, send the ${_money(_deposit)} deposit to $_firstName within 2 hours and tap "I\'ve paid". '
                'The rest is paid ${_payment == 'cash' ? 'in cash' : 'by ${payMethodLabel(_payment)}'} on the day.'
            : !_takesTransfers
                ? '$_firstName only takes cash for now. Pay on the day.'
                : _payment == 'cash'
                    ? 'Pay $_firstName in cash on the day.'
                    : 'You pay $_firstName directly. BeauTap never holds your money.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      _label('Your details',
          trailing: detailsKnown
              ? GestureDetector(
                  onTap: () => setState(() => _editDetails = true),
                  child: Text('Change', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.goldText)),
                )
              : null),
      if (detailsKnown)
        _note(TablerIcons.user, '${_nameCtrl.text.trim()} · ${_phoneCtrl.text.trim()}')
      else ...[
        TextField(
          controller: _nameCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Your name', prefixIcon: Icon(TablerIcons.user)),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _phoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Phone (WhatsApp)',
            hintText: '+263 7X XXX XXXX',
            prefixIcon: Icon(TablerIcons.phone),
          ),
        ),
      ],
      const SizedBox(height: 10),
      TextField(
        controller: _noteCtrl,
        maxLines: 3,
        minLines: 1,
        decoration: const InputDecoration(
          labelText: 'Note for the pro (optional)',
          hintText: 'e.g. Gate code, hair length, bring products',
          prefixIcon: Icon(TablerIcons.notes),
        ),
      ),
      const SizedBox(height: 10),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: TextField(
            controller: _promoCtrl,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'Promo code (optional)',
              prefixIcon: const Icon(TablerIcons.tag),
              errorText: _promoError,
              helperText: _promo != null ? 'Saved ${_money(_discount)}' : null,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 56,
          child: OutlinedButton(
            onPressed: _applyingPromo ? null : _applyPromo,
            child: Text(_applyingPromo ? '…' : 'Apply'),
          ),
        ),
      ]),
      const SizedBox(height: 14),
      if (MediaQuery.sizeOf(context).width < _wideAt) _priceCard(),
      if (_service['patch_test'] == true) ...[
        const SizedBox(height: 12),
        SoftBanner(
          icon: TablerIcons.alert_circle,
          color: AppColors.warningText,
          title: 'Patch test needed',
          message: 'Ask your pro for a small test 24–48 hours before, to check for any reaction.',
        ),
      ],
      if (_needsAck) ...[
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(color: AppColors.warningSoft, borderRadius: AppRadius.mdAll),
          child: CheckboxListTile(
            value: _ack,
            onChanged: (v) => setState(() => _ack = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
            title: Text(
              [
                if (_isMassage)
                  'Professional therapeutic massage only. Inappropriate requests will get my account banned.',
                if (_minAge != null) 'I am $_minAge or older.',
              ].join(' '),
              style: TextStyle(fontSize: 14, height: 1.4, color: AppColors.textPrimary),
            ),
          ),
        ),
      ],
      if (_policy != null) ...[
        const SizedBox(height: 12),
        Text(
          'Free cancellation up to ${_policy!['free_cancel_hours']} h before. '
          'After that, a ${_policy!['late_cancel_fee_percent']}% late-cancellation fee applies.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ]);
  }

  Widget _note(IconData icon, String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.mdAll, boxShadow: _shadow),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: AppColors.goldText, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(fontSize: 14, height: 1.4, color: AppColors.textPrimary))),
        ]),
      );

  /// Price breakdown: service, extras, travel, discounts, deposit, total.
  Widget _priceCard() {
    Widget row(String l, String r, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Expanded(child: Text(l, style: TextStyle(fontSize: 14, color: AppColors.textSecondary))),
            Text(r, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color ?? AppColors.textPrimary)),
          ]),
        );
    final tierName = (_tier != null && _tier!.isNotEmpty) ? ' · ${_tier!['name']}' : '';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.lgAll, boxShadow: _shadow),
      child: Column(children: [
        _usingPkg
            ? row('${_service['service_name'] ?? 'Service'}$tierName', 'In ${_pkg!['name']}', color: const Color(0xFF1F8A4C))
            : row('${_service['service_name'] ?? 'Service'}$tierName', _money(_basePrice)),
        ..._addons
            .where((a) => _addonIds.contains(a['id']))
            .map((a) => row(a['name'] ?? 'Extra', '+${_money(((a['price'] as num?) ?? 0).toDouble())}')),
        if (_travelFee > 0) row('Travel', '+${_money(_travelFee)}'),
        if (_discount > 0) row('Promo ${_promo?['code']}', '-${_money(_discount)}', color: AppColors.success),
        if (_loyaltyDiscount > 0)
          row('Loyalty reward (${_loyalty!['percent']}%)', '-${_money(_loyaltyDiscount)}', color: AppColors.success),
        if (_deposit > 0) row('Deposit to send after booking', _money(_deposit), color: AppColors.goldText),
        Divider(height: 18, color: AppColors.border),
        Row(children: [
          Expanded(
              child: Text('Total', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
          Text(_money(_total),
              style: TextStyle(
                  fontFamily: AppTheme.displayFamily,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
        ]),
      ]),
    );
  }

  /// Laptop: the summary that stays on the right.
  Widget _summaryCard() {
    final tierName = (_tier != null && _tier!.isNotEmpty) ? _tier!['name'] : null;
    final extras = _addons.where((a) => _addonIds.contains(a['id'])).map((a) => a['name']).join(', ');
    Widget line(String l, String r) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l, style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
            const SizedBox(width: 12),
            Expanded(
                child: Text(r,
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.lgAll, boxShadow: _shadow),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          PersonAvatar(name: _provider?['full_name'] ?? '', url: _provider?['avatar_url'], size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_service['service_name'] ?? 'Service',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              if (tierName != null || extras.isNotEmpty)
                Text([?tierName, if (extras.isNotEmpty) extras].join(' · '),
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        line('Specialist', _provider?['full_name'] ?? ''),
        if (_day != null && _time != null) line('When', '${_dayLabel(_day!)} · $_time'),
        line('Takes', _durationLabel(_totalMinutes)),
        line('Where', _studio ? '${_salonName ?? 'Pro\'s place'} · $_studioArea' : 'Comes to you'),
        if (_step == 2) line('Pay', payMethodLabel(_payment)),
        const SizedBox(height: 8),
        _priceCardInner(),
      ]),
    );
  }

  Widget _priceCardInner() => DecoratedBox(
          decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: AppRadius.mdAll),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Column(children: [
              if (_deposit > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(children: [
                    Expanded(child: Text('Deposit', style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary))),
                    Text(_money(_deposit),
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.goldText)),
                  ]),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(children: [
                  Expanded(
                      child: Text('Total',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
                  Text(_money(_total),
                      style: TextStyle(
                          fontFamily: AppTheme.displayFamily,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                ]),
              ),
            ]),
          ),
      );

  Widget _doneStep() {
    final tierName = (_tier != null && _tier!.isNotEmpty) ? ' · ${_tier!['name']}' : '';
    Widget box(String l, String v) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: AppRadius.smAll),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 2),
              Text(v, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            ]),
          ),
        );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(children: [
          const SizedBox(height: 18),
          const BookedCelebration(),
          const SizedBox(height: 18),
          Text('You\'re booked!',
              style: TextStyle(
                  fontFamily: AppTheme.displayFamily,
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.6,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Text('$_firstName will confirm soon. We\'ll let you know the moment they do.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, height: 1.45, color: AppColors.textSecondary)),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.lgAll, boxShadow: _shadow),
            child: Column(children: [
              Row(children: [
                PersonAvatar(name: _provider?['full_name'] ?? '', url: _provider?['avatar_url'], size: 50),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${_service['service_name'] ?? ''}$tierName',
                        style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    Text('with ${_provider?['full_name'] ?? ''}${_salonName != null ? ' · $_salonName' : ''}',
                        style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                  ]),
                ),
                Text(_money(_total),
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ]),
              const SizedBox(height: 12),
              if (_day != null && _time != null)
                Row(children: [
                  box('Date', _dayLabel(_day!)),
                  const SizedBox(width: 10),
                  box('Time', _whenRange().split(' · ').last),
                ]),
              const SizedBox(height: 12),
              _DashedLine(color: AppColors.border),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: Text('Booking ref', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary))),
                Text(_doneRef.isEmpty ? '–' : _doneRef,
                    style: TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppColors.textPrimary)),
              ]),
            ]),
          ),
          if (_doneDeposit > 0) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: AppRadius.mdAll),
              child: Text.rich(
                TextSpan(children: [
                  const TextSpan(text: 'Send the '),
                  TextSpan(
                      text: '${_money(_doneDeposit)} deposit',
                      style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.goldText)),
                  TextSpan(text: ' by ${payMethodLabel(_payment)} within 2 hours, or the slot is released.'),
                ]),
                style: TextStyle(fontSize: 13.5, height: 1.4, color: AppColors.textPrimary),
              ),
            ),
          ],
          if (_isGuest) ...[
            const SizedBox(height: 12),
            SoftBanner(
              icon: TablerIcons.bookmark_plus,
              color: AppColors.primary,
              title: 'Keep your bookings safe',
              message: 'Create a free account from Settings so you can find this booking on any phone.',
            ),
          ],
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: SizedBox(
                height: 52,
                child: _doneDeposit > 0
                    ? OutlinedButton(
                        onPressed: () => openWithParents(context, '/booking/$_doneId'),
                        style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
                        child: const Text('View booking'),
                      )
                    : FilledButton(
                        onPressed: () => openWithParents(context, '/booking/$_doneId'),
                        style: FilledButton.styleFrom(shape: const StadiumBorder()),
                        child: const Text('View booking'),
                      ),
              ),
            ),
            if (_doneDeposit > 0) ...[
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: FilledButton(
                    onPressed: () => openWithParents(context, '/pay/$_doneId'),
                    style: FilledButton.styleFrom(shape: const StadiumBorder()),
                    child: Text('Pay ${_money(_doneDeposit)} deposit'),
                  ),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => context.go('/bookings'),
            child: const Text('Go to my bookings'),
          ),
        ]),
      ),
    );
  }
}

class _OptionLine extends StatelessWidget {
  final String title;
  final String price;
  final bool selected;
  final bool radio;
  final VoidCallback onTap;
  const _OptionLine(
      {required this.title, required this.price, required this.selected, required this.onTap, this.radio = false});

  @override
  Widget build(BuildContext context) {
    final mark = radio
        ? AnimatedContainer(
            duration: Motion.fast,
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: selected ? AppColors.gold : AppColors.borderStrong, width: selected ? 6 : 2),
            ),
          )
        : AnimatedContainer(
            duration: Motion.fast,
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: selected ? AppColors.gold : null,
              borderRadius: BorderRadius.circular(6),
              border: selected ? null : Border.all(color: AppColors.borderStrong, width: 2),
            ),
            child: selected ? const Icon(TablerIcons.check, size: 14, color: Color(0xFF17130E)) : null,
          );
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 46,
          child: Row(children: [
            mark,
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: TextStyle(fontSize: 14.5, color: AppColors.textPrimary))),
            Text(price, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          ]),
        ),
      ),
    );
  }
}

class _SpecialistChip extends StatelessWidget {
  final Map<String, dynamic> pro;
  final bool selected;
  final VoidCallback onTap;
  const _SpecialistChip({required this.pro, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = (pro['full_name'] ?? '').toString();
    final rating = (pro['average_rating'] as num?)?.toDouble() ?? 0;
    final reviews = (pro['total_reviews'] as num?)?.toInt() ?? 0;
    return Semantics(
      selected: selected,
      button: true,
      label: name,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 78,
          child: Column(children: [
            AnimatedContainer(
              duration: Motion.fast,
              width: 70,
              height: 70,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: selected ? AppColors.gold : Colors.transparent, width: 3),
              ),
              child: ClipOval(child: ProPhoto(name: name, url: pro['avatar_url'], radius: 40)),
            ),
            const SizedBox(height: 6),
            Text(name.split(' ').first,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            Text(reviews > 0 ? '★ ${rating.toStringAsFixed(1)}' : 'New',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          ]),
        ),
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final List<String> options;
  final List<IconData> icons;
  final int selected;
  final ValueChanged<int> onChanged;
  const _Segment({required this.options, required this.icons, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: AppRadius.pill),
      child: Row(children: [
        for (var i = 0; i < options.length; i++)
          Expanded(
            child: Semantics(
              selected: i == selected,
              button: true,
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: Motion.fast,
                  height: 40,
                  decoration: BoxDecoration(
                    color: i == selected ? AppColors.card : Colors.transparent,
                    borderRadius: AppRadius.pill,
                    boxShadow: i == selected
                        ? const [BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2))]
                        : null,
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(icons[i], size: 17, color: i == selected ? AppColors.textPrimary : AppColors.textSecondary),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(options[i],
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: i == selected ? AppColors.textPrimary : AppColors.textSecondary)),
                    ),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

class _PayTile extends StatelessWidget {
  final PayMethod method;
  final String note;
  final bool selected;
  final VoidCallback onTap;
  const _PayTile({required this.method, required this.note, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final brand = payBrand(method.id);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: AppColors.card,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.mdAll,
          side: BorderSide(color: selected ? AppColors.gold : Colors.transparent, width: 2),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          child: SizedBox(
            height: 62,
            child: Stack(children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: brand.bg, borderRadius: BorderRadius.circular(10)),
                    child: Text(brand.mark,
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(method.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      Text(note,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                    ]),
                  ),
                ]),
              ),
              if (selected)
                Positioned(
                  top: 7,
                  right: 7,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(color: AppColors.gold, shape: BoxShape.circle),
                    child: const Icon(TablerIcons.check, size: 12, color: Color(0xFF17130E)),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _DashedLine extends StatelessWidget {
  final Color color;
  const _DashedLine({required this.color});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (_, c) => Row(children: [
          for (var i = 0; i < (c.maxWidth / 8).floor(); i++)
            Container(width: 4, height: 1, margin: const EdgeInsets.only(right: 4), color: color),
        ]),
      );
}

class _SelectCard extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final String title;
  final String? subtitle;
  final String? trailing;
  final Widget? leading;
  const _SelectCard({
    required this.selected,
    required this.onTap,
    required this.title,
    this.subtitle,
    this.trailing,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.primarySoft : AppColors.card,
      shape: RoundedRectangleBorder(
          borderRadius: AppRadius.mdAll,
          side: BorderSide(color: selected ? AppColors.gold : AppColors.border, width: selected ? 2 : 1)),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.mdAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            if (leading != null) ...[leading!, const SizedBox(width: 12)],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                if (subtitle != null) Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),
            if (trailing != null)
              Text(trailing!,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ]),
        ),
      ),
    );
  }
}

class _PackageUse extends StatelessWidget {
  final String name;
  final int left;
  final bool on;
  final ValueChanged<bool> onChanged;
  const _PackageUse({required this.name, required this.left, required this.on, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: on ? const Color(0xFF1F8A4C).withValues(alpha: 0.12) : AppColors.card,
      borderRadius: BorderRadius.circular(18),
      child: SwitchListTile.adaptive(
        value: on,
        onChanged: onChanged,
        activeTrackColor: const Color(0xFF1F8A4C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        secondary: const Icon(TablerIcons.calendar_repeat, color: Color(0xFF1F8A4C)),
        title: Text('Use $name', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        subtitle: Text('$left ${left == 1 ? 'visit' : 'visits'} left this month · \$0 for the service',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
      ),
    );
  }
}
