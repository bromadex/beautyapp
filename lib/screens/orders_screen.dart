import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_client.dart';
import '../theme.dart';
import '../utils/feel.dart';
import '../utils/pay_methods.dart';
import '../widgets/booking_bits.dart' show payBrand;
import '../widgets/shop_bits.dart';
import '../widgets/ui.dart';

const _orderSelect = '*, order_items(*), '
    'buyer:profiles!orders_buyer_id_fkey(full_name, avatar_url), '
    'seller:profiles!orders_seller_id_fkey(full_name, avatar_url)';

String _when(String? iso) {
  final d = DateTime.tryParse(iso ?? '')?.toLocal();
  if (d == null) return '';
  final now = DateTime.now();
  final diff = now.difference(d);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24 && d.day == now.day) return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${m[d.month - 1]}';
}

// =====================================================================
// Lists
// =====================================================================

/// Orders as a list: as buyer, as seller, or every order (admin).
class OrdersList extends StatefulWidget {
  final String role; // buying | selling | all
  final EdgeInsets padding;
  const OrdersList({super.key, required this.role, this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 32)});

  @override
  State<OrdersList> createState() => _OrdersListState();
}

class _OrdersListState extends State<OrdersList> {
  bool _loading = true;
  List<Map<String, dynamic>> _orders = [];
  String _filter = 'open';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      var q = supabase.from('orders').select(_orderSelect);
      if (widget.role == 'buying') q = q.eq('buyer_id', myId!);
      if (widget.role == 'selling') q = q.eq('seller_id', myId!);
      final rows = await q.order('updated_at', ascending: false).limit(200);
      _orders = List<Map<String, dynamic>>.from(rows);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  bool _open(Map o) => !['done', 'declined', 'cancelled'].contains(o['status']);

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingPlaceholder();
    final shown = _orders.where((o) => _filter == 'all' || (_filter == 'open') == _open(o)).toList();
    final asSeller = widget.role == 'selling';
    return RefreshIndicator.adaptive(
      onRefresh: _load,
      child: ListView(padding: widget.padding, children: [
        Row(children: [
          for (final f in const [('open', 'Open'), ('closed', 'Finished'), ('all', 'All')])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                showCheckmark: false,
                label: Text(f.$1 == 'open' ? '${f.$2} · ${_orders.where(_open).length}' : f.$2),
                selected: _filter == f.$1,
                onSelected: (_) => setState(() => _filter = f.$1),
              ),
            ),
        ]),
        const SizedBox(height: 12),
        if (shown.isEmpty)
          EmptyState(
            icon: TablerIcons.receipt,
            title: _filter == 'open' ? 'No open orders' : 'No orders yet',
            message: asSeller
                ? 'When someone orders your items, it shows up here.'
                : widget.role == 'all'
                    ? 'Shop orders across BeauTap show up here.'
                    : 'Things you order from the shop show up here.',
            actionLabel: widget.role == 'buying' ? 'Go to the shop' : null,
            onAction: widget.role == 'buying' ? () => context.push('/market') : null,
          )
        else
          for (final o in shown)
            OrderCard(
              order: o,
              asSeller: widget.role == 'all' ? null : asSeller,
              onTap: () async {
                await context.push('/orders/${o['id']}');
                _load();
              },
            ),
      ]),
    );
  }
}

class OrderCard extends StatelessWidget {
  final Map<String, dynamic> order;

  /// null: admin view (shows both people).
  final bool? asSeller;
  final VoidCallback onTap;
  const OrderCard({super.key, required this.order, required this.asSeller, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final o = order;
    final items = List<Map<String, dynamic>>.from(o['order_items'] as List? ?? const []);
    final other = Map<String, dynamic>.from((asSeller == true ? o['buyer'] : o['seller']) as Map? ?? const {});
    final st = orderStatus(o, asSeller: asSeller ?? false);
    final img = items.isEmpty ? null : items.first['image_url'] as String?;
    final title = items.isEmpty
        ? 'Order'
        : items.length == 1
            ? '${items.first['qty'] > 1 ? '${items.first['qty']} × ' : ''}${items.first['name']}'
            : '${items.first['name']} + ${items.length - 1} more';
    final who = asSeller == null
        ? '${(o['buyer'] as Map?)?['full_name'] ?? '?'} → ${(o['seller'] as Map?)?['full_name'] ?? '?'}'
        : '${asSeller! ? 'From' : 'Sold by'} ${other['full_name'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.card,
        borderRadius: AppRadius.mdAll,
        child: InkWell(
          borderRadius: AppRadius.mdAll,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              SizedBox(width: 58, height: 58, child: ProductImage(img, radius: AppRadius.smAll)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('$who · ${_when(o['updated_at'])}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                  const SizedBox(height: 6),
                  Row(children: [
                    statusChip(st.label, st.color),
                    if (st.mine && asSeller != null) ...[
                      const SizedBox(width: 6),
                      Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.gold, shape: BoxShape.circle)),
                    ],
                  ]),
                ]),
              ),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(money(o['total'] as num?), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                Text('#${o['ref']}', style: TextStyle(fontSize: 11.5, color: AppColors.textTertiary)),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}

/// /orders: what I bought, and (for pros) what I sold.
class MyOrdersScreen extends StatelessWidget {
  final bool selling;
  const MyOrdersScreen({super.key, this.selling = false});

