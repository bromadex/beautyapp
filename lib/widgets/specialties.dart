import 'package:flutter/material.dart';

import '../supabase_client.dart';
import '../theme.dart';

/// What a pro specialises in (service categories). Saved on the pro's
/// profile and shown on their public page, even before they add services.
class Specialties {
  static const max = 8;
  static List<Map<String, dynamic>>? _cache;

  static Future<List<Map<String, dynamic>>> categories() async {
    if (_cache != null) return _cache!;
    final data = await supabase.from('service_categories').select('id, name').order('sort_order');
    return _cache = List<Map<String, dynamic>>.from(data);
  }

  /// Saved on its own so a problem here never stops sign-up or a profile save.
  static Future<bool> save(String providerId, Set<String> ids) async {
    try {
      await supabase.from('provider_profiles').update({'specialties': ids.toList()}).eq('provider_id', providerId);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Set<String> from(dynamic v) => {for (final x in (v as List? ?? const [])) x.toString()};
}

class SpecialtyPicker extends StatefulWidget {
  final Set<String> value;
  final ValueChanged<Set<String>> onChanged;
  const SpecialtyPicker({super.key, required this.value, required this.onChanged});

  @override
  State<SpecialtyPicker> createState() => _SpecialtyPickerState();
}

class _SpecialtyPickerState extends State<SpecialtyPicker> {
  List<Map<String, dynamic>> _cats = [];

  @override
  void initState() {
    super.initState();
    Specialties.categories().then((c) {
      if (mounted) setState(() => _cats = c);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    if (_cats.isEmpty) return const SizedBox(height: 40);
    final full = widget.value.length >= Specialties.max;
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final c in _cats)
        Builder(builder: (_) {
          final id = c['id'].toString();
          final on = widget.value.contains(id);
          return FilterChip(
            label: Text(c['name'] ?? ''),
            selected: on,
            onSelected: (!on && full)
                ? null
                : (_) {
                    final next = {...widget.value};
                    on ? next.remove(id) : next.add(id);
                    widget.onChanged(next);
                  },
            selectedColor: AppColors.primary.withValues(alpha: 0.12),
            checkmarkColor: AppColors.primary,
            labelStyle: TextStyle(
              color: on ? AppColors.primary : AppColors.textPrimary,
              fontWeight: on ? FontWeight.w600 : FontWeight.w400,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.mdAll,
              side: BorderSide(color: on ? AppColors.primary.withValues(alpha: 0.3) : AppColors.borderStrong),
            ),
          );
        }),
    ]);
  }
}

/// "Specialises in" chips on a pro's public profile.
class SpecialtyChips extends StatefulWidget {
  final Set<String> ids;
  const SpecialtyChips({super.key, required this.ids});

  @override
  State<SpecialtyChips> createState() => _SpecialtyChipsState();
}

class _SpecialtyChipsState extends State<SpecialtyChips> {
  List<String> _names = [];

  @override
  void initState() {
    super.initState();
    Specialties.categories().then((c) {
      if (!mounted) return;
      setState(() => _names = [for (final x in c) if (widget.ids.contains(x['id'].toString())) x['name'] as String]);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    if (_names.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Specialises in', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final n in _names)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(20)),
              child: Text(n, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary)),
            ),
        ]),
      ]),
    );
  }
}
