import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';

class BookingScreen extends StatefulWidget {
  final String providerId;
  final String serviceId;
  const BookingScreen({
    super.key,
    required this.providerId,
    required this.serviceId,
  });
  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  Map<String, dynamic>? _provider;
  Map<String, dynamic>? _service;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  final _addressCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final provider = await supabase
          .from('profiles')
          .select()
          .eq('id', widget.providerId)
          .maybeSingle();

      final service = await supabase
          .from('services')
          .select('*, service_categories(name, icon)')
          .eq('id', widget.serviceId)
          .maybeSingle();

      if (provider == null || service == null) {
        setState(() {
          _error = 'Could not load booking details';
          _loading = false;
        });
        return;
      }

      final clientProfile = await supabase
          .from('profiles')
          .select()
          .eq('id', supabase.auth.currentUser!.id)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _provider = provider;
          _service = service;
          _addressCtrl.text = clientProfile?['location'] ?? '';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 60)),
    );
    if (date != null) setState(() => _selectedDate = date);
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 10, minute: 0),
    );
    if (time != null) setState(() => _selectedTime = time);
  }

  Future<bool> _hasConflict(DateTime bookingDateTime) async {
    final service = _service!;
    final durationMinutes = (service['duration_minutes'] as int?) ?? 60;
    final bookingEnd = bookingDateTime.add(Duration(minutes: durationMinutes));

    final existing = await supabase
        .from('bookings')
        .select('booking_time, services(duration_minutes)')
        .eq('provider_id', widget.providerId)
        .inFilter('status', ['pending', 'confirmed']);

    for (final b in existing as List) {
      final existingStart = DateTime.parse(b['booking_time']);
      final existingDur = (b['services']?['duration_minutes'] as int?) ?? 60;
      final existingEnd = existingStart.add(Duration(minutes: existingDur));

      if (bookingDateTime.isBefore(existingEnd) &&
          bookingEnd.isAfter(existingStart)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _confirmBooking() async {
    if (_selectedDate == null || _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a date and time')),
      );
      return;
    }
    if (_addressCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your address')),
      );
      return;
    }

    final bookingDateTime = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _selectedTime!.hour,
      _selectedTime!.minute,
    );

    if (bookingDateTime.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a future date and time')),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final pp = await supabase
          .from('provider_profiles')
          .select('availability_status')
          .eq('provider_id', widget.providerId)
          .maybeSingle();

      if (pp?['availability_status'] == 'busy') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This provider is currently busy'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        setState(() => _submitting = false);
        return;
      }

      final conflict = await _hasConflict(bookingDateTime);
      if (conflict) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'The provider already has a booking at that time. Please choose another slot.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() => _submitting = false);
        return;
      }

      await supabase.from('bookings').insert({
        'client_id': supabase.auth.currentUser!.id,
        'provider_id': widget.providerId,
        'service_id': widget.serviceId,
        'booking_time': bookingDateTime.toIso8601String(),
        'address': _addressCtrl.text.trim(),
        'status': 'pending',
        'total_price': _service!['price'],
        'client_note':
            _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      });

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: const Text('Booking Sent! 🎉'),
            content: const Text(
                'Your booking request has been sent to the provider. '
                'You\'ll be notified once they confirm.'),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  context.go('/client/bookings');
                },
                child: const Text('View My Bookings'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(body: const Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Book Appointment')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(_error!),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final cat = _service!['service_categories'] as Map?;
    final dateStr = _selectedDate == null
        ? 'Select date'
        : '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}';
    final timeStr = _selectedTime == null
        ? 'Select time'
        : _selectedTime!.format(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Book Appointment')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Service summary card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Text(cat?['icon'] ?? '✂️',
                    style: const TextStyle(fontSize: 32)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_service!['service_name'],
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      Text(
                        '${cat?['name'] ?? ''} · ${_service!['duration_minutes']} min',
                        style: const TextStyle(fontSize: 13),
                      ),
                      Text('with ${_provider!['full_name']}',
                          style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
                Text('\$${_service!['price']}',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                        color: Theme.of(context).colorScheme.primary)),
              ]),
            ),

            const SizedBox(height: 28),
            const Text('Date & Time',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 10),

            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text(dateStr),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.access_time_rounded),
                  label: Text(timeStr),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ]),

            const SizedBox(height: 20),
            const Text('Your Address',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 10),

            TextFormField(
              controller: _addressCtrl,
              decoration: const InputDecoration(
                hintText: 'e.g. 12 Borrowdale Rd, Harare',
                prefixIcon: Icon(Icons.location_on_outlined),
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),

            const SizedBox(height: 20),
            const Text('Note to Provider (optional)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 10),

            TextFormField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                hintText: 'e.g. Please bring your own products',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),

            const SizedBox(height: 32),

            // Price summary
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Service'),
                    Text('\$${_service!['price']}'),
                  ],
                ),
                const Divider(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text('\$${_service!['price']}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 18)),
                  ],
                ),
                const SizedBox(height: 4),
                const Text('Payment collected at time of service',
                    style: TextStyle(color: Colors.grey, fontSize: 11)),
              ]),
            ),

            const SizedBox(height: 24),

            FilledButton.icon(
              onPressed: _submitting ? null : _confirmBooking,
              icon: _submitting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_circle_outline),
              label: Text(_submitting
                  ? 'Sending Request...'
                  : 'Confirm Booking Request'),
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
          ],
        ),
      ),
    );
  }
}