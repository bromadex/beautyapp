import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../supabase_client.dart';
import '../services/location_service.dart';
import '../utils/pay_methods.dart';
import '../theme.dart';
import '../widgets/slot_picker.dart';
import '../widgets/ui.dart';

/// Step-by-step booking: Service → When → Details → Review.
class BookingScreen extends StatefulWidget {
  final String providerId;
  final String serviceId;
  final String? packageId;
  const BookingScreen({
    super.key,
    required this.providerId,
    required this.serviceId,
    this.packageId,
  });
  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  static const _stepTitles = ['Service', 'When', 'Details', 'Review'];

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
      await _loadServiceExtras();
      if (mounted) setState(() => _loading = false);
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
    _time = null;
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

  String get _mode => (_service['location_mode'] ?? 'client') as String;
  bool get _studio => _mode == 'studio' || (_mode == 'either' && _atStudio);
  Map<String, dynamic>? get _cat => _service['service_categories'] as Map<String, dynamic>?;
  bool get _isMassage => _cat?['studio_only'] == true && _cat?['needs_certificate'] == true;
  int? get _minAge => (_cat?['min_age'] as num?)?.toInt();
  bool get _needsAck => _isMassage || _minAge != null;
  String get _studioArea {
    final a = (_providerProfile?['address'] ?? _provider?['location'] ?? '').toString();
    return a.isEmpty ? 'their studio' : a.split(',').last.trim();
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
  double get _total => math.max(0, _basePrice - _discount - _loyaltyDiscount) + _addonsTotal + _travelFee;
  List<PayMethod> get _methods {
    final m = payMethodsOf(_providerProfile);
    return m.isEmpty ? const [PayMethod('cash', 'Cash', TablerIcons.cash)] : m;
  }

  bool get _takesTransfers => _methods.any((m) => m.isTransfer);

  // Matches the server: no deposit if the pro has nowhere to receive it.
  int get _depositPercent =>
      _takesTransfers ? (_providerProfile?['deposit_percent'] as num?)?.toInt() ?? 0 : 0;
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
      final pos = await LocationService().getCurrentPosition();
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
          _toast('Please enter your name');
          return false;
        }
        if (_phoneCtrl.text.trim().replaceAll(RegExp(r'\D'), '').length < 9) {
          _toast('Please enter a phone number the pro can reach you on');
          return false;
        }
        if (!_studio && _addressCtrl.text.trim().isEmpty) {
          _toast('Please enter where the pro should come');
          return false;
        }
      case 3:
        if (_needsAck && !_ack) {
          _toast('Please tick the box to accept the rules for this service');
          return false;
        }
    }
    return true;
  }

  void _next() {
    if (!_validateStep()) return;
    if (_step < 3) {
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
            'address': _studio ? 'At the pro\'s studio' : _addressCtrl.text.trim(),
            'at_studio': _studio,
            'client_ack': _ack,
            'status': 'pending',
            'total_price': _total,
            'promo_code': _promo?['code'],
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
      await _showDone(bookingId, inserted['ref'] ?? '', deposit);
    } on PostgrestException catch (e) {
      if (mounted) _toast(e.message, error: true);
    } catch (e) {
      if (mounted) _toast('Something went wrong: $e', error: true);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _showDone(String bookingId, String ref, double deposit) async {
    await showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      showDragHandle: false,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: const Icon(TablerIcons.check, color: AppColors.success, size: 40),
          ),
          const SizedBox(height: 16),
          Text('Request sent!', style: Theme.of(ctx).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            '${_provider?['full_name'] ?? 'Your pro'} will confirm shortly. '
            'Your reference is $ref.'
            '${deposit > 0 ? '\n\nSend your ${_money(deposit)} deposit to secure the booking.' : ''}',
            textAlign: TextAlign.center,
            style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
          ),
          if (_isGuest) ...[
            const SizedBox(height: 16),
            const SoftBanner(
              icon: TablerIcons.bookmark_plus,
              color: AppColors.primary,
              title: 'Keep your bookings safe',
              message: 'Create a free account from Settings so you can find this booking on any phone.',
            ),
          ],
          const SizedBox(height: 24),
          if (deposit > 0) ...[
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  context.go('/booking/$bookingId');
                  context.push('/pay/$bookingId');
                },
                child: Text('Pay ${_money(deposit)} deposit'),
              ),
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            child: deposit > 0
                ? OutlinedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      context.go('/booking/$bookingId');
                    },
                    child: const Text('Later'),
                  )
                : FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      context.go('/booking/$bookingId');
                    },
                    child: const Text('View booking'),
                  ),
          ),
        ]),
      ),
    );
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
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

    final lastStep = _step == 3;
    final buttonLabel = !lastStep
        ? 'Continue'
        : 'Confirm booking';

    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _step--);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(TablerIcons.arrow_left),
            onPressed: () {
              if (_step > 0) {
                setState(() => _step--);
              } else if (context.canPop()) {
                context.pop();
              } else {
                context.go('/provider/${widget.providerId}');
              }
            },
          ),
          title: Text(_stepTitles[_step]),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text('${_step + 1} / ${_stepTitles.length}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
              ),
            ),
          ],
        ),
        body: Column(children: [
          _StepBar(step: _step, titles: _stepTitles),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    switch (_step) {
                      0 => _serviceStep(),
                      1 => _whenStep(),
                      2 => _detailsStep(),
                      _ => _reviewStep(),
                    },
                  ],
                ),
              ),
            ),
          ),
          _BottomBar(
            total: _money(_total),
            subtitle: _day != null && _time != null
                ? _whenLabel()
                : '${_durationLabel(_totalMinutes)}${_deposit > 0 ? ' · ${_money(_deposit)} deposit' : ''}',
            label: buttonLabel,
            busy: _submitting,
            onPressed: _submitting ? null : _next,
          ),
        ]),
      ),
    );
  }

  Widget _serviceStep() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('What would you like?', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 16),
      ..._services.map((s) {
        final sel = s['id'] == _serviceId;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _SelectCard(
            selected: sel,
            onTap: () => _selectService(s['id']),
            leading: CategoryBadge(name: s['service_categories']?['name'], size: 44),
            title: s['service_name'] ?? 'Service',
            subtitle: '${s['duration_minutes'] ?? 60} min',
            trailing: _money(((s['price'] as num?) ?? 0).toDouble()),
          ),
        );
      }),
      if (_tiers.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('Choose an option', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        ..._tiers.map((t) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _SelectCard(
                selected: _tierId == t['id'],
                onTap: () => setState(() {
                  _tierId = t['id'];
                  _time = null;
                }),
                title: t['name'] ?? '',
                subtitle: '${t['duration_minutes']} min',
                trailing: _money((t['price'] as num).toDouble()),
                radio: true,
              ),
            )),
      ],
      if (_addons.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('Add extras', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        ..._addons.map((a) {
          final on = _addonIds.contains(a['id']);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _SelectCard(
              selected: on,
              onTap: () => setState(() {
                on ? _addonIds.remove(a['id']) : _addonIds.add(a['id']);
                _time = null;
              }),
              title: a['name'] ?? '',
              subtitle: (a['duration_minutes'] ?? 0) > 0 ? '+${a['duration_minutes']} min' : null,
              trailing: '+${_money(((a['price'] as num?) ?? 0).toDouble())}',
              checkbox: true,
            ),
          );
        }),
      ],
    ]);
  }

  String _durationLabel(int mins) =>
      mins >= 60 ? '${mins ~/ 60} h${mins % 60 > 0 ? ' ${mins % 60} min' : ''}' : '$mins min';

  String _whenLabel() {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final d = _day!;
    return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}, $_time';
  }

  Widget _whenStep() {
    final notice = (_providerProfile?['min_notice_hours'] as num?)?.toInt() ?? 2;
    final addonNames = _addons.where((a) => _addonIds.contains(a['id'])).map((a) => a['name']).join(', ');
    final tierName = (_tier != null && _tier!.isNotEmpty) ? ' · ${_tier!['name']}' : '';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: AppRadius.mdAll,
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          const Icon(TablerIcons.clock, color: AppColors.primary, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text.rich(
                TextSpan(children: [
                  TextSpan(
                      text: '${_service['service_name']}$tierName',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  if (addonNames.isNotEmpty) TextSpan(text: ' + $addonNames'),
                ]),
                style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 2),
              Text('${_durationLabel(_totalMinutes)} with ${_provider?['full_name'] ?? 'your pro'}',
                  style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 6),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Text('Only free times are shown. Book at least $notice h ahead.',
            style: Theme.of(context).textTheme.bodySmall),
      ),
      const SizedBox(height: 14),
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
    ]);
  }

  Widget _detailsStep() {
    final hasTravel = ((_providerProfile?['travel_fee_per_km'] as num?) ?? 0) > 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Your details', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 16),
      TextField(
        controller: _nameCtrl,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(labelText: 'Your name', prefixIcon: Icon(TablerIcons.user)),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: _phoneCtrl,
        keyboardType: TextInputType.phone,
        decoration: const InputDecoration(
          labelText: 'Phone (WhatsApp)',
          hintText: '+263 7X XXX XXXX',
          prefixIcon: Icon(TablerIcons.phone),
        ),
      ),
      const SizedBox(height: 16),
      if (_mode == 'either') ...[
        const Text('Where?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: false, label: Text('At my place'), icon: Icon(TablerIcons.home, size: 18)),
            ButtonSegment(value: true, label: Text('At the studio'), icon: Icon(TablerIcons.building_store, size: 18)),
          ],
          selected: {_atStudio},
          onSelectionChanged: (v) => setState(() => _atStudio = v.first),
        ),
        const SizedBox(height: 12),
      ],
      if (_studio)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: AppRadius.mdAll),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(TablerIcons.building_store, color: AppColors.primary, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'At ${(_provider?['full_name'] ?? 'the pro').toString().split(' ').first}\'s studio in $_studioArea. '
                'You\'ll see the exact address once your booking is confirmed.',
                style: const TextStyle(fontSize: 14, height: 1.4),
              ),
            ),
          ]),
        )
      else
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
      if (hasTravel && !_studio)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _locating ? null : _useMyLocation,
            icon: _locating
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(TablerIcons.current_location, size: 18),
            label: Text(_lat == null
                ? 'Use my location to work out travel fee'
                : _travelFee > 0
                    ? 'Travel fee: ${_money(_travelFee)}'
                    : 'You\'re within the free travel area'),
          ),
        ),
      const SizedBox(height: 12),
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
      const SizedBox(height: 24),
      Text('How will you pay?', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 10),
      LayoutBuilder(builder: (context, box) {
        final perRow = _methods.length >= 3 ? 3 : _methods.length;
        final w = (box.maxWidth - 8 * (perRow - 1)) / perRow;
        return Wrap(spacing: 8, runSpacing: 8, children: [
          for (final m in _methods)
            SizedBox(
              width: w,
              child: _SelectCard(
                selected: _payment == m.id,
                onTap: () => setState(() => _payment = m.id),
                title: m.label,
                icon: m.icon,
                compact: true,
              ),
            ),
        ]);
      }),
      const SizedBox(height: 10),
      Text(
        _depositPercent > 0
            ? 'This pro asks for a $_depositPercent% deposit (${_money(_deposit)}). After you book, send it to them '
                'directly and tap "I\'ve paid". The rest is paid ${_payment == 'cash' ? 'in cash' : 'by ${payMethodLabel(_payment)}'} on the day.'
            : _payment == 'cash'
                ? 'Pay the pro in cash on the day.'
                : 'You pay the pro directly. BeauTap never holds your money.',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      const SizedBox(height: 24),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: TextField(
            controller: _promoCtrl,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: 'Promo code',
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
    ]);
  }

  Widget _reviewStep() {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final d = _day!;
    final h = int.parse(_time!.substring(0, 2));
    final timeLabel = '${h % 12 == 0 ? 12 : h % 12}:${_time!.substring(3)} ${h >= 12 ? 'pm' : 'am'}';
    Widget row(String l, String r, {bool bold = false, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Expanded(
                child: Text(l,
                    style: TextStyle(
                        fontSize: bold ? 16 : 14,
                        fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
                        color: bold ? AppColors.textPrimary : AppColors.textSecondary))),
            Text(r,
                style: TextStyle(
                    fontSize: bold ? 18 : 14,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                    color: color ?? AppColors.textPrimary)),
          ]),
        );

    final tierName = (_tier != null && _tier!.isNotEmpty) ? ' · ${_tier!['name']}' : '';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Check and confirm', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              PersonAvatar(name: _provider?['full_name'] ?? '', url: _provider?['avatar_url'], size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${_service['service_name'] ?? ''}$tierName', style: Theme.of(context).textTheme.titleMedium),
                  Text('with ${_provider?['full_name'] ?? ''}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            _InfoLine(
                icon: TablerIcons.calendar_event,
                text: '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]} · $timeLabel ($_totalMinutes min)'),
            _InfoLine(
                icon: _studio ? TablerIcons.building_store : TablerIcons.map_pin,
                text: _studio ? 'At the pro\'s studio, $_studioArea' : _addressCtrl.text.trim()),
            _InfoLine(
                icon: TablerIcons.cash,
                text: _payment == 'cash' ? 'Pay cash' : 'Pay by ${payMethodLabel(_payment)}'),
          ]),
        ),
      ),
      const SizedBox(height: 12),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            row('${_service['service_name'] ?? 'Service'}$tierName', _money(_basePrice)),
            ..._addons
                .where((a) => _addonIds.contains(a['id']))
                .map((a) => row(a['name'] ?? 'Extra', '+${_money(((a['price'] as num?) ?? 0).toDouble())}')),
            if (_travelFee > 0) row('Travel', '+${_money(_travelFee)}'),
            if (_discount > 0) row('Promo ${_promo?['code']}', '-${_money(_discount)}', color: AppColors.success),
            if (_loyaltyDiscount > 0)
              row('Loyalty reward (${_loyalty!['percent']}%)', '-${_money(_loyaltyDiscount)}', color: AppColors.success),
            const Divider(height: 20),
            row('Total', _money(_total), bold: true),
            if (_deposit > 0) row('Deposit to send the pro', _money(_deposit), color: AppColors.primary),
          ]),
        ),
      ),
      if (_service['patch_test'] == true) ...[
        const SizedBox(height: 12),
        const SoftBanner(
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
              style: const TextStyle(fontSize: 14, height: 1.4, color: AppColors.textPrimary),
            ),
          ),
        ),
      ],
      if (_policy != null) ...[
        const SizedBox(height: 12),
        SoftBanner(
          icon: TablerIcons.info_circle,
          color: AppColors.info,
          title: 'Free cancellation up to ${_policy!['free_cancel_hours']}h before',
          message: 'After that, a ${_policy!['late_cancel_fee_percent']}% late-cancellation fee applies.',
        ),
      ],
    ]);
  }
}

