import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
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
      decoration: BoxDecoration(color: AppColors.cream, borderRadius: AppRadius.mdAll),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          joined
              ? 'You\'re on the waitlist. We\'ll notify you if a time opens on this day.'
              : 'No free times on this day.',
          style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
        ),
        if (widget.allowWaitlist && !joined) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _joining ? null : () => _joinWaitlist(day),
            icon: const Icon(TablerIcons.bell_ringing, size: 18),
            label: Text(_joining ? 'Adding…' : 'Notify me if a time opens'),
          ),
        ],
      ]),
    );
  }



  Widget _timeChip(String t) {
    final sel = _selectedTime == t;
    return InkWell(
      onTap: () {
        setState(() => _selectedTime = t);
        widget.onChanged(_selectedDay!, t);
      },
      borderRadius: AppRadius.smAll,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: sel ? AppColors.forest : AppColors.card,
          borderRadius: AppRadius.smAll,
          border: Border.all(color: sel ? AppColors.forest : AppColors.border),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (sel) ...[
            const Icon(TablerIcons.check, size: 16, color: AppColors.goldLight),
            const SizedBox(width: 6),
          ],
          Text(t,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: sel ? Colors.white : AppColors.textPrimary)),
        ]),
      ),
    );
  }

  Widget _timeGroup(String title, List<String> times) {
    if (times.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        LayoutBuilder(builder: (context, c) {
          final cols = c.maxWidth > 480 ? 5 : 3;
          final w = (c.maxWidth - 8 * (cols - 1)) / cols;
          return Wrap(spacing: 8, runSpacing: 8, children: [
            for (final t in times) SizedBox(width: w, child: _timeChip(t)),
          ]);
        }),
      ]),
    );
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
    final fullDay = _days.where((d) => d.slots == 0 && !_waitlisted.contains(d.day)).firstOrNull;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: 84,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _days.length + 1,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            if (i == _days.length) {
              return SizedBox(
                width: 72,
                child: OutlinedButton(
                  onPressed: _loadingMore ? null : () => _loadDays(),
                  style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll)),
                  child: _loadingMore
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('More\ndates', textAlign: TextAlign.center, style: TextStyle(fontSize: 13)),
                ),
              );
            }
            final d = _days[i];
            final selected = _selectedDay == d.day;
            final open = d.slots > 0;
            final diff = d.day.difference(_today).inDays;
            final tag = diff == 0 ? 'Today' : diff == 1 ? 'Tmrw' : _weekdays[d.day.weekday - 1];
            return InkWell(
              onTap: open || widget.allowWaitlist ? () => _selectDay(d.day) : null,
              borderRadius: AppRadius.mdAll,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 64,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: selected ? AppColors.forest : (open ? AppColors.card : AppColors.surfaceMuted),
                  borderRadius: AppRadius.mdAll,
                  border: Border.all(color: selected ? AppColors.forest : (open ? AppColors.border : Colors.transparent)),
                ),
                child: Column(children: [
                  Expanded(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(tag,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: selected ? AppColors.goldLight : AppColors.textSecondary)),
                      const SizedBox(height: 2),
                      Text('${d.day.day}',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: selected ? Colors.white : (open ? AppColors.textPrimary : AppColors.textTertiary))),
                      if (!open)
                        Text('FULL',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.4,
                                color: selected ? AppColors.goldLight : AppColors.textTertiary)),
                    ]),
                  ),
                  Container(height: 4, color: selected ? AppColors.gold : Colors.transparent),
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
                : 'No free times in these two weeks. Tap "More dates", or message the pro.',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
        )
      else if (_selectedDay != null) ...[
        if (_loadingSlots)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_slots.isEmpty)
          _waitlistBox(_selectedDay!)
        else ...[
          _timeGroup('Morning', _slots.where((t) => int.parse(t.substring(0, 2)) < 12).toList()),
          _timeGroup('Afternoon', _slots.where((t) {
            final h = int.parse(t.substring(0, 2));
            return h >= 12 && h < 17;
          }).toList()),
          _timeGroup('Evening', _slots.where((t) => int.parse(t.substring(0, 2)) >= 17).toList()),
        ],
      ],
      if (widget.allowWaitlist && fullDay != null && _selectedDay != fullDay.day)
        Material(
          color: AppColors.cream,
          borderRadius: AppRadius.mdAll,
          child: InkWell(
            borderRadius: AppRadius.mdAll,
            onTap: _joining ? null : () => _joinWaitlist(fullDay.day),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(children: [
                Icon(TablerIcons.bell_ringing, size: 22, color: AppColors.goldText),
                const SizedBox(width: 10),
                Expanded(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: '${_weekdays[fullDay.day.weekday - 1]} ${fullDay.day.day} is full. '),
                    const TextSpan(text: 'Notify me if a time opens', style: TextStyle(fontWeight: FontWeight.w800)),
                  ]), style: TextStyle(fontSize: 14.5, color: AppColors.textPrimary)),
                ),
              ]),
            ),
          ),
        ),
    ]);
  }
}

/// Combines a picked day and "HH:MM" in Harare time (UTC+2, no DST) into a UTC instant.
DateTime slotToDateTime(DateTime day, String hhmm) {
  final h = int.parse(hhmm.substring(0, 2));
  final m = int.parse(hhmm.substring(3, 5));
  return DateTime.utc(day.year, day.month, day.day, h, m).subtract(const Duration(hours: 2));
}
