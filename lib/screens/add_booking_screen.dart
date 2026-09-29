import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../supabase_client.dart';
import '../theme.dart';
import '../utils/booking_helpers.dart';
import '../widgets/ui.dart';

/// Stylist logs a booking taken by phone, WhatsApp or a walk-in, so the calendar is complete.
class AddBookingScreen extends StatefulWidget {
  final DateTime? initialDate;
  final int? initialHour;
  final String? clientKey;
  const AddBookingScreen({super.key, this.initialDate, this.initialHour, this.clientKey});

  @override
  State<AddBookingScreen> createState() => _AddBookingScreenState();
}

class _AddBookingScreenState extends State<AddBookingScreen> {
  bool _loading = true;
  bool _saving = false;
  List<Map<String, dynamic>> _services = [];
  List<Map<String, dynamic>> _clients = [];

  Map<String, dynamic>? _client; // an existing client from my_clients()
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  String? _serviceId;
  String? _tierId;
  late DateTime _date;
  TimeOfDay _time = const TimeOfDay(hour: 10, minute: 0);
  bool _paid = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = widget.initialDate ?? DateTime(now.year, now.month, now.day);
    if (widget.initialHour != null) {
      _time = TimeOfDay(hour: widget.initialHour!.clamp(0, 23), minute: 0);
    } else if (widget.initialDate == null || _isToday) {
      // Next half hour today
      final m = now.hour * 60 + now.minute + 30;
      _time = TimeOfDay(hour: (m ~/ 60).clamp(0, 23), minute: m % 60 < 30 ? 0 : 30);
    }
    _load();
  }

  bool get _isToday {
    final n = DateTime.now();
    return _date.year == n.year && _date.month == n.month && _date.day == n.day;
  }

  Future<void> _load() async {
    final uid = supabase.auth.currentUser!.id;
    try {
      final results = await Future.wait<dynamic>([
        supabase
            .from('services')
            .select('id, service_name, price, duration_minutes, service_tiers(id, name, price, duration_minutes, is_active)')
            .eq('provider_id', uid)
            .eq('is_active', true)
            .order('service_name', ascending: true),
        supabase.rpc('my_clients'),
      ]);
      _services = List<Map<String, dynamic>>.from(results[0] as List);
      _clients = List<Map<String, dynamic>>.from(results[1] as List);
      if (widget.clientKey != null) {
        _client = _clients.where((c) => c['client_key'] == widget.clientKey).firstOrNull;
      }
      if (_services.isNotEmpty) _pickService(_services.first['id']);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Map<String, dynamic>? get _service => _services.where((s) => s['id'] == _serviceId).firstOrNull;

  List<Map<String, dynamic>> get _tiers =>
      ((_service?['service_tiers'] as List?) ?? []).cast<Map<String, dynamic>>().where((t) => t['is_active'] == true).toList();

  void _pickService(String id) {
    _serviceId = id;
    _tierId = null;
    _priceCtrl.text = '${_service?['price'] ?? ''}';
  }

  DateTime get _when => DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);

  Future<void> _save() async {
    if (_client == null && _nameCtrl.text.trim().length < 2) {
      _snack('Enter the client\'s name');
      return;
    }
    if (_serviceId == null) {
      _snack('Add a service first');
      return;
    }
    setState(() => _saving = true);
    try {
      final id = await supabase.rpc('create_manual_booking', params: {
        'p_service': _serviceId,
        'p_time': _when.toUtc().toIso8601String(),
        'p_name': _client?['name'] ?? _nameCtrl.text.trim(),
        'p_phone': _client == null ? _phoneCtrl.text.trim() : _client!['phone'],
        'p_tier': _tierId,
        'p_price': double.tryParse(_priceCtrl.text.trim()),
        'p_note': _noteCtrl.text.trim(),
        'p_client': _client?['client_id'],
        'p_paid': _paid && _when.isBefore(DateTime.now()),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_when.isBefore(DateTime.now()) ? 'Walk-in saved' : 'Booking added to your calendar'),
        backgroundColor: AppColors.success,
      ));
      if (context.canPop()) {
        context.pushReplacement('/booking/$id');
      } else {
        context.go('/provider/calendar');
      }
    } on PostgrestException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String m) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _chooseClient() async {
    final picked = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ClientPicker(clients: _clients),
    );
    if (picked != null) setState(() => _client = picked);
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl, _phoneCtrl, _priceCtrl, _noteCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final past = _when.isBefore(DateTime.now());
    return Scaffold(
      appBar: AppBar(title: const Text('Add booking')),
      body: _loading
          ? const LoadingPlaceholder(kind: PlaceholderKind.detail)
          : _services.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text('Add a service first, then you can log bookings against it.',
                          textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      FilledButton(onPressed: () => context.push('/provider/services'), child: const Text('Add a service')),
                    ]),
                  ),
                )
              : ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 120), children: [
                  Text('For bookings you got by phone, WhatsApp or walk-in. They block the time in your calendar '
                      'and don\'t count towards your plan.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
                  const SizedBox(height: 20),
                  _label('Client'),
                  if (_client != null)
                    _Tile(
                      icon: TablerIcons.user,
                      title: _client!['name'],
                      subtitle: [
                        if (_client!['phone'] != null) _client!['phone'],
                        '${_client!['visits']} visits',
                      ].join(' · '),
                      trailing: TextButton(onPressed: () => setState(() => _client = null), child: const Text('Change')),
                    )
                  else ...[
                    TextField(
                      controller: _nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Name', prefixIcon: Icon(TablerIcons.user)),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone (optional)',
                        hintText: '077 123 4567',
                        prefixIcon: Icon(TablerIcons.phone),
                      ),
                    ),
                    if (_clients.isNotEmpty)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _chooseClient,
                          icon: const Icon(TablerIcons.users, size: 18),
                          label: const Text('Pick an existing client'),
                        ),
                      ),
                  ],
                  const SizedBox(height: 16),
                  _label('Service'),
                  DropdownButtonFormField<String>(
                    initialValue: _serviceId,
                    isExpanded: true,
                    items: [
                      for (final s in _services)
                        DropdownMenuItem(value: s['id'] as String, child: Text(s['service_name'] ?? 'Service')),
                    ],
                    onChanged: (v) => setState(() => _pickService(v!)),
                  ),
                  if (_tiers.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final t in _tiers)
                        ChoiceChip(
                          label: Text('${t['name']} · ${money(t['price'] as num)}'),
                          selected: _tierId == t['id'],
                          onSelected: (on) => setState(() {
                            _tierId = on ? t['id'] : null;
                            _priceCtrl.text = '${on ? t['price'] : _service?['price'] ?? ''}';
                          }),
                        ),
                    ]),
                  ],
                  const SizedBox(height: 16),
                  _label('When'),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: _date,
                            firstDate: DateTime.now().subtract(const Duration(days: 60)),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (d != null) setState(() => _date = d);
                        },
                        icon: const Icon(TablerIcons.calendar, size: 18),
                        label: Text(_isToday ? 'Today' : MaterialLocalizations.of(context).formatMediumDate(_date)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final t = await showTimePicker(context: context, initialTime: _time);
                          if (t != null) setState(() => _time = t);
                        },
                        icon: const Icon(TablerIcons.clock, size: 18),
                        label: Text(_time.format(context)),
                      ),
                    ),
                  ]),
                  if (past)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('This time has passed, so it will be saved as a completed walk-in.',
                          style: TextStyle(fontSize: 12.5, color: AppColors.textTertiary)),
                    ),
                  const SizedBox(height: 16),
                  _label('Price'),
                  TextField(
                    controller: _priceCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(prefixText: '\$ ', hintText: 'What the client pays'),
                  ),
                  if (past)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Already paid'),
                      value: _paid,
                      onChanged: (v) => setState(() => _paid = v),
                    ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _noteCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Note (optional)', hintText: 'e.g. Bring own hair'),
                  ),
                ]),
      bottomNavigationBar: _services.isEmpty || _loading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving…' : past ? 'Save walk-in' : 'Add to calendar'),
                ),
              ),
            ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: Theme.of(context).textTheme.titleSmall),
      );
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? trailing;
  const _Tile({required this.icon, required this.title, required this.subtitle, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        Icon(icon, color: AppColors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(subtitle, style: TextStyle(fontSize: 12.5, color: AppColors.textTertiary)),
          ]),
        ),
        ?trailing,
      ]),
    );
  }
}

class _ClientPicker extends StatefulWidget {
  final List<Map<String, dynamic>> clients;
  const _ClientPicker({required this.clients});
  @override
  State<_ClientPicker> createState() => _ClientPickerState();
}

class _ClientPickerState extends State<_ClientPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final list = widget.clients
        .where((c) =>
            _q.isEmpty ||
            (c['name'] ?? '').toString().toLowerCase().contains(_q) ||
            (c['phone'] ?? '').toString().contains(_q))
        .toList();
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom),
        child: Column(children: [
          TextField(
            autofocus: true,
            decoration: const InputDecoration(prefixIcon: Icon(TablerIcons.search), hintText: 'Search name or phone'),
            onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: list.length,
              itemBuilder: (_, i) {
                final c = list[i];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(c['name'] ?? 'Client'),
                  subtitle: Text([if (c['phone'] != null) c['phone'], '${c['visits']} visits'].join(' · ')),
                  onTap: () => Navigator.pop(context, c),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
