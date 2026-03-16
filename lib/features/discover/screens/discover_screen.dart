// lib/features/discover/screens/discover_screen.dart
//
// MUST StarTrack — Discover Screen (Phase 3)
//
// Matches search_discovery_filters.html exactly:
//   • Sticky search bar with filter button
//   • Recent searches pills (stored locally)
//   • Trending skills horizontal scroll (icon + label)
//   • Advanced filter panel: faculty, program, category grid, skill chips, recency
//   • Results list (PostCard) with live debounced search
//
// HCI:
//   • Recognition over Recall: recent searches shown before user types
//   • Progressive disclosure: advanced filters hidden until needed
//   • Feedback: debounced search starts immediately on type

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

class DiscoverScreen extends StatefulWidget {
  const DiscoverScreen({super.key});

  @override
  State<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends State<DiscoverScreen> {
  final _searchCtrl = TextEditingController();
  final _postDao = PostDao();

  List<PostModel> _results = [];
  bool _loading = false;
  bool _showFilters = false;

  // Filter state
  String? _filterFaculty;
  String? _filterCategory;
  String _filterRecency = 'any';
  List<String> _filterSkills = [];

  // Recent searches (would persist via SharedPreferences in Phase 4)
  List<String> _recentSearches = ['AI Ethics', 'Blockchain Research', 'Flutter'];

  static const _trendingSkills = [
    ('AI/ML', Icons.psychology_rounded, Color(0xFF1152D4)),
    ('Flutter', Icons.flutter_dash, Color(0xFF4F46E5)),
    ('Blockchain', Icons.currency_bitcoin, Color(0xFF059669)),
    ('Data Sci', Icons.storage_rounded, Color(0xFFEA580C)),
    ('Cyber', Icons.security_rounded, Color(0xFFDC2626)),
    ('Cloud', Icons.cloud_queue_rounded, Color(0xFF0284C7)),
  ];

  static const _categories = ['Research', 'Mobile App', 'Hardware', 'Data Analysis',
    'Innovation', 'Software'];

  static const _faculties = [
    'Computing & IT', 'Engineering', 'Business Management',
    'Applied Sciences', 'Medicine',
  ];

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    setState(() => _loading = true);
    try {
      final results = await _postDao.searchPosts(
        query: query,
        faculty: _filterFaculty,
        category: _filterCategory,
        skills: _filterSkills,
        recency: _filterRecency,
        pageSize: 30,
      );
      setState(() { _results = results; _loading = false; });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  void _onQueryChanged(String q) {
    if (q.length < 2 && q.isNotEmpty) return;
    _search(q);
  }

  void _addRecentSearch(String q) {
    if (q.trim().isEmpty) return;
    setState(() {
      _recentSearches.remove(q);
      _recentSearches.insert(0, q);
      if (_recentSearches.length > 8) _recentSearches = _recentSearches.take(8).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── Sticky search header ────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            floating: true,
            snap: true,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.95),
            elevation: 0,
            expandedHeight: 110,
            flexibleSpace: FlexibleSpaceBar(
              background: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('Discover',
                            style: GoogleFonts.lexend(
                              fontSize: 24, fontWeight: FontWeight.w700,
                              color: AppColors.primary, letterSpacing: -0.3)),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.notifications_outlined),
                            onPressed: () => context.push(RouteNames.notifications),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _searchCtrl,
                              onChanged: _onQueryChanged,
                              onSubmitted: (q) {
                                _addRecentSearch(q);
                                _search(q);
                              },
                              decoration: InputDecoration(
                                hintText: 'Search projects, skills, or students',
                                hintStyle: GoogleFonts.lexend(fontSize: 13),
                                prefixIcon: const Icon(Icons.search_rounded),
                                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Filter toggle button
                          Material(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                            child: InkWell(
                              onTap: () => setState(() => _showFilters = !_showFilters),
                              borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                              child: Container(
                                width: 48, height: 48,
                                alignment: Alignment.center,
                                child: Icon(
                                  _showFilters ? Icons.tune_rounded : Icons.tune_rounded,
                                  color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Body ────────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Recent searches
                if (_searchCtrl.text.isEmpty && _recentSearches.isNotEmpty)
                  _RecentSearches(
                    items: _recentSearches,
                    onTap: (q) {
                      _searchCtrl.text = q;
                      _search(q);
                    },
                    onClear: () => setState(() => _recentSearches.clear()),
                  ),

                // Trending skills
                if (_searchCtrl.text.isEmpty)
                  _TrendingSkills(
                    skills: _trendingSkills,
                    onTap: (skill) {
                      _searchCtrl.text = skill;
                      _search(skill);
                    },
                  ),

                // Advanced filter panel
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  child: _showFilters
                    ? _AdvancedFilters(
                        faculties: _faculties,
                        categories: _categories,
                        selectedFaculty: _filterFaculty,
                        selectedCategory: _filterCategory,
                        selectedRecency: _filterRecency,
                        selectedSkills: _filterSkills,
                        onFacultyChanged: (v) => setState(() => _filterFaculty = v),
                        onCategoryChanged: (v) => setState(() {
                          _filterCategory = _filterCategory == v ? null : v;
                        }),
                        onRecencyChanged: (v) => setState(() => _filterRecency = v),
                        onSkillsChanged: (v) => setState(() => _filterSkills = v),
                        onApply: () {
                          setState(() => _showFilters = false);
                          _search(_searchCtrl.text);
                        },
                      )
                    : const SizedBox.shrink(),
                ),

                // Results header
                if (_results.isNotEmpty || _loading)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.grid_view_rounded,
                            size: 18, color: AppColors.primary),
                        const SizedBox(width: 8),
                        Text(_loading ? 'Searching…' : '${_results.length} results',
                          style: GoogleFonts.lexend(
                            fontSize: 14, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // ── Results ──────────────────────────────────────────────────────
          if (_loading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_results.isEmpty && _searchCtrl.text.isNotEmpty)
            SliverFillRemaining(child: _EmptyResults(query: _searchCtrl.text))
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) {
                  final post = _results[i];
                  return PostCard(
                    post: post,
                    onTap: () => context.push('${RouteNames.projectDetail}/${post.id}'),
                    onAuthorTap: () => context.push('${RouteNames.profile}/${post.authorId}'),
                  );
                },
                childCount: _results.length,
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Recent searches
// ─────────────────────────────────────────────────────────────────────────────

class _RecentSearches extends StatelessWidget {
  final List<String> items;
  final ValueChanged<String> onTap;
  final VoidCallback onClear;

  const _RecentSearches({
    required this.items,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
          child: Row(
            children: [
              Text('RECENT SEARCHES',
                style: GoogleFonts.lexend(
                  fontSize: 11, fontWeight: FontWeight.w700,
                  color: AppColors.textSecondaryLight, letterSpacing: 0.08)),
              const Spacer(),
              TextButton(
                onPressed: onClear,
                child: Text('Clear All',
                  style: GoogleFonts.lexend(
                    fontSize: 12, fontWeight: FontWeight.w600,
                    color: AppColors.primary)),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8, runSpacing: 8,
            children: items.map((q) => GestureDetector(
              onTap: () => onTap(q),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.history_rounded, size: 14,
                        color: AppColors.textSecondaryLight),
                    const SizedBox(width: 6),
                    Text(q, style: GoogleFonts.lexend(fontSize: 13, fontWeight: FontWeight.w500)),
                  ],
                ),
              ),
            )).toList(),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Trending skills
// ─────────────────────────────────────────────────────────────────────────────

class _TrendingSkills extends StatelessWidget {
  final List<(String, IconData, Color)> skills;
  final ValueChanged<String> onTap;

  const _TrendingSkills({required this.skills, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Text('TRENDING SKILLS',
            style: GoogleFonts.lexend(
              fontSize: 11, fontWeight: FontWeight.w700,
              color: AppColors.textSecondaryLight, letterSpacing: 0.08)),
        ),
        SizedBox(
          height: 90,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: skills.length,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: (_, i) {
              final (label, icon, color) = skills[i];
              return GestureDetector(
                onTap: () => onTap(label),
                child: Column(
                  children: [
                    Container(
                      width: 56, height: 56,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(icon, color: color, size: 28),
                    ),
                    const SizedBox(height: 6),
                    Text(label,
                      style: GoogleFonts.lexend(
                        fontSize: 10, fontWeight: FontWeight.w600)),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Advanced filter panel
// ─────────────────────────────────────────────────────────────────────────────

class _AdvancedFilters extends StatelessWidget {
  final List<String> faculties;
  final List<String> categories;
  final String? selectedFaculty;
  final String? selectedCategory;
  final String selectedRecency;
  final List<String> selectedSkills;
  final ValueChanged<String?> onFacultyChanged;
  final ValueChanged<String> onCategoryChanged;
  final ValueChanged<String> onRecencyChanged;
  final ValueChanged<List<String>> onSkillsChanged;
  final VoidCallback onApply;

  const _AdvancedFilters({
    required this.faculties,
    required this.categories,
    required this.selectedFaculty,
    required this.selectedCategory,
    required this.selectedRecency,
    required this.selectedSkills,
    required this.onFacultyChanged,
    required this.onCategoryChanged,
    required this.onRecencyChanged,
    required this.onSkillsChanged,
    required this.onApply,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Advanced Filters',
                style: GoogleFonts.lexend(fontSize: 16, fontWeight: FontWeight.w700)),
              const Spacer(),
              const Icon(Icons.expand_less_rounded, color: AppColors.textSecondaryLight),
            ],
          ),
          const SizedBox(height: 20),

          // Faculty
          const _FilterLabel('Faculty'),
          DropdownButtonFormField<String?>(
            // ignore: deprecated_member_use
            initialValue: selectedFaculty,
            decoration: const InputDecoration(contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
            items: [
              const DropdownMenuItem(value: null, child: Text('All faculties')),
              ...faculties.map((f) => DropdownMenuItem(value: f, child: Text(f))),
            ],
            onChanged: onFacultyChanged,
          ),
          const SizedBox(height: 16),

          // Category grid
          const _FilterLabel('Project Category'),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: categories.map((cat) {
              final active = selectedCategory == cat;
              return GestureDetector(
                onTap: () => onCategoryChanged(cat),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: active ? AppColors.primaryTint10 : Colors.transparent,
                    border: Border.all(
                      color: active ? AppColors.primary : AppColors.borderLight),
                    borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                  ),
                  child: Text(cat,
                    style: GoogleFonts.lexend(
                      fontSize: 12, fontWeight: FontWeight.w600,
                      color: active ? AppColors.primary : AppColors.textSecondaryLight)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Skill requirement
          const _FilterLabel('Skill Requirement'),
          SkillChipInput(
            initialSkills: selectedSkills,
            onChanged: onSkillsChanged,
            label: '',
          ),
          const SizedBox(height: 16),

          // Recency
          const _FilterLabel('Recency'),
          Row(
            children: [
              _RecencyBtn(label: 'Anytime', value: 'any', selected: selectedRecency, onTap: onRecencyChanged),
              const SizedBox(width: 8),
              _RecencyBtn(label: 'Last 30 days', value: 'month', selected: selectedRecency, onTap: onRecencyChanged),
              const SizedBox(width: 8),
              _RecencyBtn(label: 'Last 7 days', value: 'week', selected: selectedRecency, onTap: onRecencyChanged),
            ],
          ),
          const SizedBox(height: 20),

          // Apply
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onApply,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16)),
              child: Text('Apply Filters',
                style: GoogleFonts.lexend(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterLabel extends StatelessWidget {
  final String label;
  const _FilterLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(label.toUpperCase(),
        style: GoogleFonts.lexend(
          fontSize: 10, fontWeight: FontWeight.w700,
          color: AppColors.textSecondaryLight, letterSpacing: 0.08)),
    );
  }
}

class _RecencyBtn extends StatelessWidget {
  final String label;
  final String value;
  final String selected;
  final ValueChanged<String> onTap;

  const _RecencyBtn({
    required this.label, required this.value,
    required this.selected, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = selected == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? AppColors.primary : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
          ),
          child: Text(label,
            textAlign: TextAlign.center,
            style: GoogleFonts.lexend(
              fontSize: 11, fontWeight: FontWeight.w600,
              color: active ? Colors.white : AppColors.textSecondaryLight)),
        ),
      ),
    );
  }
}

class _EmptyResults extends StatelessWidget {
  final String query;
  const _EmptyResults({required this.query});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search_off_rounded, size: 60, color: AppColors.primary),
          const SizedBox(height: 16),
          Text('No results for "$query"',
            style: GoogleFonts.lexend(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text('Try different keywords or adjust filters.',
            style: GoogleFonts.lexend(fontSize: 13, color: AppColors.textSecondaryLight)),
        ],
      ),
    );
  }
}
