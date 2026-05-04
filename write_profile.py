content = r"""// lib/features/profile/screens/profile_screen.dart
//
// MUST StarTrack — Student Digital Portfolio (Phase 5 — Glow Redesign)
// Light: #F8FBFF → #ECF3FF  |  Dark: #061845 → #030D27
// PlusJakartaSans, pill buttons, frosted-glass stat cards, glow blobs

import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/router/route_names.dart';
import '../../../core/utils/media_path_utils.dart';
import '../../../data/models/post_model.dart';
import '../../../data/models/user_model.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../bloc/profile_cubit.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Glow blob widget (matches leaderboard / notification-settings pattern)
// ─────────────────────────────────────────────────────────────────────────────

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: 220,
        height: 220,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: color, blurRadius: 80, spreadRadius: 24),
          ],
        ),
      ),
    );
  }
}

bool _isVideoUrl(String url) => isVideoMediaPath(url);

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class ProfileScreen extends StatefulWidget {
  final String? userId;
  const ProfileScreen({super.key, this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin {
  bool _followLoading = false;
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _openEditProfile() async {
    await context.push(RouteNames.editProfile);
    if (!mounted) return;
    await context.read<ProfileCubit>().reload();
  }

  Future<void> _toggleFollow() async {
    final cubit = context.read<ProfileCubit>();
    final current = cubit.state;
    if (current is! ProfileLoaded || current.isOwnProfile || _followLoading) {
      return;
    }
    setState(() => _followLoading = true);
    try {
      await cubit.toggleFollow();
    } finally {
      if (mounted) setState(() => _followLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgTop = isDark ? const Color(0xFF061845) : const Color(0xFFF8FBFF);
    final bgBottom = isDark ? const Color(0xFF030D27) : const Color(0xFFECF3FF);
    final fgPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final pillBg = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.white.withValues(alpha: 0.80);
    final pillBorder = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : const Color(0xFFE2E8F0);

    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) {
        // ── Loading ────────────────────────────────────────────────────────
        if (state is ProfileLoading || state is ProfileInitial) {
          return Scaffold(
            backgroundColor: bgTop,
            body: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [bgTop, bgBottom],
                      ),
                    ),
                  ),
                ),
                const Center(child: CircularProgressIndicator()),
              ],
            ),
          );
        }

        // ── Error ──────────────────────────────────────────────────────────
        if (state is ProfileError) {
          return Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              leading: IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded, color: fgPrimary),
                onPressed: () => context.pop(),
              ),
              title: Text('Profile',
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w700, color: fgPrimary)),
            ),
            body: Stack(
              children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [bgTop, bgBottom],
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppColors.danger.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.error_outline_rounded,
                              size: 48, color: AppColors.danger),
                        ),
                        const SizedBox(height: 16),
                        Text(state.message,
                            style: GoogleFonts.plusJakartaSans(
                                fontSize: 14, color: fgPrimary, height: 1.5),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: () => context
                              .read<ProfileCubit>()
                              .loadProfile(widget.userId),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: Text('Retry',
                              style: GoogleFonts.plusJakartaSans(
                                  fontWeight: FontWeight.w700)),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 28, vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                  AppDimensions.radiusFull),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        // ── Loaded ─────────────────────────────────────────────────────────
        final loaded = state as ProfileLoaded;
        final user = loaded.user;
        final posts = loaded.posts;
        final photoPosts =
            posts.where((p) => p.mediaUrls.any((u) => !_isVideoUrl(u))).toList();
        final videoPosts =
            posts.where((p) => p.mediaUrls.any(_isVideoUrl)).toList();

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [bgTop, bgBottom],
                    ),
                  ),
                ),
              ),
              const Positioned(
                  top: -60,
                  right: -50,
                  child: _GlowBlob(color: Color(0x332563EB))),
              const Positioned(
                  bottom: 120,
                  left: -80,
                  child: _GlowBlob(color: Color(0x221152D4))),
              SafeArea(
                bottom: false,
                child: NestedScrollView(
                  headerSliverBuilder: (_, __) => [
                    SliverAppBar(
                      pinned: true,
                      backgroundColor: Colors.transparent,
                      surfaceTintColor: Colors.transparent,
                      elevation: 0,
                      scrolledUnderElevation: 0,
                      leading: IconButton(
                        icon: Icon(Icons.arrow_back_ios_new_rounded,
                            color: fgPrimary),
                        onPressed: () => context.pop(),
                      ),
                      title: Text(
                        loaded.isOwnProfile ? 'My Profile' : 'Profile',
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700, color: fgPrimary),
                      ),
                      centerTitle: true,
                      actions: [
                        IconButton(
                          icon: Icon(Icons.share_rounded, color: fgPrimary),
                          onPressed: () {},
                          tooltip: 'Share profile',
                        ),
                      ],
                    ),
                    SliverToBoxAdapter(
                      child: _Header(
                        user: user,
                        isOwn: loaded.isOwnProfile,
                        isFollowing: loaded.isFollowing,
                        followLoading: _followLoading,
                        onToggleFollow: _toggleFollow,
                        onEditProfile: _openEditProfile,
                        isDark: isDark,
                        fgPrimary: fgPrimary,
                        pillBg: pillBg,
                        pillBorder: pillBorder,
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: _PortfolioLinks(
                        user: user,
                        pillBg: pillBg,
                        pillBorder: pillBorder,
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: _StatsRow(
                        postsCount: posts.length,
                        collabCount: loaded.collabCount,
                        followerCount: loaded.followerCount,
                        followingCount: loaded.followingCount,
                        isDark: isDark,
                        pillBg: pillBg,
                        pillBorder: pillBorder,
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: _SkillsSection(
                          user: user, isDark: isDark, fgPrimary: fgPrimary),
                    ),
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _TabDelegate(
                        TabBar(
                          controller: _tabCtrl,
                          indicatorColor: AppColors.primary,
                          labelColor: AppColors.primary,
                          unselectedLabelColor: isDark
                              ? Colors.white54
                              : const Color(0xFF94A3B8),
                          indicatorWeight: 2.5,
                          labelStyle: GoogleFonts.plusJakartaSans(
                              fontSize: 12, fontWeight: FontWeight.w700),
                          unselectedLabelStyle: GoogleFonts.plusJakartaSans(
                              fontSize: 12, fontWeight: FontWeight.w500),
                          tabs: const [
                            Tab(
                                text: 'Photos',
                                icon: Icon(Icons.photo_library_outlined,
                                    size: 18)),
                            Tab(
                                text: 'Videos',
                                icon: Icon(
                                    Icons.play_circle_outline_rounded,
                                    size: 18)),
                            Tab(
                                text: 'About',
                                icon: Icon(Icons.person_outline_rounded,
                                    size: 18)),
                          ],
                        ),
                        isDark: isDark,
                        pillBg: pillBg,
                        pillBorder: pillBorder,
                      ),
                    ),
                  ],
                  body: TabBarView(
                    controller: _tabCtrl,
                    children: [
                      _ProjectsGrid(
                        posts: photoPosts,
                        emptyTitle: 'No photos yet',
                        emptySubtitle: 'Published images will appear here.',
                        isDark: isDark,
                      ),
                      _ProjectsGrid(
                        posts: videoPosts,
                        emptyTitle: 'No videos yet',
                        emptySubtitle: 'Published videos will appear here.',
                        preferVideoBadge: true,
                        isDark: isDark,
                      ),
                      _AboutTab(
                          user: user, isDark: isDark, fgPrimary: fgPrimary),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Header
// ─────────────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final UserModel user;
  final bool isOwn;
  final bool isFollowing;
  final bool followLoading;
  final VoidCallback onToggleFollow;
  final VoidCallback onEditProfile;
  final bool isDark;
  final Color fgPrimary;
  final Color pillBg;
  final Color pillBorder;

  const _Header({
    required this.user,
    required this.isOwn,
    required this.isFollowing,
    required this.followLoading,
    required this.onToggleFollow,
    required this.onEditProfile,
    required this.isDark,
    required this.fgPrimary,
    required this.pillBg,
    required this.pillBorder,
  });

  @override
  Widget build(BuildContext context) {
    final fgSecondary =
        isDark ? Colors.white60 : const Color(0xFF64748B);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        children: [
          // Avatar with glow ring
          GestureDetector(
            onTap: isOwn ? onEditProfile : null,
            child: Stack(
              children: [
                Container(
                  width: 116,
                  height: 116,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.28),
                        blurRadius: 24,
                        spreadRadius: 4,
                      ),
                    ],
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.50),
                      width: 2.5,
                    ),
                  ),
                  child: ClipOval(child: _buildAvatar()),
                ),
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2563EB), Color(0xFF1152D4)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isDark
                            ? const Color(0xFF061845)
                            : Colors.white,
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      isOwn
                          ? Icons.camera_alt_rounded
                          : Icons.verified_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Name
          Text(
            _displayName(),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: fgPrimary,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 4),

          // Reg number pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
            ),
            child: Text(
              _regNumber(),
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
                letterSpacing: 0.2,
              ),
            ),
          ),
          const SizedBox(height: 6),

          // Faculty
          Text(
            user.profile?.faculty ??
                'Mbarara University of Science & Technology',
            style: GoogleFonts.plusJakartaSans(
                fontSize: 13, color: fgSecondary),
            textAlign: TextAlign.center,
            maxLines: 2,
          ),
          const SizedBox(height: 18),

          // Action buttons
          if (isOwn) ...[
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onEditProfile,
                    icon: const Icon(Icons.edit_rounded, size: 16),
                    label: Text('Edit Profile',
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700)),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                              AppDimensions.radiusFull)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.push(RouteNames.projects),
                    icon: Icon(Icons.folder_open_rounded,
                        size: 16, color: fgPrimary),
                    label: Text('My Projects',
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w600, color: fgPrimary)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      side: BorderSide(color: pillBorder),
                      backgroundColor: pillBg,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                              AppDimensions.radiusFull)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _confirmLogout(context),
                icon: const Icon(Icons.logout_rounded,
                    size: 17, color: AppColors.danger),
                label: Text('Log out',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600,
                        color: AppColors.danger)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  side: BorderSide(
                      color: AppColors.danger.withValues(alpha: 0.55)),
                  backgroundColor:
                      AppColors.danger.withValues(alpha: 0.06),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                          AppDimensions.radiusFull)),
                ),
              ),
            ),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: followLoading
                      ? Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.primary),
                          ),
                        )
                      : (isFollowing
                          ? OutlinedButton.icon(
                              onPressed: onToggleFollow,
                              icon: const Icon(Icons.check_rounded,
                                  size: 16, color: AppColors.primary),
                              label: Text('Following',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary)),
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 13),
                                side: const BorderSide(
                                    color: AppColors.primary),
                                backgroundColor: AppColors.primary
                                    .withValues(alpha: 0.08),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                        AppDimensions.radiusFull)),
                              ),
                            )
                          : FilledButton.icon(
                              onPressed: onToggleFollow,
                              icon: const Icon(Icons.person_add_rounded,
                                  size: 16),
                              label: Text('Follow',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontWeight: FontWeight.w700)),
                              style: FilledButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                        AppDimensions.radiusFull)),
                              ),
                            )),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.push(
                      RouteNames.chatDetail
                          .replaceFirst(':threadId', user.id),
                      extra: {
                        'peerName': user.displayName ?? user.email,
                        'peerPhotoUrl': user.photoUrl,
                        'isPeerLecturer': user.isLecturer,
                      },
                    ),
                    icon: Icon(Icons.chat_bubble_outline_rounded,
                        size: 16, color: fgPrimary),
                    label: Text('Message',
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w600, color: fgPrimary)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      side: BorderSide(color: pillBorder),
                      backgroundColor: pillBg,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                              AppDimensions.radiusFull)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAvatar() {
    final url = user.photoUrl;
    if (url != null && url.trim().isNotEmpty) {
      if (isLocalMediaPath(url)) {
        return Image.file(File(url),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _initialsWidget());
      }
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        errorWidget: (_, __, ___) => _initialsWidget(),
        placeholder: (_, __) =>
            Container(color: AppColors.primaryTint10),
      );
    }
    return _initialsWidget();
  }

  Widget _initialsWidget() {
    final letter = (user.displayName?.isNotEmpty == true)
        ? user.displayName![0].toUpperCase()
        : (user.email.isNotEmpty ? user.email[0].toUpperCase() : '?');
    return Container(
      color: AppColors.primaryTint10,
      alignment: Alignment.center,
      child: Text(letter,
          style: GoogleFonts.plusJakartaSans(
              fontSize: 42,
              fontWeight: FontWeight.w800,
              color: AppColors.primary)),
    );
  }

  String _displayName() {
    if (user.displayName?.isNotEmpty == true) return user.displayName!;
    if (user.email.isNotEmpty) return user.email.split('@').first;
    return 'Student User';
  }

  String _regNumber() {
    if (user.profile?.regNumber != null) return user.profile!.regNumber!;
    if (user.email.isNotEmpty) {
      final prefix = user.email.split('@').first.toUpperCase();
      return 'MUST/' + prefix.substring(0, prefix.length.clamp(0, 8) as int);
    }
    return 'MUST/STUDENT';
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Log out?',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700)),
        content: Text('You will be returned to the login screen.',
            style: GoogleFonts.plusJakartaSans()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.plusJakartaSans()),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: Text('Log out',
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await sl<AuthCubit>().logout();
      if (context.mounted) context.go(RouteNames.login);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Portfolio links bar
// ─────────────────────────────────────────────────────────────────────────────

class _PortfolioLinks extends StatelessWidget {
  final UserModel user;
  final Color pillBg;
  final Color pillBorder;

  const _PortfolioLinks({
    required this.user,
    required this.pillBg,
    required this.pillBorder,
  });

  @override
  Widget build(BuildContext context) {
    final links = user.profile?.portfolioLinks ?? {};
    final items = <_LinkEntry>[];
    if (links.containsKey('github')) {
      items.add(_LinkEntry(Icons.code_rounded, 'GitHub', links['github']!));
    }
    if (links.containsKey('linkedin')) {
      items.add(
          _LinkEntry(Icons.link_rounded, 'LinkedIn', links['linkedin']!));
    }
    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Container(
        decoration: BoxDecoration(
          color: pillBg,
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          border: Border.all(color: pillBorder),
        ),
        child: Row(
          children: items.asMap().entries.expand((e) {
            final entry = e.value;
            return [
              if (e.key > 0) Container(width: 1, height: 28, color: pillBorder),
              Expanded(
                child: TextButton.icon(
                  onPressed: () async {
                    final uri = Uri.tryParse(entry.url);
                    if (uri != null) await launchUrl(uri);
                  },
                  icon: Icon(entry.icon, size: 17, color: AppColors.primary),
                  label: Text(
                    entry.label.toUpperCase(),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.4,
                      color: AppColors.primary,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ];
          }).toList(),
        ),
      ),
    );
  }
}

class _LinkEntry {
  final IconData icon;
  final String label;
  final String url;
  const _LinkEntry(this.icon, this.label, this.url);
}

// ─────────────────────────────────────────────────────────────────────────────
// Stats row — frosted glass cards
// ─────────────────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final int postsCount;
  final int collabCount;
  final int followerCount;
  final int followingCount;
  final bool isDark;
  final Color pillBg;
  final Color pillBorder;

  const _StatsRow({
    required this.postsCount,
    required this.collabCount,
    required this.followerCount,
    required this.followingCount,
    required this.isDark,
    required this.pillBg,
    required this.pillBorder,
  });

  @override
  Widget build(BuildContext context) {
    final fgPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final fgSecondary = isDark ? Colors.white60 : const Color(0xFF64748B);

    final stats = [
      (postsCount.toString(), 'Projects', Icons.rocket_launch_rounded),
      (collabCount.toString(), 'Collabs', Icons.group_rounded),
      (followerCount.toString(), 'Followers', Icons.people_rounded),
      (followingCount.toString(), 'Following', Icons.person_add_rounded),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Row(
        children: stats.map((s) {
          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding:
                  const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              decoration: BoxDecoration(
                color: pillBg,
                borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                border: Border.all(color: pillBorder),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(s.$3, size: 15, color: AppColors.primary),
                  const SizedBox(height: 4),
                  Text(s.$1,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: fgPrimary)),
                  const SizedBox(height: 2),
                  Text(s.$2,
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: fgSecondary)),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Skills section
// ─────────────────────────────────────────────────────────────────────────────

class _SkillsSection extends StatelessWidget {
  final UserModel user;
  final bool isDark;
  final Color fgPrimary;

  const _SkillsSection({
    required this.user,
    required this.isDark,
    required this.fgPrimary,
  });

  @override
  Widget build(BuildContext context) {
    final skills = user.profile?.skills ?? [];
    if (skills.isEmpty) return const SizedBox.shrink();

    final fgSecondary = isDark ? Colors.white60 : const Color(0xFF64748B);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology_rounded,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: 6),
              Text('Skills and Expertise',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: fgPrimary)),
              const Spacer(),
              Text('${skills.length}',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: fgSecondary)),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: skills.map((skill) {
              return Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.15),
                      const Color(0xFF2563EB).withValues(alpha: 0.08),
                    ],
                  ),
                  borderRadius:
                      BorderRadius.circular(AppDimensions.radiusFull),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.28)),
                ),
                child: Text(skill,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary)),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3-column projects grid
// ─────────────────────────────────────────────────────────────────────────────

class _ProjectsGrid extends StatelessWidget {
  final List<PostModel> posts;
  final String emptyTitle;
  final String emptySubtitle;
  final bool preferVideoBadge;
  final bool isDark;

  const _ProjectsGrid({
    required this.posts,
    required this.emptyTitle,
    required this.emptySubtitle,
    required this.isDark,
    this.preferVideoBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    final fgPrimary = isDark ? Colors.white : const Color(0xFF0F172A);
    final fgSecondary = isDark ? Colors.white60 : const Color(0xFF64748B);

    if (posts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  preferVideoBadge
                      ? Icons.play_circle_outline_rounded
                      : Icons.photo_library_outlined,
                  size: 42,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 14),
              Text(emptyTitle,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: fgPrimary)),
              const SizedBox(height: 6),
              Text(emptySubtitle,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 13, color: fgSecondary),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemCount: posts.length,
      itemBuilder: (ctx, i) =>
          _GridTile(post: posts[i], preferVideoBadge: preferVideoBadge),
    );
  }
}

class _GridTile extends StatelessWidget {
  final PostModel post;
  final bool preferVideoBadge;
  const _GridTile({required this.post, this.preferVideoBadge = false});

  @override
  Widget build(BuildContext context) {
    final previewUrl = _previewUrl(post);
    return GestureDetector(
      onTap: () => context.push('/project/' + post.id),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (previewUrl != null)
            isLocalMediaPath(previewUrl)
                ? Image.file(File(previewUrl),
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const _GridPlaceholder())
                : CachedNetworkImage(
                    imageUrl: previewUrl,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const _GridPlaceholder(),
                    placeholder: (_, __) =>
                        Container(color: AppColors.primaryTint10),
                  )
          else
            _GridPlaceholder(
                isVideo: preferVideoBadge ||
                    post.mediaUrls.any(_isVideoUrl)),
          if (post.mediaUrls.isEmpty)
            Container(
              color: AppColors.primaryTint10,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(6),
              child: Text(
                post.title,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          if (preferVideoBadge)
            Positioned(
              right: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.60),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: const Icon(Icons.play_arrow_rounded,
                    color: Colors.white, size: 14),
              ),
            ),
        ],
      ),
    );
  }

  String? _previewUrl(PostModel post) {
    if (!preferVideoBadge) {
      return post.mediaUrls
          .where((url) => !_isVideoUrl(url))
          .cast<String?>()
          .firstWhere((_) => true, orElse: () => null);
    }
    return null;
  }
}

class _GridPlaceholder extends StatelessWidget {
  final bool isVideo;
  const _GridPlaceholder({this.isVideo = false});

  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.primaryTint10,
        child: Center(
          child: Icon(
            isVideo
                ? Icons.play_circle_outline_rounded
                : Icons.rocket_launch_rounded,
            color: AppColors.primary,
            size: 28,
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// About tab
// ─────────────────────────────────────────────────────────────────────────────

class _AboutTab extends StatelessWidget {
  final UserModel user;
  final bool isDark;
  final Color fgPrimary;

  const _AboutTab({
    required this.user,
    required this.isDark,
    required this.fgPrimary,
  });

  @override
  Widget build(BuildContext context) {
    final fgSecondary = isDark ? Colors.white60 : const Color(0xFF64748B);
    final cardBg = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.white.withValues(alpha: 0.72);
    final cardBorder = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : const Color(0xFFE2E8F0);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        if (user.profile?.bio != null &&
            user.profile!.bio!.isNotEmpty) ...[
          _InfoCard(
            title: 'Bio',
            icon: Icons.format_quote_rounded,
            cardBg: cardBg,
            cardBorder: cardBorder,
            fgPrimary: fgPrimary,
            fgSecondary: fgSecondary,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                user.profile!.bio!,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 14, color: fgPrimary, height: 1.6),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        _InfoCard(
          title: 'Academic Info',
          icon: Icons.school_rounded,
          cardBg: cardBg,
          cardBorder: cardBorder,
          fgPrimary: fgPrimary,
          fgSecondary: fgSecondary,
          child: Column(
            children: [
              _DetailRow(
                label: 'Faculty',
                value: user.profile?.faculty ?? '--',
                icon: Icons.account_balance_rounded,
                fgPrimary: fgPrimary,
                fgSecondary: fgSecondary,
                dividerColor: cardBorder,
              ),
              _DetailRow(
                label: 'Programme',
                value: user.profile?.programName ?? '--',
                icon: Icons.menu_book_rounded,
                fgPrimary: fgPrimary,
                fgSecondary: fgSecondary,
                dividerColor: cardBorder,
              ),
              _DetailRow(
                label: 'Year',
                value: user.profile?.yearOfStudy != null
                    ? 'Year ' + user.profile!.yearOfStudy.toString()
                    : '--',
                icon: Icons.calendar_today_rounded,
                fgPrimary: fgPrimary,
                fgSecondary: fgSecondary,
                dividerColor: cardBorder,
              ),
              _DetailRow(
                label: 'Email',
                value: user.email,
                icon: Icons.email_outlined,
                fgPrimary: fgPrimary,
                fgSecondary: fgSecondary,
                dividerColor: cardBorder,
                isLast: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color cardBg;
  final Color cardBorder;
  final Color fgPrimary;
  final Color fgSecondary;
  final Widget child;

  const _InfoCard({
    required this.title,
    required this.icon,
    required this.cardBg,
    required this.cardBorder,
    required this.fgPrimary,
    required this.fgSecondary,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        border: Border.all(color: cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Icon(icon, size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
                Text(title,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: fgSecondary,
                        letterSpacing: 0.2)),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color fgPrimary;
  final Color fgSecondary;
  final Color dividerColor;
  final bool isLast;

  const _DetailRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.fgPrimary,
    required this.fgSecondary,
    required this.dividerColor,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 15, color: AppColors.primary),
              const SizedBox(width: 8),
              SizedBox(
                width: 88,
                child: Text(label,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: fgSecondary)),
              ),
              Expanded(
                child: Text(value,
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: fgPrimary),
                    overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
        if (!isLast)
          Divider(
              height: 1,
              color: dividerColor,
              indent: 16,
              endIndent: 16),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sticky glass tab bar delegate
// ─────────────────────────────────────────────────────────────────────────────

class _TabDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tab;
  final bool isDark;
  final Color pillBg;
  final Color pillBorder;

  const _TabDelegate(
    this.tab, {
    required this.isDark,
    required this.pillBg,
    required this.pillBorder,
  });

  @override
  double get minExtent => tab.preferredSize.height + 1;
  @override
  double get maxExtent => tab.preferredSize.height + 1;

  @override
  Widget build(BuildContext ctx, double shrink, bool overlaps) {
    return Container(
      decoration: BoxDecoration(
        color: pillBg,
        border: Border(bottom: BorderSide(color: pillBorder)),
      ),
      child: tab,
    );
  }

  @override
  bool shouldRebuild(covariant _TabDelegate old) =>
      old.isDark != isDark || old.pillBg != pillBg;
}
"""
with open('d:/start_track/must_startrack/lib/features/profile/screens/profile_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
print('DONE', len(content))
