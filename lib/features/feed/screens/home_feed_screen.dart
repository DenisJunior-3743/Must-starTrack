// lib/features/feed/screens/home_feed_screen.dart
//
// MUST StarTrack — Home Feed Screen (Phase 3)
//
// Layout (matches ai_recommendations_feed.html exactly):
//   • Sticky header: greeting + notification bell
//   • Horizontal collaborator suggestions strip
//   • Vertical paginated project cards
//   • Infinite scroll with load-more indicator
//   • Filter chips (All / Projects / Opportunities)
//   • Pull-to-refresh
//
// HCI: Progressive disclosure (collaborators above feed),
//      Chunking (sections), Feedback (optimistic likes),
//      Affordance (FAB for creating posts).

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/router/route_names.dart';
import '../../../core/router/route_guards.dart';
import '../../shared/hci_components/post_card.dart';
import '../bloc/feed_cubit.dart';

class HomeFeedScreen extends StatefulWidget {
  const HomeFeedScreen({super.key});

  @override
  State<HomeFeedScreen> createState() => _HomeFeedScreenState();
}

class _HomeFeedScreenState extends State<HomeFeedScreen> {
  final _scrollCtrl = ScrollController();
  FeedCubit? _cubit;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cubit ??= context.read<FeedCubit>();
  }

  void _onScroll() {
    if (_cubit == null) return;
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 300) {
      _cubit!.loadMore();
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = _cubit ?? context.read<FeedCubit>();
    return Scaffold(
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: cubit.refresh,
        child: CustomScrollView(
            controller: _scrollCtrl,
            slivers: [
              // ── Sticky App Bar ───────────────────────────────────────────
              _FeedAppBar(),

              // ── Filter chips ─────────────────────────────────────────────
              SliverToBoxAdapter(child: _FilterChips(cubit: cubit)),

              // ── Collaborator suggestions strip ────────────────────────────
              const SliverToBoxAdapter(child: _CollaboratorStrip()),

              // ── Section header ────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.folder_special_rounded,
                          size: 20, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Projects You Might Like',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.lexend(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      TextButton(
                        onPressed: () => context.push(RouteNames.discover),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        child: Text('View all',
                          style: GoogleFonts.lexend(
                            fontSize: 13, fontWeight: FontWeight.w600,
                            color: AppColors.primary)),
                      ),
                    ],
                  ),
                ),
              ),

              // ── Feed ──────────────────────────────────────────────────────
              BlocBuilder<FeedCubit, FeedState>(
                builder: (ctx, state) {
                  if (state is FeedLoading) {
                    return const SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (state is FeedError) {
                    return SliverFillRemaining(
                      child: _ErrorView(
                        message: state.message,
                        onRetry: cubit.refresh,
                      ),
                    );
                  }
                  if (state is FeedLoaded) {
                    if (state.posts.isEmpty) {
                      return const SliverFillRemaining(child: _EmptyFeed());
                    }
                    return SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (_, i) {
                          if (i == state.posts.length) {
                            return state.isLoadingMore
                                ? const Padding(
                                    padding: EdgeInsets.all(24),
                                    child: Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  )
                                : state.hasMore
                                    ? const SizedBox(height: 80)
                                    : const _EndOfFeed();
                          }
                          final post = state.posts[i];
                          return PostCard(
                            post: post,
                            onTap: () => ctx.push(
                              '${RouteNames.projectDetail}/${post.id}',
                            ),
                            onLike: () => cubit.likePost(post.id),
                            onAuthorTap: () => ctx.push(
                              '${RouteNames.profile}/${post.authorId}',
                            ),
                          );
                        },
                        childCount: state.posts.length + 1,
                      ),
                    );
                  }
                  return const SliverToBoxAdapter(child: SizedBox.shrink());
                },
              ),
            ],
          ),
        ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sticky app bar
// ─────────────────────────────────────────────────────────────────────────────

class _FeedAppBar extends StatelessWidget {
  void _handleLoginTap(BuildContext context) {
    final guards = sl<RouteGuards>();
    if (!guards.isAuthenticated) {
      context.push(RouteNames.login);
      return;
    }

    final role = guards.currentRole;
    if (role == UserRole.superAdmin) {
      context.go(RouteNames.superAdminDashboard);
    } else if (role == UserRole.admin) {
      context.go(RouteNames.adminDashboard);
    } else {
      context.go(RouteNames.home);
    }
  }

  void _handleRegisterTap(BuildContext context) {
    final guards = sl<RouteGuards>();
    if (!guards.isAuthenticated) {
      context.push(RouteNames.registerStep1);
      return;
    }

    final role = guards.currentRole;
    if (role == UserRole.superAdmin) {
      context.go(RouteNames.superAdminDashboard);
    } else if (role == UserRole.admin) {
      context.go(RouteNames.adminDashboard);
    } else {
      context.go(RouteNames.home);
    }
  }

