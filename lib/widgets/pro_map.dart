import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import '../theme.dart';
import '../utils/feel.dart';
import 'ui.dart';

/// One pin on the map: a pro, or several pros sharing the same ~1 km area.
class _Spot {
  final LatLng at;
  final List<Map<String, dynamic>> pros;
  _Spot(this.at, this.pros);
}

/// Browse as a map. Pros are drawn as a soft ~1 km circle with their face
/// on it, never an exact point (the public pin is rounded on the server).
/// Free OpenStreetMap tiles. Swipe the cards and the map follows; tap a pin
/// and its card comes up.
class ProMapView extends StatefulWidget {
  final List<Map<String, dynamic>> providers;
  final Map<String, String> covers;
  final LatLng? centre;
  final double? Function(Map<String, dynamic>) distanceOf;
  final Set<String> saved;
  final void Function(String providerId) onSave;

  const ProMapView({
    super.key,
    required this.providers,
    required this.covers,
    required this.centre,
    required this.distanceOf,
    required this.saved,
    required this.onSave,
  });

  @override
  State<ProMapView> createState() => _ProMapViewState();
}

class _ProMapViewState extends State<ProMapView> {
  static const _harare = LatLng(-17.8292, 31.0522);
  final _map = MapController();
  PageController? _pages;
  int _selected = 0;
  bool _ready = false;

  List<Map<String, dynamic>> get _pinned => widget.providers
      .where((p) => p['latitude'] != null && p['longitude'] != null)
      .toList();

  LatLng _at(Map<String, dynamic> p) =>
      LatLng((p['latitude'] as num).toDouble(), (p['longitude'] as num).toDouble());

  /// Pros on the same rounded point share one pin with a "+N" bubble.
  List<_Spot> get _spots {
    final byKey = <String, _Spot>{};
    for (final p in _pinned) {
      final a = _at(p);
      final k = '${a.latitude.toStringAsFixed(3)},${a.longitude.toStringAsFixed(3)}';
      byKey.putIfAbsent(k, () => _Spot(a, [])).pros.add(p);
    }
    return byKey.values.toList();
  }

  @override
  void didUpdateWidget(ProMapView old) {
    super.didUpdateWidget(old);
    if (old.providers.length != widget.providers.length) {
      _selected = 0;
      if (_pages?.hasClients == true) _pages!.jumpToPage(0);
      WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
    }
  }

  @override
  void dispose() {
    _pages?.dispose();
    super.dispose();
  }

  void _fit() {
    if (!_ready) return;
    final pts = _pinned.map(_at).toList();
    if (pts.isEmpty) {
      _map.move(widget.centre ?? _harare, 12);
    } else if (pts.length == 1) {
      _map.move(pts.first, 13.5);
    } else {
      _map.fitCamera(CameraFit.coordinates(
        coordinates: pts,
        padding: const EdgeInsets.fromLTRB(50, 140, 50, 230),
        maxZoom: 14,
      ));
    }
  }

  void _select(int i, {bool fromCards = false}) {
    final list = _pinned;
    if (i < 0 || i >= list.length) return;
    if (i != _selected) Haptics.light();
    setState(() => _selected = i);
    final cam = _map.camera;
    _map.move(_at(list[i]), math.max(cam.zoom, 13));
    if (!fromCards && _pages?.hasClients == true) {
      _pages!.animateToPage(i, duration: Motion.of(context), curve: Motion.curve);
    }
  }

  String _price(Map<String, dynamic> p) {
    final services = (p['services'] as List? ?? []).where((s) => s['is_active'] == true).toList();
    if (services.isEmpty) return '';
    final low = services.map((s) => (s['price'] as num?)?.toDouble() ?? 0).reduce(math.min);
    return '\$${low.toStringAsFixed(0)}';
  }

  String? _photo(Map<String, dynamic> p) {
    final prof = p['profiles'] as Map? ?? {};
    final avatar = (prof['avatar_url'] ?? '').toString();
    return avatar.isNotEmpty ? avatar : widget.covers[p['provider_id']];
  }

