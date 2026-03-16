// lib/features/discover/screens/guest_discover_screen.dart
//
// MUST StarTrack — Guest Discover Screen
//
// Shows the discover feed in read-only mode.
// Interaction actions (like, collaborate) trigger a login nudge.
// HCI: clear affordance of limited state via banner + locked icons.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/router/route_names.dart';
import '../../../data/local/dao/post_dao.dart';
import '../../../data/models/post_model.dart';
import '../../shared/hci_components/post_card.dart';
import '../../shared/hci_components/st_form_widgets.dart';

class GuestDiscoverScreen extends StatefulWidget {
  const GuestDiscoverScreen({super.key});

  @override
  State<GuestDiscoverScreen> createState() => _GuestDiscoverScreenState();
}

class _GuestDiscoverScreenState extends State<GuestDiscoverScreen> {
  final _dao = PostDao();
  List<PostModel> _posts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final posts = await _dao.getFeedPage(pageSize: 15);
      setState(() { _posts = posts; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  void _showLoginNudge() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _LoginNudgeSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            title: Row(
              children: [
                const Icon(Icons.rocket_launch_rounded,
                    color: AppColors.primary, size: 22),
                const SizedBox(width: 8),
                Text('MUST StarTrack',
                  style: GoogleFonts.lexend(
                    fontWeight: FontWeight.w700, color: AppColors.primary)),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => context.go(RouteNames.login),
                child: Text('Sign In',
                  style: GoogleFonts.lexend(
                    fontWeight: FontWeight.w700, color: AppColors.primary)),
              ),
            ],
          ),

          // Guest banner
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.primary.withBlue(200)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_open_rounded, color: Colors.white, size: 36),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('You\'re browsing as a Guest',
                          style: GoogleFonts.lexend(
                            color: Colors.white, fontWeight: FontWeight.w700,
                            fontSize: 14)),
                        Text('Sign in to like, follow and collaborate.',
                          style: GoogleFonts.lexend(
                            color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.go(RouteNames.login),
                    style: TextButton.styleFrom(
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppDimensions.radiusSm)),
                    ),
                    child: Text('Join',
                      style: GoogleFonts.lexend(
                        fontSize: 13, fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
                  ),
                ],
              ),
            ),
          ),

          if (_loading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()))
          else if (_posts.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.public_rounded, size: 60, color: AppColors.primary),
                    const SizedBox(height: 16),
                    Text('No public posts yet.',
                      style: GoogleFonts.lexend(fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => context.go(RouteNames.login),
                      child: const Text('Sign in to see all content →'),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => PostCard(
                  post: _posts[i],
                  onTap: () => _showLoginNudge(),
                  onLike: () => _showLoginNudge(),
                  onAuthorTap: () => _showLoginNudge(),
                ),
                childCount: _posts.length,
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Login nudge bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _LoginNudgeSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderLight,
                borderRadius: BorderRadius.circular(AppDimensions.radiusFull)),
            ),
            const SizedBox(height: 20),
            const Icon(Icons.lock_rounded, size: 48, color: AppColors.primary),
            const SizedBox(height: 12),
            Text('Join MUST StarTrack',
              style: GoogleFonts.lexend(
                fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
            const SizedBox(height: 8),
            Text(
              'Sign in with your MUST email to like posts, follow students, send collaboration requests and more.',
              style: GoogleFonts.lexend(
                fontSize: 14, color: AppColors.textSecondaryLight, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            StButton(
              label: 'Sign In',
              trailingIcon: Icons.arrow_forward_rounded,
              onPressed: () {
                Navigator.pop(context);
                context.go(RouteNames.login);
              },
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Continue Browsing',
                style: GoogleFonts.lexend(
                  fontSize: 13, color: AppColors.textSecondaryLight)),
            ),
          ],
        ),
      ),
    );
  }
}
