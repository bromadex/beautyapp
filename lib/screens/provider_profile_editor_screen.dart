import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';

class ProviderProfileEditorScreen extends StatefulWidget {
  const ProviderProfileEditorScreen({super.key});
  @override
  State<ProviderProfileEditorScreen> createState() =>
      _ProviderProfileEditorScreenState();
}

class _ProviderProfileEditorScreenState
    extends State<ProviderProfileEditorScreen> {
  final _formKey     = GlobalKey<FormState>();
  final _bioCtrl     = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _latCtrl     = TextEditingController();
  final _lngCtrl     = TextEditingController();
  bool _loading = false;
  bool _saving  = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await supabase
          .from('provider_profiles')
          .select()
          .eq('provider_id', supabase.auth.currentUser!.id)
          .single();
      _bioCtrl.text     = data['bio']     ?? '';
      _addressCtrl.text = data['address'] ?? '';
      _latCtrl.text     = data['latitude']?.toString()  ?? '';
      _lngCtrl.text     = data['longitude']?.toString() ?? '';
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final userId = supabase.auth.currentUser!.id;
    final payload = {
      'provider_id': userId,
      'bio':         _bioCtrl.text.trim(),
      'address':     _addressCtrl.text.trim(),
      'latitude':    double.tryParse(_latCtrl.text.trim()),
      'longitude':   double.tryParse(_lngCtrl.text.trim()),
    };

    try {
      // Upsert — creates or updates
      await supabase
          .from('provider_profiles')
          .upsert(payload, onConflict: 'provider_id');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile saved ✓'),
              backgroundColor: Colors.green),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _bioCtrl.dispose(); _addressCtrl.dispose();
    _latCtrl.dispose(); _lngCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Provider Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _bioCtrl,
                decoration: const InputDecoration(
                  labelText: 'Bio / About You',
                  hintText: 'e.g. Professional braider with 5 years experience...',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
                maxLines: 4,
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Please add a bio' : null,
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _addressCtrl,
                decoration: const InputDecoration(
                  labelText: 'Service Area / Address',
                  hintText: 'e.g. Borrowdale, Harare',
                  prefixIcon: Icon(Icons.location_on_outlined),
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Please add your address' : null,
              ),
              const SizedBox(height: 16),

              // Lat/Lng — manual for now, map picker in Stage 6
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _latCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Latitude',
                      hintText: '-17.8292',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _lngCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Longitude',
                      hintText: '31.0522',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              const Text(
                'Tip: Find your coordinates on Google Maps — right-click your location.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              const SizedBox(height: 32),

              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(height: 18, width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_rounded),
                label: Text(_saving ? 'Saving...' : 'Save Profile'),
                style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}