  Widget _tiles() {
    final layer = TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.beautap.app',
      maxNativeZoom: 18,
      tileBuilder: AppColors.isDark ? darkModeTileBuilder : null,
    );
    return layer;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 900;
      final list = _pinned;
      if (_selected >= list.length) _selected = 0;
      final map = _mapLayer(list, wide);
      if (!wide) {
        _pages ??= PageController(viewportFraction: 0.86);
        return Stack(children: [
          Positioned.fill(child: map),
          if (list.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 12 + tabBarSpace(context),
              height: 128,
              child: PageView.builder(
                controller: _pages,
                itemCount: list.length,
                onPageChanged: (i) => _select(i, fromCards: true),
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: _MapCard(
                    pro: list[i],
                    photo: widget.covers[list[i]['provider_id']] ?? _photo(list[i]),
                    price: _price(list[i]),
                    distance: widget.distanceOf(list[i]),
                    selected: i == _selected,
                  ),
                ),
              ),
            ),
          if (list.length < widget.providers.length)
            Positioned(
              top: 10,
              left: 16,
              right: 16,
              child: Center(child: _NoteChip('${widget.providers.length - list.length} more pros have no map area yet. See List.')),
            ),
        ]);
      }
      // Laptop: the list on the left, the map on the right.
      return Row(children: [
        SizedBox(
          width: 400,
          child: ListView.builder(
            padding: EdgeInsets.fromLTRB(20, 4, 16, 16 + tabBarSpace(context)),
            itemCount: list.length,
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: MouseRegion(
                onEnter: (_) => _select(i),
                child: _MapCard(
                  pro: list[i],
                  photo: widget.covers[list[i]['provider_id']] ?? _photo(list[i]),
                  price: _price(list[i]),
                  distance: widget.distanceOf(list[i]),
                  selected: i == _selected,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(0, 4, 20, 16 + tabBarSpace(context)),
            child: ClipRRect(borderRadius: BorderRadius.circular(24), child: map),
          ),
        ),
      ]);
    });
  }

  Widget _mapLayer(List<Map<String, dynamic>> list, bool wide) {
    final spots = _spots;
    final selectedId = list.isEmpty ? null : list[_selected]['provider_id'];
    return Stack(children: [
      FlutterMap(
        mapController: _map,
        options: MapOptions(
          initialCenter: widget.centre ?? (list.isNotEmpty ? _at(list.first) : _harare),
          initialZoom: 12,
          minZoom: 5,
          maxZoom: 17,
          backgroundColor: AppColors.isDark ? const Color(0xFF1A1815) : const Color(0xFFEDE6D8),
          interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
          onMapReady: () {
            _ready = true;
            _fit();
          },
        ),
        children: [
          _tiles(),
          // About 1 km around each rounded pin: the pro is somewhere in here.
          CircleLayer(circles: [
            for (final s in spots)
              CircleMarker(
                point: s.at,
                radius: 650,
                useRadiusInMeter: true,
                color: AppColors.gold.withValues(alpha: 0.22),
                borderColor: AppColors.gold.withValues(alpha: 0.75),
                borderStrokeWidth: 1.5,
              ),
          ]),
          MarkerLayer(markers: [
            for (final s in spots)
              () {
                final selected = s.pros.any((p) => p['provider_id'] == selectedId);
                final lead = selected ? s.pros.firstWhere((p) => p['provider_id'] == selectedId) : s.pros.first;
                final size = selected ? 60.0 : 48.0;
                return Marker(
                  point: s.at,
                  width: 96,
                  height: size + 26,
                  alignment: Alignment.center,
                  child: GestureDetector(
                    onTap: () {
                      // Several pros here: each tap shows the next one.
                      final ids = s.pros.map((p) => p['provider_id']).toList();
                      final cur = ids.indexOf(selectedId);
                      final next = s.pros[(cur + 1) % s.pros.length];
                      _select(list.indexWhere((p) => p['provider_id'] == next['provider_id']));
                    },
                    child: _Pin(
                      name: ((lead['profiles'] as Map?)?['full_name'] ?? '').toString(),
                      photo: _photo(lead),
                      price: _price(lead),
                      size: size,
                      selected: selected,
                      more: s.pros.length - 1,
                    ),
                  ),
                );
              }(),
          ]),
          const RichAttributionWidget(
            alignment: AttributionAlignment.bottomLeft,
            showFlutterMapAttribution: false,
            attributions: [TextSourceAttribution('OpenStreetMap contributors')],
          ),
        ],
      ),
      Positioned(
        right: 14,
        bottom: wide ? 14 : 152 + tabBarSpace(context),
        child: Material(
          color: AppColors.card,
          shape: const CircleBorder(),
          elevation: 3,
          child: IconButton(
            tooltip: 'Show all pros',
            onPressed: () {
              Haptics.light();
              _fit();
            },
            icon: Icon(TablerIcons.focus_centered, color: AppColors.textPrimary),
          ),
        ),
      ),
    ]);
  }
}

