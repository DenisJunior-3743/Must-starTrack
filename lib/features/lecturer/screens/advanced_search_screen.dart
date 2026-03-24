// lib/features/lecturer/screens/advanced_search_screen.dart
//
// MUST StarTrack — Advanced Student Search (Lecturer)
//
// Multi-filter search: query text, faculty, specific skill.
// Results show student cards with profile links.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/router/route_names.dart';
import '../../../data/models/user_model.dart';
import '../bloc/lecturer_cubit.dart';

class AdvancedSearchScreen extends StatefulWidget {
  const AdvancedSearchScreen({super.key});

  @override
  State<AdvancedSearchScreen> createState() => _AdvancedSearchScreenState();
}

class _AdvancedSearchScreenState extends State<AdvancedSearchScreen> {
  final _queryCtrl = TextEditingController();
  String? _selectedFaculty;
  String? _selectedSkill;
  bool _hasSearched = false;

  static const _faculties = [
    'Computing and Informatics',
    'Science',
    'Engineering',
    'Medicine',
    'Business and Management',
    'Education',
    'Arts and Social Sciences',
  ];

  void _doSearch() {
    final query = _queryCtrl.text.trim();
    if (query.isEmpty && _selectedFaculty == null && _selectedSkill == null) {
      return;
    }
    setState(() => _hasSearched = true);
    context.read<LecturerCubit>().searchStudents(
          query: query.isEmpty ? '' : query,
          faculty: _selectedFaculty,
          skill: _selectedSkill,
        );
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        title: Text(
          'Search Students',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: [
          // ── Search controls ────────────────────────────────────────────
          Container(
            color: isDark ? AppColors.surfaceDark : Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              children: [
                // Search bar
                TextField(
                  controller: _queryCtrl,
                  onSubmitted: (_) => _doSearch(),
                  style: GoogleFonts.plusJakartaSans(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search by name or skill...',
                    hintStyle: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      color: AppColors.textHintLight,
                    ),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.tune, size: 20),
                      onPressed: () => _showFilterSheet(context),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius:
                          BorderRadius.circular(AppDimensions.radiusMd),
                      borderSide: BorderSide(
                        color: isDark
                            ? AppColors.borderDark
                            : AppColors.borderLight,
                      ),
                    ),
                  ),
                ),

                // Active filter chips
                if (_selectedFaculty != null || _selectedSkill != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (_selectedFaculty != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: InputChip(
                            label: Text(
                              _selectedFaculty!,
                              style: GoogleFonts.plusJakartaSans(fontSize: 11),
                            ),
                            onDeleted: () {
                              setState(() => _selectedFaculty = null);
                              if (_hasSearched) _doSearch();
                            },
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      if (_selectedSkill != null)
                        InputChip(
                          label: Text(
                            _selectedSkill!,
                            style: GoogleFonts.plusJakartaSans(fontSize: 11),
                          ),
                          onDeleted: () {
                            setState(() => _selectedSkill = null);
                            if (_hasSearched) _doSearch();
                          },
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ],

                const SizedBox(height: 8),

                // Search button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _doSearch,
                    icon: const Icon(Icons.search, size: 18),
                    label: const Text('Search'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.roleLecturer,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppDimensions.radiusMd),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // ── Results ────────────────────────────────────────────────────
          Expanded(
            child: BlocBuilder<LecturerCubit, LecturerState>(
              builder: (context, state) {
                if (state is LecturerLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state is LecturerError) {
                  return Center(child: Text(state.message));
                }
                if (state is StudentSearchLoaded) {
                  if (state.results.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.person_search_outlined,
                              size: 56,
                              color: AppColors.textSecondaryLight
                                  .withValues(alpha: 0.5)),
                          const SizedBox(height: 12),
                          Text(
                            'No students found',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 14,
                              color: AppColors.textSecondaryLight,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Try adjusting your filters',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: AppColors.textHintLight,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: state.results.length,
                    itemBuilder: (context, index) {
                      return _SearchResultCard(user: state.results[index]);
                    },
                  );
                }

                // Initial state — prompt
                if (!_hasSearched) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.school_outlined,
                            size: 56,
                            color: AppColors.textSecondaryLight
                                .withValues(alpha: 0.5)),
                        const SizedBox(height: 12),
                        Text(
                          'Find talented students',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondaryLight,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Search by name, skill, or faculty',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: AppColors.textHintLight,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showFilterSheet(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final skillCtrl = TextEditingController(text: _selectedSkill);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                  16, 20, 16, MediaQuery.of(ctx).viewInsets.bottom + 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Filters',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: isDark
                          ? AppColors.textPrimaryDark
                          : AppColors.textPrimaryLight,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Faculty dropdown
                  Text(
                    'Faculty',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedFaculty,
                    isExpanded: true,
                    hint: Text('All faculties',
                        style: GoogleFonts.plusJakartaSans(fontSize: 13)),
                    items: _faculties
                        .map((f) => DropdownMenuItem(
                              value: f,
                              child: Text(f,
                                  style: GoogleFonts.plusJakartaSans(fontSize: 13)),
                            ))
                        .toList(),
                    onChanged: (v) {
                      setSheetState(() {});
                      setState(() => _selectedFaculty = v);
                    },
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppDimensions.radiusMd),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Skill filter
                  Text(
                    'Skill',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: skillCtrl,
                    style: GoogleFonts.plusJakartaSans(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'e.g. Flutter, Python, ML',
                      hintStyle: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: AppColors.textHintLight,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(AppDimensions.radiusMd),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Apply button
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () {
                        setState(() {
                          _selectedSkill = skillCtrl.text.trim().isNotEmpty
                              ? skillCtrl.text.trim()
                              : null;
                        });
                        Navigator.pop(ctx);
                        _doSearch();
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.roleLecturer,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text('Apply Filters'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// ── Search result card ────────────────────────────────────────────────────────

class _SearchResultCard extends StatelessWidget {
  final UserModel user;
  const _SearchResultCard({required this.user});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final profile = user.profile;
    final skills = profile?.skills ?? [];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        child: InkWell(
          onTap: () {
            context.push(
              RouteNames.profile.replaceFirst(':userId', user.id),
            );
          },
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
              border: Border.all(
                color: isDark ? AppColors.borderDark : AppColors.borderLight,
              ),
            ),
            child: Row(
              children: [
                // Avatar
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.primaryTint10,
                  backgroundImage: user.photoUrl != null
                      ? NetworkImage(user.photoUrl!)
                      : null,
                  child: user.photoUrl == null
                      ? Text(
                          user.firstName.isNotEmpty
                              ? user.firstName[0].toUpperCase()
                              : '?',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),

                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.displayName ?? user.email,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? AppColors.textPrimaryDark
                              : AppColors.textPrimaryLight,
                        ),
                      ),
                      if (profile?.faculty != null ||
                          profile?.programName != null)
                        Text(
                          profile?.programName ?? profile?.faculty ?? '',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: AppColors.textSecondaryLight,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (skills.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: skills
                              .take(4)
                              .map(
                                (s) => Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryTint10,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    s,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 10,
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),

                // Stats column
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (profile != null && profile.activityStreak > 0) ...[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.local_fire_department,
                              size: 14, color: Colors.orange.shade400),
                          const SizedBox(width: 2),
                          Text(
                            '${profile.activityStreak}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.orange.shade400,
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (profile != null && profile.totalPosts > 0) ...[
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.article_outlined,
                              size: 14, color: AppColors.textHintLight),
                          const SizedBox(width: 2),
                          Text(
                            '${profile.totalPosts}',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              color: AppColors.textHintLight,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),

                const SizedBox(width: 4),
                const Icon(Icons.chevron_right,
                    size: 20, color: AppColors.textHintLight),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

