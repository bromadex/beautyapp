import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../widgets/ui.dart';
import 'provider_public_profile_screen.dart';

/// Resolves a public booking link (/@slug) to the stylist's profile.
class StylistLinkScreen extends StatefulWidget {
  final String slug;
  const StylistLinkScreen({super.key, required this.slug});
  @override
  State<StylistLinkScreen> createState() => _StylistLinkScreenState();
}

class _StylistLinkScreenState extends State<StylistLinkScreen> {
  String? _providerId;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final row = await supabase
          .from('provider_profiles')
          .select('provider_id')
          .eq('slug', widget.slug.toLowerCase())
          .maybeSingle();
      if (mounted) {
        setState(() {
          _providerId = row?['provider_id'];
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_failed) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: TablerIcons.wifi_off,
          title: 'Couldn\'t load this page',
          message: 'Check your connection and try again.',
          actionLabel: 'Try again',
          onAction: _resolve,
        ),
      );
    }
    if (_providerId == null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: TablerIcons.link_off,
          title: 'Stylist not found',
          message: 'This booking link doesn\'t exist any more. Check the spelling or browse other stylists.',
          actionLabel: 'Browse stylists',
          onAction: () => context.go('/browse'),
        ),
      );
    }
    return ProviderPublicProfileScreen(providerId: _providerId!);
  }
}