class _Pin extends StatelessWidget {
  final String name;
  final String? photo;
  final String price;
  final double size;
  final bool selected;
  final int more;
  const _Pin(
      {required this.name, required this.photo, required this.price, required this.size, required this.selected, required this.more});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$name${price.isNotEmpty ? ', from $price' : ''}${more > 0 ? ', and $more more here' : ''}',
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Stack(clipBehavior: Clip.none, children: [
          AnimatedContainer(
            duration: Motion.fast,
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: selected ? AppColors.gold : (AppColors.isDark ? const Color(0xFF2A2722) : Colors.white), width: 3),
              boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 12, offset: Offset(0, 4))],
            ),
            child: ClipOval(child: ProPhoto(name: name, url: photo, radius: 0)),
          ),
          if (more > 0)
            Positioned(
              right: -6,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF141210),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Text('+$more',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.gold)),
              ),
            ),
        ]),
        if (price.isNotEmpty)
          Transform.translate(
            offset: const Offset(0, -6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.isDark ? AppColors.gold : const Color(0xFF141210),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(selected ? 'from $price' : price,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.isDark ? const Color(0xFF17130E) : const Color(0xFFF7F3EC))),
            ),
          ),
      ]),
    );
  }
}

class _MapCard extends StatelessWidget {
  final Map<String, dynamic> pro;
  final String? photo;
  final String price;
  final double? distance;
  final bool selected;
  const _MapCard({required this.pro, required this.photo, required this.price, required this.distance, required this.selected});

  @override
  Widget build(BuildContext context) {
    final prof = pro['profiles'] as Map? ?? {};
    final name = (prof['full_name'] ?? 'Beauty pro').toString();
    final verified = prof['is_verified'] == true;
    final area = (pro['area'] ?? '').toString();
    final rating = (pro['average_rating'] as num?)?.toDouble() ?? 0;
    final reviews = (pro['total_reviews'] as num?)?.toInt() ?? 0;
    final title = (pro['title'] ?? '').toString();
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(24),
      elevation: selected ? 6 : 2,
      shadowColor: const Color(0x33000000),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: () => context.push('/provider/${pro['provider_id']}'),
        child: AnimatedContainer(
          duration: Motion.fast,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: selected ? AppColors.gold : Colors.transparent, width: 2),
          ),
          child: Row(children: [
            SizedBox(width: 88, height: 104, child: ProPhoto(name: name, url: photo, radius: 18)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  ),
                  if (verified) ...[
                    const SizedBox(width: 4),
                    Icon(TablerIcons.rosette_discount_check_filled, size: 16, color: AppColors.info),
                  ],
                ]),
                Text(
                    [
                      if (title.isNotEmpty) title,
                      area.isNotEmpty ? '$area area' : 'Area not set',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 4),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(
                        text: reviews > 0 ? '★ ${rating.toStringAsFixed(1)}' : 'New',
                        style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    if (reviews > 0) TextSpan(text: ' ($reviews)'),
                    if (distance != null && distance! >= 1) TextSpan(text: ' · ${distance!.toStringAsFixed(1)} km'),
                  ]),
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                ),
                const Spacer(),
                Row(children: [
                  Expanded(
                    child: price.isEmpty
                        ? const SizedBox.shrink()
                        : Text.rich(TextSpan(children: [
                            TextSpan(text: 'from ', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                            TextSpan(
                                text: price,
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                          ])),
                  ),
                  Container(
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.primary, borderRadius: AppRadius.pill),
                    child: Text('Book',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.onPrimary)),
                  ),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _NoteChip extends StatelessWidget {
  final String text;
  const _NoteChip(this.text);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.card.withValues(alpha: 0.95),
          borderRadius: AppRadius.pill,
          boxShadow: const [BoxShadow(color: Color(0x22000000), blurRadius: 8)],
        ),
        child: Text(text, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      );
}
