import 'package:flutter/material.dart';
import '../supabase_client.dart';
import '../theme.dart';

class AvailabilityScreen extends StatefulWidget {
  const AvailabilityScreen({super.key});
  @override
  State<AvailabilityScreen> createState() => _AvailabilityScreenState();
}

class _AvailabilityScreenState extends State<AvailabilityScreen> {
  static const _dayNames = [
    'Sunday', 'Monday', 'Tuesday', 'Wednesday',
    'Thursday', 'Friday', 'Saturday',
  ];

  List<_DaySchedule> _days = List.generate(7, (i) => _DaySchedule(
    dayOfWeek: i,
    isAvailable: i >= 1 && i <= 5,
    startTime: const TimeOfDay(hour: 8, minute: 0),
    endTime: const TimeOfDay(hour: 17, minute: 0),
  ));

  List<DateTime> _blockedDates = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    try {
      final avail = await supabase
          .from('provider_availability')
          .select()
          .eq('provider_id', uid)
          .order('day_of_week');

      if (avail.isNotEmpty) {
        for (final row in avail) {
          final dow = row['day_of_week'] as int;
          if (dow >= 0 && dow < 7) {
            final start = _parseTime(row['start_time']);
            final end = _parseTime(row['end_time']);
            _days[dow] = _DaySchedule(
              dayOfWeek: dow,
              isAvailable: row['is_available'] == true,
              startTime: start,
              endTime: end,
            );
          }
        }
      }

      final blocked = await supabase
          .from('provider_blocked_dates')
          .select()
          .eq('provider_id', uid)
          .order('blocked_date');

      _blockedDates = blocked
          .map<DateTime>((r) => DateTime.parse(r['blocked_date']))
          .toList();
    } catch (_) {}

    if (mounted) setState(() => _loading = false);
  }

  TimeOfDay _parseTime(String time) {
    final parts = time.split(':');
    return TimeOfDay(
      hour: int.parse(parts[0]),
      minute: int.parse(parts[1]),
    );
  }

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  Future<void> _pickTime(int dayIndex, bool isStart) async {
    final current = isStart ? _days[dayIndex].startTime : _days[dayIndex].endTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: current,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _days[dayIndex] = _days[dayIndex].copyWith(startTime: picked);
      } else {
        _days[dayIndex] = _days[dayIndex].copyWith(endTime: picked);
      }
    });
  }

  Future<void> _addBlockedDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    if (_blockedDates.any((d) =>
        d.year == picked.year && d.month == picked.month && d.day == picked.day)) {
      return;
    }
    setState(() {
      _blockedDates.add(picked);
      _blockedDates.sort();
    });
  }

  Future<void> _save() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    setState(() => _saving = true);

    try {
      await supabase
          .from('provider_availability')
          .delete()
          .eq('provider_id', uid);

      final rows = _days.map((d) => ({
        'provider_id': uid,
        'day_of_week': d.dayOfWeek,
        'start_time': _formatTime(d.startTime),
        'end_time': _formatTime(d.endTime),
        'is_available': d.isAvailable,
      })).toList();

      await supabase.from('provider_availability').insert(rows);

      await supabase
          .from('provider_blocked_dates')
          .delete()
          .eq('provider_id', uid);

      if (_blockedDates.isNotEmpty) {
        final blockedRows = _blockedDates.map((d) => ({
          'provider_id': uid,
          'blocked_date': '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
        })).toList();
        await supabase.from('provider_blocked_dates').insert(blockedRows);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Schedule saved'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Working Hours'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: AppSpacing.screenPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Set your working hours for each day. Clients will only be able to book during these times.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  ...List.generate(7, (i) => _buildDayRow(i)),

                  const SizedBox(height: AppSpacing.xxl),
                  Divider(color: Colors.grey.shade200),
                  const SizedBox(height: AppSpacing.xl),

                  Row(
                    children: [
                      Icon(Icons.block_rounded, size: 18, color: AppColors.textSecondary),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        'Blocked Dates',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Block specific dates when you\'re unavailable (holidays, personal days).',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  if (_blockedDates.isNotEmpty)
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: _blockedDates.map((d) {
                        final label = '${d.day}/${d.month}/${d.year}';
                        return Chip(
                          label: Text(label, style: const TextStyle(fontSize: 13)),
                          deleteIcon: const Icon(Icons.close, size: 16),
                          onDeleted: () =>
                              setState(() => _blockedDates.remove(d)),
                          backgroundColor: AppColors.error.withValues(alpha: 0.08),
                          side: BorderSide(
                              color: AppColors.error.withValues(alpha: 0.2)),
                        );
                      }).toList(),
                    ),

                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton.icon(
                    onPressed: _addBlockedDate,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add Blocked Date'),
                  ),

                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }

  Widget _buildDayRow(int index) {
    final day = _days[index];
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: day.isAvailable ? AppColors.cardLight : AppColors.surfaceLight,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Switch(
              value: day.isAvailable,
              onChanged: (v) => setState(() {
                _days[index] = day.copyWith(isAvailable: v);
              }),
              activeColor: AppColors.primary,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: AppSpacing.lg),
          SizedBox(
            width: 80,
            child: Text(
              _dayNames[index],
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: day.isAvailable
                    ? AppColors.textPrimary
                    : AppColors.textTertiary,
              ),
            ),
          ),
          const Spacer(),
          if (day.isAvailable) ...[
            _TimeChip(
              time: day.startTime,
              onTap: () => _pickTime(index, true),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: Text('–', style: TextStyle(color: AppColors.textTertiary)),
            ),
            _TimeChip(
              time: day.endTime,
              onTap: () => _pickTime(index, false),
            ),
          ] else
            Text(
              'Closed',
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 13,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  final TimeOfDay time;
  final VoidCallback onTap;
  const _TimeChip({required this.time, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final label =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.08),
          borderRadius: AppRadius.smAll,
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}

class _DaySchedule {
  final int dayOfWeek;
  final bool isAvailable;
  final TimeOfDay startTime;
  final TimeOfDay endTime;

  const _DaySchedule({
    required this.dayOfWeek,
    required this.isAvailable,
    required this.startTime,
    required this.endTime,
  });

  _DaySchedule copyWith({
    bool? isAvailable,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
  }) =>
      _DaySchedule(
        dayOfWeek: dayOfWeek,
        isAvailable: isAvailable ?? this.isAvailable,
        startTime: startTime ?? this.startTime,
        endTime: endTime ?? this.endTime,
      );
}