  Future<void> _showAuthEntryModal(BuildContext context) async {
    final guards = sl<RouteGuards>();

    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.border(modalContext),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(Icons.account_circle_outlined, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(
                      guards.isAuthenticated ? 'Session Active' : 'Welcome',
                      style: GoogleFonts.lexend(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  guards.isAuthenticated
                      ? 'You already have an active session. Continue to your main screen.'
                      : 'Sign in if you already have an account, or register to get started.',
                  style: GoogleFonts.lexend(height: 1.35),
                ),
                const SizedBox(height: 16),
                if (!guards.isAuthenticated) ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(modalContext).pop();
                        _handleLoginTap(context);
                      },
                      child: const Text('Login'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.of(modalContext).pop();
                        _handleRegisterTap(context);
                      },
                      child: const Text('Register'),
                    ),
                  ),
                ] else ...[
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.of(modalContext).pop();
                        _handleLoginTap(context);
                      },
                      child: const Text('Continue'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      floating: true,
      snap: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.92),
      elevation: 0,
      titleSpacing: 0,
      flexibleSpace: FlexibleSpaceBar(
        background: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          const Icon(Icons.auto_awesome_rounded,
                              size: 18, color: AppColors.primary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Recommended for You',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.lexend(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      constraints: const BoxConstraints.tightFor(
                        width: 34,
                        height: 34,
                      ),
                      padding: EdgeInsets.zero,
                      iconSize: 19,
                      icon: const Icon(Icons.notifications_outlined),
                      onPressed: () => context.push(RouteNames.notifications),
                      tooltip: 'Notifications',
                    ),
                    IconButton(
                      constraints: const BoxConstraints.tightFor(
                        width: 34,
                        height: 34,
                      ),
                      padding: EdgeInsets.zero,
                      iconSize: 19,
                      icon: const Icon(Icons.account_circle_outlined),
                      onPressed: () => _showAuthEntryModal(context),
                      tooltip: 'Account',
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text('Hi there 👋',
                  style: GoogleFonts.lexend(
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  )),
                Text(
                  'Based on your research interests and skills',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.lexend(
                    fontSize: 12,
                    color: AppColors.textSecondaryLight,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      expandedHeight: 128,
      collapsedHeight: 60,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter chips
// ─────────────────────────────────────────────────────────────────────────────

class _FilterChips extends StatelessWidget {
  final FeedCubit cubit;
  const _FilterChips({required this.cubit});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<FeedCubit, FeedState>(
      builder: (_, state) {
        final current = state is FeedLoaded ? state.filter : const FeedFilter();
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              _Chip(
                label: 'All',
                active: current.type == null,
                onTap: () => cubit.applyFilter(current.copyWith(clearType: true)),
              ),
              _Chip(
                label: 'Projects',
                active: current.type == 'project',
                onTap: () => cubit.applyFilter(current.copyWith(type: 'project')),
              ),
              _Chip(
                label: 'Opportunities',
                active: current.type == 'opportunity',
                onTap: () => cubit.applyFilter(current.copyWith(type: 'opportunity')),
              ),
              if (current.isActive)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ActionChip(
                    label: const Text('Clear'),
                    avatar: const Icon(Icons.close, size: 14),
                    onPressed: cubit.clearFilters,
                    backgroundColor: AppColors.danger.withValues(alpha: 0.10),
                    labelStyle: GoogleFonts.lexend(
                      fontSize: 12, color: AppColors.danger,
                      fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _Chip({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: active,
        onSelected: (_) => onTap(),
        selectedColor: AppColors.primary,
        labelStyle: GoogleFonts.lexend(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: active ? Colors.white : AppColors.textSecondaryLight,
        ),
        backgroundColor: Theme.of(context).cardColor,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
          side: BorderSide(
            color: active ? AppColors.primary : AppColors.borderLight,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Collaborator suggestions horizontal strip
// ─────────────────────────────────────────────────────────────────────────────

class _CollaboratorStrip extends StatelessWidget {
  const _CollaboratorStrip();

 
  static const _placeholders = [
    ('Elena V.', 'Python'),
    ('Marcus C.', 'Data Viz'),
    ('Julian H.', 'ML'),
    ('Sia P.', 'Stats'),
    ('Omar K.', 'Flutter'),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Row(
            children: [
              const Icon(Icons.group_add_rounded, size: 20, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('Potential Collaborators',
                style: GoogleFonts.lexend(
                  fontSize: 17, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        SizedBox(
          height: 140,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _placeholders.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              final (name, skill) = _placeholders[i];
              return _CollaboratorCard(name: name, skill: skill);
            },
          ),
        ),
      ],
    );
  }
}

class _CollaboratorCard extends StatelessWidget {
  final String name;
  final String skill;

  const _CollaboratorCard({required this.name, required this.skill});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 120,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        border: Border.all(
          color: isDark ? AppColors.borderDark : AppColors.borderLight,
          width: 0.8,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.primaryTint10,
            child: Text(
              name[0],
              style: GoogleFonts.lexend(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(name,
            style: GoogleFonts.lexend(fontSize: 12, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primaryTint10,
              borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
            ),
            child: Text(skill,
              style: GoogleFonts.lexend(
                fontSize: 9, fontWeight: FontWeight.w600, color: AppColors.primary),
              maxLines: 1),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Utility widgets
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyFeed extends StatelessWidget {
  const _EmptyFeed();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.search_off_rounded, size: 64, color: AppColors.primary),
                    const SizedBox(height: 16),
                    Text(
                      'No posts yet',
                      style: GoogleFonts.lexend(fontSize: 18, fontWeight: FontWeight.w700),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Be the first to share a project!',
                      style: GoogleFonts.lexend(
                        fontSize: 14,
                        color: AppColors.textSecondaryLight,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      physics: const AlwaysScrollableScrollPhysics(),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 56, color: AppColors.danger),
              const SizedBox(height: 16),
              Text('Could not load feed', style: GoogleFonts.lexend(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                message,
                style: GoogleFonts.lexend(fontSize: 12, color: AppColors.textSecondaryLight),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EndOfFeed extends StatelessWidget {
  const _EndOfFeed();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Text("You're all caught up! ✨",
          style: GoogleFonts.lexend(
            fontSize: 14, color: AppColors.textSecondaryLight)),
      ),
    );
  }
}
