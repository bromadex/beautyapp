import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../supabase_client.dart';
import '../theme.dart';

/// Date strip + time chips showing only times the stylist can actually take.
/// Availability comes from the `available_dates` / `available_slots` RPCs.
class SlotPicker extends StatefulWidget {
  final String providerId;
  final int minutes;
  final DateTime? initialDate;
  final String? initialTime;
  final void Function(DateTime date, String time) onChanged;

  /// Offer "notify me" on days with no free time (client booking only).
  final bool allowWaitlist;
  final String? serviceId;

  const SlotPicker({
    super.key,
    required this.providerId,
    required this.minutes,
    required this.onChanged,
    this.initialDate,
    this.initialTime,
    this.allowWaitlist = false,
    this.serviceId,
  });

  @override
  State<SlotPicker> createState() => _SlotPickerState();
}

class _SlotPickerState extends State<SlotPicker> {
  static const _pageDays = 14;
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  final List<({DateTime day, int slots})> _days = [];
  bool _loadingDays = true;
  bool _loadingMore = false;
  DateTime? _selectedDay;
  List<String> _slots = [];
  bool _loadingSlots = false;
  String? _selectedTime;
  final Set<DateTime> _waitlisted = {};
  bool _joining = false;

  @override
  void initState() {
    super.initState();
    _selectedDay = widget.initialDate;
    _selectedTime = widget.initialTime;
    _loadDays(reset: true);
  }

  @override
  void didUpdateWidget(SlotPicker old) {
    super.didUpdateWidget(old);
    if (old.minutes != widget.minutes || old.providerId != widget.providerId) {
      _selectedTime = null;
      _loadDays(reset: true);
    }
  }

  DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _loadDays({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loadingDays = true;
        _days.clear();
      });
    } else {
      setState(() => _loadingMore = true);
    }
    final from = reset ? _today : _days.last.day.add(const Duration(days: 1));
    try {
      final rows = await supabase.rpc('available_dates', params: {
        'p_provider': widget.providerId,
        'p_from': _iso(from),
        'p_days': _pageDays,
        'p_minutes': widget.minutes,
      }) as List;
      final parsed = rows.map((r) {
        final d = DateTime.parse(r['day'] as String);
        return (day: DateTime(d.year, d.month, d.day), slots: (r['slots'] as num).toInt());
      }).toList();
      if (!mounted) return;
      setState(() {
        _days.addAll(parsed);
        _loadingDays = false;
        _loadingMore = false;
      });
      final firstOpen = _days.where((d) => d.slots > 0);
      if (_selectedDay == null && firstOpen.isNotEmpty) {
        _selectDay(firstOpen.first.day);
      } else if (_selectedDay != null && reset) {
        _selectDay(_selectedDay!);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingDays = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _selectDay(DateTime day) async {
    setState(() {
      _selectedDay = day;
      _loadingSlots = true;
      _slots = [];
    });
    try {
      final rows = await supabase.rpc('available_slots', params: {
        'p_provider': widget.providerId,
        'p_date': _iso(day),
        'p_minutes': widget.minutes,
      }) as List;
      if (!mounted || _selectedDay != day) return;
      setState(() {
        _slots = rows.map((r) => r['slot'] as String).toList();
        _loadingSlots = false;
        if (_selectedTime != null && !_slots.contains(_selectedTime)) _selectedTime = null;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingSlots = false);
    }
  }

  Future<void> _joinWaitlist(DateTime day) async {
    setState(() => _joining = true);
    try {
      await supabase.rpc('join_waitlist', params: {
        'p_provider': widget.providerId,
        'p_day': _iso(day),
        'p_minutes': widget.minutes,
        'p_service': widget.serviceId,
      });
      if (mounted) setState(() => _waitlisted.add(day));
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Widget _waitlistBox(DateTime day) {
    final joined = _waitlisted.contains(day);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: AppRadius.mdAll),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          joined
              ? 'You\'re on the waitlist. We\'ll notify you if a time opens on this day.'
              : 'No free times on this day.',
          style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
        ),
        if (widget.allowWaitlist && !joined) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _joining ? null : () => _joinWaitlist(day),
            icon: const Icon(Icons.notifications_active_outlined, size: 18),
            label: Text(_joining ? 'Adding…' : 'Notify me if a time opens'),
          ),
        ],
      ]),
    );
  }

  String _label(String hhmm) {
    final h = int.parse(hhmm.substring(0, 2));
    final m = hhmm.substring(3);
    final suffix = h >= 12 ? 'pm' : 'am';
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:$m $suffix';
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingDays) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final anyOpen = _days.any((d) => d.slots > 0);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: 92,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _days.length + 1,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            if (i == _days.length) {
              return SizedBox(
                width: 76,
                child: OutlinedButton(
                  onPressed: _loadingMore ? null : () => _loadDays(),
                  style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                  child: _loadingMore
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('More\ndates', textAlign: TextAlign.center),
                ),
              );
            }
            final d = _days[i];
            final selected = _selectedDay == d.day;
            final open = d.slots > 0;
            final diff = d.day.difference(_today).inDays;
            final tag = diff == 0 ? 'TODAY' : diff == 1 ? 'TMRW' : _weekdays[d.day.weekday - 1].toUpperCase();
            return InkWell(
              onTap: open || widget.allowWaitlist ? () => _selectDay(d.day) : null,
              borderRadius: AppRadius.mdAll,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 68,
                decoration: BoxDecoration(
                  color: selected ? AppColors.primary : (open ? Colors.white : AppColors.surfaceMuted),
                  borderRadius: AppRadius.mdAll,
                  border: Border.all(color: selected ? AppColors.primary : AppColors.border),
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(tag,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          color: selected ? Colors.white70 : AppColors.textTertiary)),
                  const SizedBox(height: 2),
                  Text('${d.day.day}',
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: selected ? Colors.white : (open ? AppColors.textPrimary : AppColors.textTertiary))),
                  Text(open ? _months[d.day.month - 1] : 'Full',
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: selected ? Colors.white70 : (open ? AppColors.textSecondary : AppColors.textTertiary))),
                ]),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 20),
      if (!anyOpen && _selectedDay == null)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: AppRadius.mdAll),
          child: Text(
            widget.allowWaitlist
                ? 'No free times in these two weeks. Tap "More dates", or tap a day to get notified if a time opens.'
                : 'No free times in these two weeks. Tap "More dates", or message the stylist.',
            style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
          ),
        )
      else if (_selectedDay != null) ...[
        Text(
          '${_weekdays[_selectedDay!.weekday - 1]} ${_selectedDay!.day} ${_months[_selectedDay!.month - 1]}',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 10),
        if (_loadingSlots)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_slots.isEmpty)
          _waitlistBox(_selectedDay!)
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _slots.map((t) {
              final sel = _selectedTime == t;
              return InkWell(
                onTap: () {
                  setState(() => _selectedTime = t);
                  widget.onChanged(_selectedDay!, t);
                },
                borderRadius: AppRadius.smAll,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 92,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: sel ? AppColors.primary : Colors.white,
                    borderRadius: AppRadius.smAll,
                    border: Border.all(color: sel ? AppColors.primary : AppColors.borderStrong),
                  ),
                  child: Text(_label(t),
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: sel ? Colors.white : AppColors.textPrimary)),
                ),
              );
            }).toList(),
          ),
      ],
    ]);
  }
}

/// Combines a picked day and "HH:MM" in Harare time (UTC+2, no DST) into a UTC instant.
DateTime slotToDateTime(DateTime day, String hhmm) {
  final h = int.parse(hhmm.substring(0, 2));
  final m = int.parse(hhmm.substring(3, 5));
  return DateTime.utc(day.year, day.month, day.day, h, m).subtract(const Duration(hours: 2));
}
