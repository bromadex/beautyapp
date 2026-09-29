import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../theme.dart';

class CreateServiceRequestScreen extends StatefulWidget {
  const CreateServiceRequestScreen({super.key});

  @override
  State<CreateServiceRequestScreen> createState() =>
      _CreateServiceRequestScreenState();
}

class _CreateServiceRequestScreenState
    extends State<CreateServiceRequestScreen> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _budgetMinCtrl = TextEditingController();
  final _budgetMaxCtrl = TextEditingController();

  DateTime? _preferredDate;
  TimeOfDay? _preferredTime;
  String? _selectedCategoryId;
  List<Map<String, dynamic>> _categories = [];
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final cats = await supabase
          .from('service_categories')
          .select()
          .order('name');
      if (mounted) {
        setState(() {
          _categories = List<Map<String, dynamic>>.from(cats);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a title')),
      );
      return;
    }
    if (_locationCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your location')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final uid = supabase.auth.currentUser!.id;
      await supabase.from('service_requests').insert({
        'client_id': uid,
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        'category_id': _selectedCategoryId,
        'location': _locationCtrl.text.trim(),
        'budget_min': double.tryParse(_budgetMinCtrl.text),
        'budget_max': double.tryParse(_budgetMaxCtrl.text),
        'preferred_date': _preferredDate?.toIso8601String().split('T')[0],
        'preferred_time': _preferredTime != null
            ? '${_preferredTime!.hour.toString().padLeft(2, '0')}:${_preferredTime!.minute.toString().padLeft(2, '0')}'
            : null,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Request posted! Providers will see it soon.'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _locationCtrl.dispose();
    _budgetMinCtrl.dispose();
    _budgetMaxCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Post a Request')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: AppSpacing.screenPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('What service do you need?',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _titleCtrl,
                    decoration: InputDecoration(
                      hintText: 'e.g. Braids for wedding',
                      border: OutlineInputBorder(borderRadius: AppRadius.mdAll),
                    ),
                  ),

                  const SizedBox(height: AppSpacing.xxl),
                  Text('Category',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: _categories.map((cat) {
                      final selected = _selectedCategoryId == cat['id'];
                      return ChoiceChip(
                        label: Text(
                            '${cat['name'] ?? ''}'),
                        selected: selected,
                        onSelected: (_) => setState(
                            () => _selectedCategoryId = cat['id']),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: AppSpacing.xxl),
                  Text('Details (optional)',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _descCtrl,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Describe what you need...',
                      border: OutlineInputBorder(borderRadius: AppRadius.mdAll),
                    ),
                  ),

                  const SizedBox(height: AppSpacing.xxl),
                  Text('Your Location',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _locationCtrl,
                    decoration: InputDecoration(
                      hintText: 'e.g. Borrowdale, Harare',
                      prefixIcon: const Icon(TablerIcons.map_pin),
                      border: OutlineInputBorder(borderRadius: AppRadius.mdAll),
                    ),
                  ),

                  const SizedBox(height: AppSpacing.xxl),
                  Text('Budget Range (optional)',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.sm),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _budgetMinCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: 'Min \$',
                          border: OutlineInputBorder(
                              borderRadius: AppRadius.mdAll),
                        ),
                      ),
                    ),
                    const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                      child: Text('to'),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _budgetMaxCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: 'Max \$',
                          border: OutlineInputBorder(
                              borderRadius: AppRadius.mdAll),
                        ),
                      ),
                    ),
                  ]),

                  const SizedBox(height: AppSpacing.xxl),
                  Text('Preferred Date & Time (optional)',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.sm),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: context,
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now()
                                .add(const Duration(days: 90)),
                          );
                          if (d != null) {
                            setState(() => _preferredDate = d);
                          }
                        },
                        icon: const Icon(TablerIcons.calendar_month,
                            size: 18),
                        label: Text(_preferredDate != null
                            ? '${_preferredDate!.day}/${_preferredDate!.month}/${_preferredDate!.year}'
                            : 'Date'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final t = await showTimePicker(
                            context: context,
                            initialTime:
                                const TimeOfDay(hour: 10, minute: 0),
                          );
                          if (t != null) {
                            setState(() => _preferredTime = t);
                          }
                        },
                        icon: const Icon(TablerIcons.clock,
                            size: 18),
                        label: Text(_preferredTime != null
                            ? _preferredTime!.format(context)
                            : 'Time'),
                      ),
                    ),
                  ]),

                  const SizedBox(height: AppSpacing.xxxl),
                  FilledButton.icon(
                    onPressed: _submitting ? null : _submit,
                    icon: _submitting
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(TablerIcons.send),
                    label: Text(_submitting
                        ? 'Posting...'
                        : 'Post Request'),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                ],
              ),
            ),
    );
  }
}