class _StepBar extends StatelessWidget {
  final int step;
  final List<String> titles;
  const _StepBar({required this.step, required this.titles});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Row(children: [
        for (var i = 0; i < titles.length; i++) ...[
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                height: 4,
                decoration: BoxDecoration(
                  color: i <= step ? AppColors.primary : const Color(0xFFDDE2DE),
                  borderRadius: AppRadius.pill,
                ),
              ),
              const SizedBox(height: 6),
              Text(titles[i],
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: i == step ? FontWeight.w800 : FontWeight.w600,
                      color: i == step ? AppColors.textPrimary : AppColors.textSecondary)),
            ]),
          ),
          if (i < titles.length - 1) const SizedBox(width: 6),
        ],
      ]),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final String total;
  final String subtitle;
  final String label;
  final bool busy;
  final VoidCallback? onPressed;
  const _BottomBar(
      {required this.total, required this.subtitle, required this.label, required this.busy, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Row(children: [
            Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              Text(total,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            ]),
            const SizedBox(width: 16),
            Expanded(
              child: FilledButton(
                onPressed: onPressed,
                child: busy
                    ? const SizedBox(
                        width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(label, overflow: TextOverflow.ellipsis),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _SelectCard extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final String title;
  final String? subtitle;
  final String? trailing;
  final Widget? leading;
  final IconData? icon;
  final bool radio;
  final bool checkbox;
  final bool compact;
  const _SelectCard({
    required this.selected,
    required this.onTap,
    required this.title,
    this.subtitle,
    this.trailing,
    this.leading,
    this.icon,
    this.radio = false,
    this.checkbox = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final border = selected ? AppColors.primary : AppColors.border;
    return Material(
      color: selected ? AppColors.primarySoft : Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: AppRadius.mdAll, side: BorderSide(color: border, width: selected ? 1.6 : 1)),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.mdAll,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 14, vertical: compact ? 14 : 12),
          child: compact
              ? Column(children: [
                  Icon(icon, color: selected ? AppColors.primary : AppColors.textSecondary),
                  const SizedBox(height: 6),
                  Text(title,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: selected ? AppColors.primary : AppColors.textPrimary)),
                ])
              : Row(children: [
                  if (radio || checkbox) ...[
                    Icon(
                      checkbox
                          ? (selected ? TablerIcons.square_check : TablerIcons.square)
                          : (selected ? TablerIcons.circle_dot : TablerIcons.circle),
                      color: selected ? AppColors.primary : AppColors.textTertiary,
                    ),
                    const SizedBox(width: 12),
                  ],
                  if (leading != null) ...[leading!, const SizedBox(width: 12)],
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: Theme.of(context).textTheme.titleSmall),
                      if (subtitle != null) Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
                    ]),
                  ),
                  if (trailing != null)
                    Text(trailing!,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: selected ? AppColors.primary : AppColors.textPrimary)),
                ]),
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoLine({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: AppColors.textTertiary),
        const SizedBox(width: 10),
        Expanded(
            child: Text(text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary))),
      ]),
    );
  }
}
