// lib/features/profile/screens/profile_screen.dart
//
// MUST StarTrack â€” Student Digital Portfolio (Phase 4)
//
// Matches student_digital_portfolio.html exactly:
//   â€¢ Large avatar (128dp) + verified badge overlay
//   â€¢ Student ID, display name, faculty label
//   â€¢ Edit Profile + Settings (own profile) OR Follow + Message (others)
//   â€¢ Portfolio links bar: GitHub | LinkedIn
//   â€¢ Stats row: Projects | Collabs | Followers | Following
//   â€¢ Skills & Expertise chip grid
//   â€¢ 3-column Instagram-style project grid (tap â†’ project detail)
//   â€¢ About tab with bio, programme, year info
//
// HCI:
//   â€¢ Chunking: header â†’ links â†’ stats â†’ skills â†’ grid (F-pattern)
//   â€¢ Affordance: verified badge, follow button shape/colour
//   â€¢ Visibility: online badge, activity streak (Phase 5)
//   â€¢ Universal Design: 48dp touch targets, semantic labels

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/router/route_names.dart';
import '../../../core/utils/media_path_utils.dart';
import '../../../data/models/post_model.dart';
import '../../../data/models/user_model.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../bloc/profile_cubit.dart';

class ProfileScreen extends StatefulWidget {
  final String? userId; // null = own profile
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
    return BlocBuilder<ProfileCubit, ProfileState>(
      builder: (context, state) {
        if (state is ProfileLoading || state is ProfileInitial) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (state is ProfileError) {
          return Scaffold(
            appBar: AppBar(title: const Text('StarTrack Profile')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline_rounded,
                      size: 48,
                      color: AppColors.danger,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      state.message,
                      style: GoogleFonts.plusJakartaSans(fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => context.read<ProfileCubit>().loadProfile(widget.userId),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final loaded = state as ProfileLoaded;
        final user = loaded.user;
        final posts = loaded.posts;
        final photoPosts = posts
            .where((post) => post.mediaUrls.any((url) => !_isVideoUrl(url)))
            .toList();
        final videoPosts =
            posts.where((post) => post.mediaUrls.any(_isVideoUrl)).toList();

        return Scaffold(
          body: NestedScrollView(
            headerSliverBuilder: (_, __) => [
              SliverAppBar(
                pinned: true,
                title: Text(loaded.isOwnProfile ? 'My Profile' : 'Profile'),
                centerTitle: true,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.share_rounded),
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
                ),
              ),
              SliverToBoxAdapter(child: _PortfolioLinks(user: user)),
              SliverToBoxAdapter(
                child: _StatsRow(
                  postsCount: posts.length,
                  collabCount: loaded.collabCount,
                  followerCount: loaded.followerCount,
                  followingCount: loaded.followingCount,
                ),
              ),
              SliverToBoxAdapter(child: _SkillsSection(user: user)),
              SliverPersistentHeader(
                pinned: true,
                delegate: _TabDelegate(
                  TabBar(
                    controller: _tabCtrl,
                    indicatorColor: AppColors.primary,
                    labelColor: AppColors.primary,
                    unselectedLabelColor: AppColors.textSecondaryLight,
                    tabs: const [
                      Tab(text: 'Photos', icon: Icon(Icons.photo_library_outlined)),
                      Tab(
                        text: 'Videos',
                        icon: Icon(Icons.play_circle_outline_rounded),
                      ),
                      Tab(text: 'About', icon: Icon(Icons.person_outline_rounded)),
                    ],
                  ),
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
                ),
                _ProjectsGrid(
                  posts: videoPosts,
                  emptyTitle: 'No videos yet',
                  emptySubtitle: 'Published videos will appear here.',
                  preferVideoBadge: true,
                ),
                _AboutTab(user: user),
              ],
            ),
          ),
        );
      },
    );
  }
}

bool _isVideoUrl(String url) {
  return isVideoMediaPath(url);
}

// â”€â”€ Header â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _Header extends StatelessWidget {
  final UserModel user;
  final bool isOwn;
  final bool isFollowing;
  final bool followLoading;
  final VoidCallback onToggleFollow;
  final VoidCallback onEditProfile;
  const _Header({
    required this.user,
    required this.isOwn,
    required this.isFollowing,
    required this.followLoading,
    required this.onToggleFollow,
    required this.onEditProfile,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      child: Column(
        children: [
          // Avatar + verified badge / edit overlay
          GestureDetector(
            onTap: isOwn ? onEditProfile : null,
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 52,
                  backgroundColor: AppColors.primaryTint10,
                  backgroundImage: user.photoUrl != null
                      ? CachedNetworkImageProvider(user.photoUrl!)
                      : null,
                  child: user.photoUrl == null
                      ? Text(
                          (user.displayName?.isNotEmpty == true)
                              ? user.displayName![0].toUpperCase()
                              : '?',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 40,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary))
                      : null,
                ),
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Icon(
                        isOwn
                            ? Icons.camera_alt_rounded
                            : Icons.verified_rounded,
                        size: 16,
                        color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Name - fallback to email prefix if displayName is empty
          Text(
              (user.displayName?.isNotEmpty == true)
                  ? user.displayName!
                  : (user.email.isNotEmpty
                      ? user.email.split('@').first
                      : 'Student User'),
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3)),
          const SizedBox(height: 2),

          // Student ID from profile - show regNumber or derive from email
          Text(
              user.profile?.regNumber ??
                  (user.email.isNotEmpty
                      ? 'MUST/${user.email.split('@').first.substring(0, 6).toUpperCase()}'
                      : 'Student'),
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary)),
          const SizedBox(height: 2),

          // Faculty
          Text(
              user.profile?.faculty ??
                  'Mbarara University of Science & Technology',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 13, color: AppColors.textSecondaryLight),
              textAlign: TextAlign.center,
              maxLines: 2),
          const SizedBox(height: 16),

          // Action buttons
          Row(
            children: isOwn
                ? [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: onEditProfile,
                        child: Text('Edit Profile',
                            style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => context.push(RouteNames.projects),
                        icon: const Icon(Icons.folder_open_rounded, size: 16),
                        label: Text('My Projects',
                            style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ]
                : [
                    Expanded(
                      child: followLoading
                          ? const Center(
                              child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2)))
                          : ElevatedButton(
                              onPressed: onToggleFollow,
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    isFollowing ? Colors.transparent : null,
                                foregroundColor:
                                    isFollowing ? AppColors.primary : null,
                                side: isFollowing
                                    ? const BorderSide(color: AppColors.primary)
                                    : null,
                              ),
                              child: Text(isFollowing ? 'Following' : 'Follow',
                                  style: GoogleFonts.plusJakartaSans(
                                      fontWeight: FontWeight.w700)),
                            ),
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
                        icon: const Icon(Icons.chat_bubble_outline_rounded,
                            size: 16),
                        label: Text('Message',
                            style: GoogleFonts.plusJakartaSans(
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
          ),
          if (isOwn) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Log out?'),
                      content: const Text(
                          'You will be returned to the login screen.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          style: FilledButton.styleFrom(
                              backgroundColor: AppColors.danger),
                          child: const Text('Log out'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true) {
                    await sl<AuthCubit>().logout();
                    if (context.mounted) context.go(RouteNames.login);
                  }
                },
                icon: const Icon(Icons.logout_rounded,
                    size: 18, color: AppColors.danger),
                label: Text('Log out',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w600, color: AppColors.danger)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.danger),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// â”€â”€ Portfolio links bar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _PortfolioLinks extends StatelessWidget {
  final UserModel user;
  const _PortfolioLinks({required this.user});

  @override
  Widget build(BuildContext context) {
    final links = user.profile?.portfolioLinks ?? {};
    if (links.isEmpty) return const SizedBox.shrink();

    final items = <_LinkEntry>[];
    if (links.containsKey('github')) {
      items.add(_LinkEntry(Icons.code_rounded, 'GitHub', links['github']!));
    }
    if (links.containsKey('linkedin')) {
      items.add(_LinkEntry(Icons.link_rounded, 'LinkedIn', links['linkedin']!));
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return Container(
      decoration: const BoxDecoration(
          color: AppColors.surfaceLight,
          border: Border.symmetric(
              horizontal: BorderSide(color: AppColors.borderLight))),
      child: Row(
        children: items.asMap().entries.expand((e) {
          final entry = e.value;
          return [
            if (e.key > 0)
              Container(width: 1, height: 28, color: AppColors.borderLight),
            Expanded(
              child: TextButton.icon(
                onPressed: () async {
                  final uri = Uri.tryParse(entry.url);
                  if (uri != null) await launchUrl(uri);
                },
                icon: Icon(entry.icon, size: 18),
                label: Text(entry.label.toUpperCase(),
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.1)),
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    foregroundColor: AppColors.textSecondaryLight),
              ),
            ),
          ];
        }).toList(),
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

// â”€â”€ Stats row â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _StatsRow extends StatelessWidget {
  final int postsCount;
  final int collabCount;
  final int followerCount;
  final int followingCount;
  const _StatsRow({
    required this.postsCount,
    required this.collabCount,
    required this.followerCount,
    required this.followingCount,
  });

  @override
  Widget build(BuildContext context) {
    final stats = [
      (postsCount.toString(), 'Projects'),
      (collabCount.toString(), 'Collabs'),
      (followerCount.toString(), 'Followers'),
      (followingCount.toString(), 'Following'),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: stats
            .map((s) => Expanded(
                  child: Column(
                    children: [
                      Text(s.$1,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(s.$2,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              color: AppColors.textSecondaryLight)),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }
}

// â”€â”€ Skills section â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _SkillsSection extends StatelessWidget {
  final UserModel user;
  const _SkillsSection({required this.user});

  @override
  Widget build(BuildContext context) {
    final skills = user.profile?.skills ?? [];
    if (skills.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Skills & Expertise',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 17, fontWeight: FontWeight.w700)),
              const Spacer(),
              const Icon(Icons.psychology_rounded,
                  size: 22, color: AppColors.primary),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: skills
                .map((s) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.primaryTint10,
                        borderRadius:
                            BorderRadius.circular(AppDimensions.radiusSm),
                      ),
                      child: Text(s,
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary)),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

// â”€â”€ 3-column projects grid â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _ProjectsGrid extends StatelessWidget {
  final List<PostModel> posts;
  final String emptyTitle;
  final String emptySubtitle;
  final bool preferVideoBadge;

  const _ProjectsGrid({
    required this.posts,
    required this.emptyTitle,
    required this.emptySubtitle,
    this.preferVideoBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              preferVideoBadge
                  ? Icons.play_circle_outline_rounded
                  : Icons.photo_library_outlined,
              size: 60,
              color: AppColors.primary,
            ),
            const SizedBox(height: 12),
            Text(emptyTitle,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(emptySubtitle,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13, color: AppColors.textSecondaryLight)),
          ],
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
      onTap: () => context.push('/project/${post.id}'),
      child: Stack(
        fit: StackFit.expand,
        children: [
          previewUrl != null
              ? isLocalMediaPath(previewUrl)
                  ? Image.file(
                      File(previewUrl),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const _GridPlaceholder(),
                    )
                  : CachedNetworkImage(
                      imageUrl: previewUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const _GridPlaceholder(),
                      placeholder: (_, __) => Container(
                        color: AppColors.primaryTint10,
                      ),
                    )
              : _GridPlaceholder(
                  isVideo: preferVideoBadge || post.mediaUrls.any(_isVideoUrl)),
          if (preferVideoBadge)
            Positioned(
              right: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 14,
                ),
              ),
            ),
          // Subtle overlay so text projects are still identifiable
          if (post.mediaUrls.isEmpty)
            Container(
              color: AppColors.primaryTint10,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(4),
              child: Text(post.title,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center),
            ),
        ],
      ),
    );
  }

  String? _previewUrl(PostModel post) {
    if (!preferVideoBadge) {
      final imageUrl = post.mediaUrls
          .where((url) => !_isVideoUrl(url))
          .cast<String?>()
          .firstWhere(
            (_) => true,
            orElse: () => null,
          );
      return imageUrl;
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

// â”€â”€ About tab â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _AboutTab extends StatelessWidget {
  final UserModel user;
  const _AboutTab({required this.user});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (user.profile?.bio != null) ...[
          Text('Bio',
              style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondaryLight)),
          const SizedBox(height: 6),
          Text(user.profile!.bio!,
              style: GoogleFonts.plusJakartaSans(fontSize: 14, height: 1.6)),
          const SizedBox(height: 16),
        ],
        _Row('Faculty', user.profile?.faculty ?? '—'),
        _Row('Programme', user.profile?.programName ?? '—'),
        _Row(
            'Year of Study',
            user.profile?.yearOfStudy != null
                ? 'Year ${user.profile!.yearOfStudy}'
                : '—'),
        _Row('Email', user.email),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondaryLight)),
          ),
          Expanded(
              child: Text(value,
                  style: GoogleFonts.plusJakartaSans(fontSize: 13))),
        ],
      ),
    );
  }
}

// â”€â”€ Persistent tab bar delegate â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _TabDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tab;
  const _TabDelegate(this.tab);

  @override
  double get minExtent => tab.preferredSize.height;
  @override
  double get maxExtent => tab.preferredSize.height;

  @override
  Widget build(BuildContext ctx, double shrink, bool overlaps) =>
      Container(color: Theme.of(ctx).scaffoldBackgroundColor, child: tab);

  @override
  bool shouldRebuild(covariant SliverPersistentHeaderDelegate old) => false;
}
