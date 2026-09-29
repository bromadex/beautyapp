import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../services/location_service.dart';
import '../supabase_client.dart';
import '../theme.dart';
import '../widgets/ui.dart';

/// Where a pro works. City and area are required before clients can find or
/// book them; the street address is only shown once a booking is confirmed.
class ProviderLocationScreen extends StatefulWidget {
  const ProviderLocationScreen({super.key});

  @override
  State<ProviderLocationScreen> createState() => _ProviderLocationScreenState();
}

class _ProviderLocationScreenState extends State<ProviderLocationScreen> {
  bool _loading = true;
  bool _saving = false;
  bool _locating = false;
  List<Map<String, dynamic>> _cities = [];
  String? _cityId;
  String? _savedCityId;
  final _areaCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  double? _lat, _lng;
  bool _pinFromPhone = false;
  int _upcomingAtPlace = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _areaCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final uid = supabase.auth.currentUser!.id;
      final res = await Future.wait<dynamic>([
        supabase.from('cities').select('id, name').eq('is_active', true).order('name'),
        supabase
            .from('provider_profiles')
            .select('city_id, area, address, latitude, longitude')
            .eq('provider_id', uid)
            .maybeSingle(),
        supabase.rpc('my_upcoming_studio_bookings'),
      ]);
      final pp = res[1] as Map<String, dynamic>?;
      if (!mounted) return;
      setState(() {
        _cities = List<Map<String, dynamic>>.from(res[0] as List);
        _cityId = pp?['city_id'];
        _savedCityId = _cityId;
        _areaCtrl.text = pp?['area'] ?? '';
        _addressCtrl.text = pp?['address'] ?? '';
        _lat = (pp?['latitude'] as num?)?.toDouble();
        _lng = (pp?['longitude'] as num?)?.toDouble();
        _upcomingAtPlace = (res[2] as num?)?.toInt() ?? 0;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String m, {bool error = false}) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m), backgroundColor: error ? AppColors.error : null));

  Future<void> _usePhone() async {
    setState(() => _locating = true);
    try {
      final pos = await LocationService().getCurrentPosition(
        context: context,
        reason: 'So clients near you can find you, and travel fees are worked out from where you are.',
      );
      if (pos != null && mounted) {
        setState(() {
          _lat = pos.latitude;
          _lng = pos.longitude;
          _pinFromPhone = true;
        });
        _toast('Pin set to where you are now');
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    if (_cityId == null) {
      _toast('Choose your city', error: true);
      return;
    }
    if (_areaCtrl.text.trim().length < 2) {
      _toast('Add your area or suburb, e.g. Avondale', error: true);
      return;
    }
    final moving = _savedCityId != null && _savedCityId != _cityId;
    if ((moving || _addressCtrl.text.trim().isNotEmpty) && _upcomingAtPlace > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('You have upcoming bookings'),
          content: Text(
              '$_upcomingAtPlace client${_upcomingAtPlace == 1 ? ' is' : 's are'} booked to come to your place. '
              'Their bookings keep the old address, so message them about the new one.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save anyway')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _saving = true);
    try {
      await supabase.from('provider_profiles').update({
        'city_id': _cityId,
        'area': _areaCtrl.text.trim(),
        'address': _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
        // A moved city without a new phone pin resets to the city centre (done in the database).
        if (_pinFromPhone) 'latitude': _lat,
        if (_pinFromPhone) 'longitude': _lng,
      }).eq('provider_id', supabase.auth.currentUser!.id);
      if (!mounted) return;
      _toast('Saved. Clients can now find you in ${_cities.firstWhere((c) => c['id'] == _cityId)['name']}.');
      if (context.canPop()) {
        context.pop(true);
      } else {
        context.go('/provider/home');
      }
    } on PostgrestException catch (e) {
      _toast(e.message, error: true);
    } catch (_) {
      _toast('Could not save. Check your connection.', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Where you work')),
      body: _loading
          ? const LoadingPlaceholder(kind: PlaceholderKind.detail)
          : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
              Text('Clients see your city and area, and only find and book you once both are set. '
                  'Moved? Change it here any time.',
                  style: TextStyle(color: AppColors.textSecondary, height: 1.4)),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _cityId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'City or town', prefixIcon: Icon(TablerIcons.building)),
                items: [
                  for (final c in _cities) DropdownMenuItem(value: c['id'] as String, child: Text(c['name'])),
                ],
                onChanged: (v) => setState(() {
                  _cityId = v;
                  if (v != _savedCityId) _pinFromPhone = false;
                }),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _areaCtrl,
                textCapitalization: TextCapitalization.words,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'Area or suburb',
                  hintText: 'e.g. Avondale',
                  prefixIcon: Icon(TablerIcons.map_pin),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _addressCtrl,
                textCapitalization: TextCapitalization.words,
                maxLines: 2,
                minLines: 1,
                decoration: const InputDecoration(
                  labelText: 'Street address (optional)',
                  hintText: 'e.g. 12 King George Rd',
                  prefixIcon: Icon(TablerIcons.home),
                ),
              ),
              const SizedBox(height: 4),
              Text('Only shown to clients coming to your place, after you confirm their booking.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: AppRadius.mdAll,
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Icon(_lat != null ? TablerIcons.map_pin_check : TablerIcons.map_pin_question,
                        color: _lat != null ? AppColors.success : AppColors.textSecondary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _pinFromPhone
                            ? 'Map pin set to where you are now'
                            : _lat != null
                                ? 'Map pin set'
                                : 'No map pin yet. We\'ll use your city centre.',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Text('A pin makes "near me" results and travel fees accurate. Set it while you\'re at your place.',
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _locating ? null : _usePhone,
                    icon: const Icon(TablerIcons.current_location, size: 18),
                    label: Text(_locating ? 'Finding you…' : 'Use my current location'),
                  ),
                ]),
              ),
            ]),
      bottomNavigationBar: _loading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving…' : 'Save location'),
                ),
              ),
            ),
    );
  }
}