  @override
  Widget build(BuildContext context) {
    final isPro = supabase.auth.currentUser?.userMetadata?['user_type'] == 'provider';
    if (!isPro) {
      return Scaffold(appBar: AppBar(title: const Text('My orders')), body: const OrdersList(role: 'buying'));
    }
    return DefaultTabController(
      length: 2,
      initialIndex: selling ? 1 : 0,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Orders'),
          bottom: const TabBar(tabs: [Tab(text: 'Buying'), Tab(text: 'Selling')]),
        ),
        body: const TabBarView(children: [OrdersList(role: 'buying'), OrdersList(role: 'selling')]),
      ),
    );
  }
}

class AdminOrdersScreen extends StatelessWidget {
  const AdminOrdersScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: const Text('Shop orders')), body: const OrdersList(role: 'all'));
}

// =====================================================================
// One order: where it's at, what to do next, and the chat
// =====================================================================

class OrderScreen extends StatefulWidget {
  final String orderId;
  const OrderScreen({super.key, required this.orderId});

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  Map<String, dynamic>? _o;
  List<Map<String, dynamic>> _msgs = [];
  List<PayMethod> _sellerPays = const [];
  Map<String, dynamic>? _rating;
  bool _loading = true;
  bool _busy = false;
  RealtimeChannel? _channel;
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load(first: true);
  }

  @override
  void dispose() {
    if (_channel != null) supabase.removeChannel(_channel!);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool first = false}) async {
    try {
      final res = await Future.wait<dynamic>([
        supabase.from('orders').select(_orderSelect).eq('id', widget.orderId).maybeSingle(),
        supabase.from('order_messages').select().eq('order_id', widget.orderId).order('created_at', ascending: true),
        supabase.from('seller_ratings').select().eq('order_id', widget.orderId).maybeSingle(),
      ]);
      if (res[0] != null) {
        _o = Map<String, dynamic>.from(res[0] as Map);
        _msgs = List<Map<String, dynamic>>.from(res[1] as List);
        _rating = res[2] == null ? null : Map<String, dynamic>.from(res[2] as Map);
        if (first && _isBuyer) {
          final pp = await supabase
              .from('provider_profiles')
              .select('accepts_cash, ecocash_number, ecocash_name, ecocash_merchant, innbucks_number, onemoney_number, bank_details')
              .eq('provider_id', _o!['seller_id'])
              .maybeSingle();
          _sellerPays = payMethodsOf(pp == null ? null : Map<String, dynamic>.from(pp));
        }
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => _loading = false);
    if (first && _o != null) _subscribe();
  }

  void _subscribe() {
    _channel = supabase
        .channel('order_${widget.orderId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'order_messages',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'order_id', value: widget.orderId),
          callback: (p) {
            final m = Map<String, dynamic>.from(p.newRecord);
            if (_msgs.any((x) => x['id'] == m['id'])) return;
            if (mounted) setState(() => _msgs.add(m));
            if (m['kind'] != 'text') _load();
            _toEnd();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'orders',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'id', value: widget.orderId),
          callback: (_) => _load(),
        )
        .subscribe();
  }

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });

  bool get _isBuyer => _o?['buyer_id'] == myId;
  bool get _isSeller => _o?['seller_id'] == myId;
  String get _status => _o?['status'] ?? 'requested';
  Map<String, dynamic> get _terms => Map<String, dynamic>.from((_o?['terms'] as Map?) ?? const {});
  String _first(String who) => ((_o?[who] as Map?)?['full_name'] ?? '').toString().split(' ').first;

  Future<void> _rpc(String fn, Map<String, dynamic> params, {String? done}) async {
    setState(() => _busy = true);
    try {
      await supabase.rpc(fn, params: params);
      Haptics.firm();
      await _load();
      if (done != null && mounted) shopToast(context, done);
      _toEnd();
    } catch (e) {
      if (mounted) shopToast(context, errText(e), error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _step(String step, {String? note, String? done}) =>
      _rpc('order_step', {'p_order': widget.orderId, 'p_step': step, 'p_note': note}, done: done);

  Future<void> _send() async {
    final t = _input.text.trim();
    if (t.isEmpty) return;
    _input.clear();
    try {
      final m = await supabase
          .from('order_messages')
          .insert({'order_id': widget.orderId, 'sender_id': myId, 'kind': 'text', 'body': t})
          .select()
          .single();
      if (mounted && !_msgs.any((x) => x['id'] == m['id'])) setState(() => _msgs.add(Map<String, dynamic>.from(m)));
      _toEnd();
    } catch (e) {
      _input.text = t;
      if (mounted) shopToast(context, errText(e), error: true);
    }
  }

  Future<String?> _askNote(String title, String label, {String? hint, String action = 'Send'}) async {
    final c = TextEditingController();
    final r = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, maxLength: 300, maxLines: 2, decoration: InputDecoration(labelText: label, hintText: hint)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Back')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(action)),
        ],
      ),
    );
    return r;
  }

  Future<void> _offer() async {
    final o = _o!;
    final amount = await showModalBottomSheet<(double, String)>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _OfferSheet(asking: o['total'] as num, lastOffer: o['buyer_offer'] as num?),
    );
    if (amount == null) return;
    await _rpc('offer_order_price', {'p_order': widget.orderId, 'p_amount': amount.$1, 'p_note': amount.$2},
        done: 'Offer sent to ${_first('seller')}');
  }

  Future<void> _sendTerms({num? atPrice}) async {
    final o = _o!;
    if (atPrice != null) {
      await _rpc('send_order_terms', {
        'p_order': widget.orderId,
        'p_get': _terms['get'] ?? o['pref_get'],
        'p_pay': _terms['pay'] ?? o['pref_pay'],
        'p_delivery_fee': 0,
        'p_details': 'Deal at ${money(atPrice)}',
        'p_total': atPrice,
      }, done: 'Terms sent at ${money(atPrice)}');
      return;
    }
    final settings = await supabase.from('shop_settings').select().eq('provider_id', myId!).maybeSingle();
    if (!mounted) return;
    final r = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _TermsSheet(order: o, settings: settings == null ? const {} : Map<String, dynamic>.from(settings)),
    );
    if (r == null) return;
    await _rpc('send_order_terms', {'p_order': widget.orderId, ...r}, done: 'Terms sent');
  }

  Future<void> _rate() async {
    final r = await showModalBottomSheet<(int, String)>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RateSheet(seller: _first('seller'), initial: (_rating?['rating'] as num?)?.toInt() ?? 0),
    );
    if (r == null) return;
    await _rpc('rate_seller', {'p_order': widget.orderId, 'p_rating': r.$1, 'p_comment': r.$2}, done: 'Thanks for rating');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Scaffold(appBar: AppBar(), body: const LoadingPlaceholder(kind: PlaceholderKind.detail));
    final o = _o;
    if (o == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: TablerIcons.receipt_off, title: 'Order not found', message: 'It may belong to someone else.'),
      );
    }
    final canChat = (_isBuyer || _isSeller);
    return Scaffold(
      appBar: AppBar(title: Text('Order #${o['ref']}')),
      body: Column(children: [
        Expanded(
          child: ListView(controller: _scroll, padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
            _header(o),
            const SizedBox(height: 14),
            _actionCard(o),
            sectionLabel('Items'),
            _itemsCard(o),
            sectionLabel('Messages'),
            if (_msgs.isEmpty)
              Text('No messages yet.', style: TextStyle(color: AppColors.textTertiary))
            else
              for (final m in _msgs) _bubble(m),
          ]),
        ),
        if (canChat) _inputBar(),
      ]),
    );
  }

  Widget _header(Map<String, dynamic> o) {
    final st = orderStatus(o, asSeller: _isSeller);
    final otherKey = _isSeller ? 'buyer' : 'seller';
    final other = Map<String, dynamic>.from((o[otherKey] as Map?) ?? const {});
    const steps = ['Request', 'Agreed', 'Paid', 'Ready', 'Done'];
    final idx = switch (_status) {
      'requested' || 'terms_sent' => 0,
      'agreed' => 1,
      'paid' => 2,
      'ready' => 3,
      'done' => 4,
      _ => -1,
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        PersonAvatar(name: other['full_name'] ?? '', url: other['avatar_url'], size: 40),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(other['full_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
            Text(_isSeller ? 'Buyer' : (_isBuyer ? 'Seller' : 'Admin view'),
                style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
          ]),
        ),
        statusChip(st.label, st.color),
      ]),
      if (idx >= 0) ...[
        const SizedBox(height: 14),
        Row(children: [
          for (var i = 0; i < steps.length; i++)
            Expanded(
              child: Column(children: [
                Container(
                  height: 4,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: i <= idx ? AppColors.gold : AppColors.border,
                    borderRadius: AppRadius.pill,
                  ),
                ),
                const SizedBox(height: 4),
                Text(steps[i],
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: i == idx ? FontWeight.w700 : FontWeight.w500,
                      color: i <= idx ? AppColors.textPrimary : AppColors.textTertiary,
                    )),
              ]),
            ),
        ]),
      ],
    ]);
  }

  /// The card that says what happens next, with the buttons for it.
  Widget _actionCard(Map<String, dynamic> o) {
    final total = o['total'] as num;
    final offer = o['buyer_offer'] as num?;
    final seller = _first('seller');
    final buyer = _first('buyer');
    final payId = (_terms['pay'] ?? o['pref_pay'] ?? 'cash') as String;
    final get = (_terms['get'] ?? o['pref_get']) as String?;
    String title;
    String? body;
    final buttons = <Widget>[];
    Widget? extra;

    Widget primary(String t, VoidCallback f) => FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)), onPressed: _busy ? null : f, child: Text(t));
    Widget secondary(String t, VoidCallback f) => OutlinedButton(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)), onPressed: _busy ? null : f, child: Text(t));
    Widget quiet(String t, VoidCallback f, {bool danger = false}) => TextButton(
        onPressed: _busy ? null : f,
        child: Text(t, style: TextStyle(color: danger ? AppColors.errorText : AppColors.textSecondary)));

    if (_terms.isNotEmpty && _status != 'requested') {
      extra = _TermsCard(terms: _terms, itemsTotal: o['items_total'] as num);
    }

    switch (_status) {
      case 'requested' when _isSeller:
        if (offer != null) {
          title = '$buyer offered ${money(offer)}';
          body = 'You asked ${money(total)}. Accept their price, or send terms with your own price.';
          buttons.addAll([
            primary('Accept ${money(offer)}', () => _sendTerms(atPrice: offer)),
            secondary('Send terms with my price', _sendTerms),
          ]);
        } else {
          title = 'Send $buyer your terms';
          body = 'Confirm the total, how they pay you and how they get it. They\'ll accept it, or offer a price.';
          buttons.add(primary('Send terms', _sendTerms));
        }
        buttons.add(quiet('Decline order', () async {
          final n = await _askNote('Decline this order?', 'Reason (optional)', hint: 'e.g. Out of stock', action: 'Decline');
          if (n != null) await _step('decline', note: n, done: 'Order declined');
        }, danger: true));
      case 'requested':
        title = offer != null ? 'You offered ${money(offer)}' : 'Waiting for $seller\'s terms';
        body = offer != null
            ? '$seller will accept it or reply with their price. You\'ll get a notification.'
            : '$seller will confirm the total, how to pay and how you get it. You\'ll get a notification.';
        buttons.add(secondary(offer != null ? 'Change my offer' : 'Offer a different price', _offer));
        buttons.add(quiet('Cancel order', () async {
          final n = await _askNote('Cancel this order?', 'Reason (optional)', action: 'Cancel order');
          if (n != null) await _step('cancel', note: n, done: 'Order cancelled');
        }, danger: true));
      case 'terms_sent' when _isBuyer:
        title = 'Check $seller\'s terms';
        body = 'Accept them and you\'ll pay $seller directly. Or offer another price.';
        buttons.addAll([
          primary('Accept · ${money(total)}', () => _step('accept', done: 'Terms accepted')),
          secondary('Offer a different price', _offer),
          quiet('Cancel order', () async {
            final n = await _askNote('Cancel this order?', 'Reason (optional)', action: 'Cancel order');
            if (n != null) await _step('cancel', note: n, done: 'Order cancelled');
          }, danger: true),
        ]);
      case 'terms_sent':
        title = 'Waiting for $buyer';
        body = 'They\'ll accept your terms or offer another price.';
        buttons.addAll([
          secondary('Change terms', _sendTerms),
          quiet('Decline order', () async {
            final n = await _askNote('Decline this order?', 'Reason (optional)', action: 'Decline');
            if (n != null) await _step('decline', note: n, done: 'Order declined');
          }, danger: true),
        ]);
      case 'agreed' when _isBuyer:
        if (o['buyer_paid_at'] != null) {
          title = 'Payment sent';
          body = '$seller will confirm once it\'s in.';
        } else if (payId == 'cash') {
          title = 'Pay ${money(total)} in cash';
          body = 'Pay $seller when you ${get == 'deliver' ? 'get your delivery' : 'meet'}. They mark it paid.';
        } else {
          final pm = _sellerPays.where((p) => p.id == payId).firstOrNull;
          title = 'Pay $seller ${money(total)}';
          body = pm?.account != null
              ? 'By ${pm!.label} to ${pm.displayAccount}${pm.accountName != null ? ' (${pm.accountName})' : ''}, then tap "I\'ve paid".'
              : 'By ${payMethodLabel(payId)}. Ask $seller for the details in the chat, then tap "I\'ve paid".';
          final ussd = pm?.ussd(total);
          if (pm?.account != null) {
            buttons.add(secondary('Copy ${pm!.id == 'bank' ? 'bank details' : 'number'}', () {
              Clipboard.setData(ClipboardData(text: pm.account!));
              shopToast(context, 'Copied');
            }));
          }
          if (ussd != null) {
            buttons.add(Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('EcoCash: dial $ussd', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            ));
          }
          buttons.insert(0, primary('I\'ve paid', () => _step('paid', done: '$seller will confirm your payment')));
        }
        buttons.add(quiet('Cancel order', () async {
          final n = await _askNote('Cancel this order?', 'Reason (optional)', action: 'Cancel order');
          if (n != null) await _step('cancel', note: n, done: 'Order cancelled');
        }, danger: true));
      case 'agreed':
        title = o['buyer_paid_at'] != null ? '$buyer says they paid ${money(total)}' : 'Waiting for $buyer to pay';
        body = o['buyer_paid_at'] != null
            ? 'Check your ${payMethodLabel(payId)} and confirm when it\'s in.'
            : payId == 'cash'
                ? 'They\'ll pay ${money(total)} in cash. Tap Received when you have it.'
                : 'They\'ll pay ${money(total)} by ${payMethodLabel(payId)}.';
        buttons.add(primary('Received ${money(total)}', () => _step('received', done: 'Payment received')));
      case 'paid' when _isSeller:
        final away = get == 'deliver' || get == 'post';
        title = away ? 'Send it to $buyer' : 'Get it ready for $buyer';
        body = 'Tap below when it\'s ${away ? 'on its way' : 'ready to collect'}. Add where and when.';
        buttons.addAll([
          primary(away ? 'It\'s on its way' : 'Ready to collect', () async {
            final n = await _askNote(away ? 'On its way' : 'Ready to collect', away ? 'Details (optional)' : 'Where and when (optional)',
                hint: away ? 'e.g. With Swift courier, arrives Friday' : 'e.g. At my salon, Sat 9 to 1');
            if (n != null) await _step('ready', note: n, done: '$buyer has been told');
          }),
          quiet('Mark complete', () => _step('done', done: 'Order complete')),
        ]);
      case 'paid':
        title = '$seller is getting it ready';
        body = 'You\'ll get a notification when it\'s ready or on its way.';
        buttons.add(quiet('I\'ve got it already', () => _step('done', done: 'Order complete')));
      case 'ready' when _isBuyer:
        final away = get == 'deliver' || get == 'post';
        title = away ? 'On its way' : 'Ready to collect';
        body = (o['ready_note'] ?? '').toString().isNotEmpty ? o['ready_note'] : null;
        buttons.add(primary('I\'ve got it', () => _step('done', done: 'Enjoy!')));
      case 'ready':
        title = 'Waiting for $buyer to get it';
        body = 'Mark it complete once they have it.';
        buttons.add(secondary('Mark complete', () => _step('done', done: 'Order complete')));
      case 'done':
        title = 'Order complete';
        if (_isBuyer) {
          body = _rating == null ? 'How was buying from $seller?' : 'You rated $seller ${'★' * ((_rating!['rating'] as num).toInt())}';
          buttons.add(_rating == null ? primary('Rate $seller', _rate) : quiet('Change rating', _rate));
        } else {
          body = _rating == null ? null : '$buyer rated you ${'★' * ((_rating!['rating'] as num).toInt())}'
              '${(_rating!['comment'] ?? '').toString().isEmpty ? '' : ': “${_rating!['comment']}”'}';
        }
        buttons.add(quiet(_isBuyer ? 'Buy again' : 'Open my shop',
            () => context.push(_isBuyer ? '/shop/seller/${o['seller_id']}' : '/provider/shop')));
      case 'declined':
        title = 'Declined';
        body = (o['cancel_reason'] ?? '').toString().isNotEmpty ? o['cancel_reason'] : null;
      default:
        title = 'Cancelled';
        body = (o['cancel_reason'] ?? '').toString().isNotEmpty ? o['cancel_reason'] : null;
    }
    if (!_isBuyer && !_isSeller) buttons.clear();

    final st = orderStatus(o, asSeller: _isSeller);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: st.mine ? AppColors.gold : AppColors.border, width: st.mine ? 1.5 : 1),
        boxShadow: AppColors.isDark ? null : AppShadows.lifted,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        if (body != null) ...[
          const SizedBox(height: 4),
          Text(body, style: TextStyle(color: AppColors.textSecondary, height: 1.4)),
        ],
        if (extra != null) ...[const SizedBox(height: 12), extra],
        if (buttons.isNotEmpty) const SizedBox(height: 12),
        for (final b in buttons) Padding(padding: const EdgeInsets.only(top: 6), child: b),
      ]),
    );
  }

  Widget _itemsCard(Map<String, dynamic> o) {
    final items = List<Map<String, dynamic>>.from(o['order_items'] as List? ?? const []);
    final fee = o['delivery_fee'] as num? ?? 0;
    final itemsTotal = o['items_total'] as num? ?? 0;
    final total = o['total'] as num? ?? 0;
    final diff = itemsTotal + fee - total;
    Widget line(String a, String b, {bool bold = false, Color? color}) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(children: [
            Text(a, style: TextStyle(color: color ?? AppColors.textSecondary, fontWeight: bold ? FontWeight.w700 : null)),
            const Spacer(),
            Text(b, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600, fontSize: bold ? 17 : 14, color: color)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.mdAll),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final it in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: InkWell(
              onTap: it['product_id'] == null ? null : () => context.push('/shop/item/${it['product_id']}'),
              child: Row(children: [
                SizedBox(width: 46, height: 46, child: ProductImage(it['image_url'], radius: AppRadius.smAll)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('${it['qty']} × ${it['name']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                Text(money((it['price'] as num) * (it['qty'] as num))),
              ]),
            ),
          ),
        Divider(color: AppColors.border),
        line('Items', money(itemsTotal)),
        if (fee > 0) line('Delivery', money(fee)),
        if (diff > 0.005) line('Agreed discount', '−${money(diff)}', color: AppColors.success),
        if (diff < -0.005) line('Extra agreed', money(-diff)),
        line('Total', money(total), bold: true),
        const SizedBox(height: 8),
        Wrap(spacing: 14, runSpacing: 4, children: [
          _meta(getIcon(_terms['get'] ?? o['pref_get']), getLabel(_terms['get'] ?? o['pref_get'])),
          _meta(TablerIcons.wallet, payMethodLabel(_terms['pay'] ?? o['pref_pay'])),
        ]),
        if ((o['buyer_note'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Note: ${o['buyer_note']}', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        ],
      ]),
    );
  }

  Widget _meta(IconData i, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(i, size: 15, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Text(t, style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
      ]);

  Widget _bubble(Map<String, dynamic> m) {
    final kind = m['kind'] as String? ?? 'text';
    final body = (m['body'] ?? '').toString();
    if (kind == 'status' || m['sender_id'] == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Expanded(child: Divider(color: AppColors.border)),
          Flexible(
            flex: 4,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(body,
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.35)),
            ),
          ),
          Expanded(child: Divider(color: AppColors.border)),
        ]),
      );
    }
    final mine = m['sender_id'] == myId;
    final special = kind == 'terms' || kind == 'offer';
    final bg = special
        ? AppColors.primarySoft
        : mine
            ? AppColors.primary
            : AppColors.card;
    final fg = !special && mine ? AppColors.onPrimary : AppColors.textPrimary;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.75),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: special ? Border.all(color: AppColors.gold) : null,
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          if (special)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(kind == 'offer' ? TablerIcons.tag : TablerIcons.file_check, size: 14, color: AppColors.goldText),
                const SizedBox(width: 4),
                Text(kind == 'offer' ? 'PRICE OFFER' : 'TERMS',
                    style: TextStyle(fontSize: 10.5, letterSpacing: 0.8, fontWeight: FontWeight.w700, color: AppColors.goldText)),
              ]),
            ),
          Text(special ? body.replaceFirst(RegExp(r'^(Offer|Terms): '), '') : body,
              style: TextStyle(color: fg, fontWeight: special ? FontWeight.w700 : null, height: 1.35)),
          const SizedBox(height: 2),
          Text(_when(m['created_at']),
              style: TextStyle(fontSize: 10.5, color: fg.withValues(alpha: 0.6))),
        ]),
      ),
    );
  }

  Widget _inputBar() => SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          decoration: BoxDecoration(color: AppColors.card, border: Border(top: BorderSide(color: AppColors.border))),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                maxLength: 1000,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: 'Message ${_isSeller ? _first('buyer') : _first('seller')}',
                  counterText: '',
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filled(
              onPressed: _send,
              style: IconButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: AppColors.onPrimary),
              icon: Icon(TablerIcons.send, size: 20, color: AppColors.onPrimary),
            ),
          ]),
        ),
      );
}

class _TermsCard extends StatelessWidget {
  final Map<String, dynamic> terms;
  final num itemsTotal;
  const _TermsCard({required this.terms, required this.itemsTotal});

  @override
  Widget build(BuildContext context) {
    if (terms.isEmpty) return const SizedBox.shrink();
    final pay = (terms['pay'] ?? 'cash') as String;
    final discount = (terms['discount'] as num?) ?? 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: AppRadius.mdAll),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('Total', style: TextStyle(color: AppColors.textSecondary)),
          const Spacer(),
          if (discount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(money(itemsTotal + ((terms['delivery_fee'] as num?) ?? 0)),
                  style: TextStyle(decoration: TextDecoration.lineThrough, color: AppColors.textTertiary)),
            ),
          Text(money(terms['total'] as num?), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Icon(getIcon(terms['get']), size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 6),
          Text(getLabel(terms['get']) +
              (((terms['delivery_fee'] as num?) ?? 0) > 0 ? ' · ${money(terms['delivery_fee'] as num)} included' : '')),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: payBrand(pay).bg, borderRadius: BorderRadius.circular(5)),
            child: Text(payMethodLabel(pay), style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
          ),
        ]),
        if ((terms['details'] ?? '').toString().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('“${terms['details']}”', style: TextStyle(fontSize: 13.5, color: AppColors.textPrimary, height: 1.35)),
        ],
      ]),
    );
  }
}

class _OfferSheet extends StatefulWidget {
  final num asking;
  final num? lastOffer;
  const _OfferSheet({required this.asking, this.lastOffer});

  @override
  State<_OfferSheet> createState() => _OfferSheetState();
}

class _OfferSheetState extends State<_OfferSheet> {
  late final _amount = TextEditingController(text: widget.lastOffer == null ? '' : amountText(widget.lastOffer!));
  final _note = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quick = [0.9, 0.8].map((f) => (widget.asking * f).roundToDouble()).where((v) => v > 0 && v < widget.asking).toSet();
    return SheetScroll(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Offer a price', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text('The seller is asking ${money(widget.asking)}. They can accept your price or reply with theirs.',
              style: TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 14),
          if (quick.isNotEmpty)
            Wrap(spacing: 8, children: [
              for (final q in quick)
                ActionChip(label: Text(money(q)), onPressed: () => setState(() => _amount.text = amountText(q))),
            ]),
          const SizedBox(height: 8),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: const InputDecoration(labelText: 'Your price for everything', prefixText: '\$ '),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _note,
            maxLength: 300,
            decoration: const InputDecoration(labelText: 'Message (optional)', hintText: 'e.g. I\'ll collect today'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: () {
              final v = double.tryParse(_amount.text.trim());
              if (v == null || v <= 0) return;
              Navigator.pop(context, (v, _note.text.trim()));
            },
            child: const Text('Send offer'),
          ),
        ]),
      ),
    );
  }
}

class _TermsSheet extends StatefulWidget {
  final Map<String, dynamic> order;
  final Map<String, dynamic> settings;
  const _TermsSheet({required this.order, required this.settings});

  @override
  State<_TermsSheet> createState() => _TermsSheetState();
}

class _TermsSheetState extends State<_TermsSheet> {
  late final Map<String, dynamic> _t = Map<String, dynamic>.from((widget.order['terms'] as Map?) ?? const {});
  late String _get = (_t['get'] ?? widget.order['pref_get'] ?? 'collect') as String;
  late String _pay = (_t['pay'] ?? widget.order['pref_pay'] ?? 'cash') as String;
  late final _fee = TextEditingController(
      text: amountText((_t['delivery_fee'] as num?) ?? (_get == 'deliver' ? (widget.settings['delivery_fee'] as num? ?? 0) : 0)));
  late final _total = TextEditingController(text: amountText(widget.order['buyer_offer'] as num? ?? widget.order['total'] as num));
  late final _details = TextEditingController(text: (_t['details'] ?? '').toString());
  bool _totalEdited = false;

  num get _items => widget.order['items_total'] as num;
  num get _feeNum => num.tryParse(_fee.text.trim()) ?? 0;

  @override
  void initState() {
    super.initState();
    if (widget.order['buyer_offer'] == null && _t.isEmpty) _total.text = amountText(_items + _feeNum);
  }

  @override
  void dispose() {
    _fee.dispose();
    _total.dispose();
    _details.dispose();
    super.dispose();
  }

  void _syncTotal() {
    if (!_totalEdited) _total.text = amountText(_items + _feeNum);
  }

  @override
  Widget build(BuildContext context) {
    final offer = widget.order['buyer_offer'] as num?;
    final total = num.tryParse(_total.text.trim()) ?? 0;
    return SheetScroll(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Your terms', style: Theme.of(context).textTheme.headlineSmall),
          if (offer != null) ...[
            const SizedBox(height: 4),
            Text('They offered ${money(offer)} for items worth ${money(_items)}.', style: TextStyle(color: AppColors.goldText)),
          ],
          sectionLabel('How they get it'),
          ChoiceRow<String>(
            options: getOptions,
            value: _get,
            label: getLabel,
            icon: getIcon,
            onChanged: (g) => setState(() {
              _get = g;
              if (g != 'deliver' && g != 'post') {
                _fee.text = '0';
              } else if (_feeNum == 0 && widget.settings['delivery_fee'] != null) {
                _fee.text = amountText(widget.settings['delivery_fee'] as num);
              }
              _syncTotal();
            }),
          ),
          sectionLabel('How they pay you'),
          ChoiceRow<String>(options: payOptions, value: _pay, label: payMethodLabel, onChanged: (p) => setState(() => _pay = p)),
          const SizedBox(height: 14),
          Row(children: [
            if (_get == 'deliver' || _get == 'post') ...[
              Expanded(
                child: TextField(
                  controller: _fee,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  onChanged: (_) => setState(_syncTotal),
                  decoration: const InputDecoration(labelText: 'Delivery fee', prefixText: '\$ '),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: TextField(
                controller: _total,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                onChanged: (_) => setState(() => _totalEdited = true),
                decoration: const InputDecoration(labelText: 'Total they pay', prefixText: '\$ '),
              ),
            ),
          ]),
          if (total > 0 && total < _items + _feeNum)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Discount of ${money(_items + _feeNum - total)}', style: TextStyle(color: AppColors.success, fontSize: 13)),
            ),
          const SizedBox(height: 10),
          TextField(
            controller: _details,
            maxLength: 500,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Details (optional)', hintText: 'e.g. Collect at my salon in Avondale, Sat 9 to 1'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: total <= 0
                ? null
                : () => Navigator.pop(context, {
                      'p_get': _get,
                      'p_pay': _pay,
                      'p_delivery_fee': _feeNum,
                      'p_details': _details.text.trim(),
                      'p_total': total,
                    }),
            child: Text('Send terms · ${money(total)}'),
          ),
        ]),
      ),
    );
  }
}

class _RateSheet extends StatefulWidget {
  final String seller;
  final int initial;
  const _RateSheet({required this.seller, required this.initial});

  @override
  State<_RateSheet> createState() => _RateSheetState();
}

class _RateSheetState extends State<_RateSheet> {
  late int _stars = widget.initial;
  final _comment = TextEditingController();

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SheetScroll(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Rate ${widget.seller}', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                iconSize: 38,
                onPressed: () {
                  Haptics.light();
                  setState(() => _stars = i);
                },
                icon: Icon(i <= _stars ? TablerIcons.star_filled : TablerIcons.star,
                    color: i <= _stars ? const Color(0xFFA8822F) : AppColors.textTertiary),
              ),
          ]),
          TextField(
            controller: _comment,
            maxLength: 300,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'A few words (optional)', hintText: 'e.g. Quick and friendly'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
            onPressed: _stars == 0 ? null : () => Navigator.pop(context, (_stars, _comment.text.trim())),
            child: const Text('Send rating'),
          ),
        ]),
      ),
    );
  }
}
