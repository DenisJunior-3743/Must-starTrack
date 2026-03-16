// lib/features/super_admin/screens/super_admin_dashboard_screen.dart
//
// MUST StarTrack — Super Admin Analytics Dashboard (Phase 4)
//
// Matches super_admin_analytics_dashboard.html exactly:
//   • Header: admin avatar + title + settings
//   • System Health Ticker: cloud sync status, server, active admins
//   • Quick Stats 2×2 grid: Total Users, Active Today, Projects, Collabs
//     — each card has icon, growth %, value
//   • User Registration line chart (custom painter — no external chart lib)
//   • Faculty Engagement animated progress bars
//   • Trending Skills chip cloud (top = filled primary, rest = outlined)
//   • Bottom nav: Overview | Users | Content | Settings
//
// Engineering Metrics (requested by team for panel defence):
//   • DAU / MAU ratio (stickiness metric)
//   • Sync queue depth (infrastructure health)
//   • Offline vs online session ratio
//   • p95 feed load time (performance)
//   • Collaboration rate = collabs / total_projects
//
// HCI:
//   • Chunking: ticker → stats → chart → faculty → skills
//   • Visibility: green dot on sync status, growth badges
//   • Affordance: navigation bar icons clearly labelled

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';

class SuperAdminDashboardScreen extends StatefulWidget {
  const SuperAdminDashboardScreen({super.key});

  @override
  State<SuperAdminDashboardScreen> createState() =>
      _SuperAdminDashboardScreenState();
}

class _SuperAdminDashboardScreenState extends State<SuperAdminDashboardScreen>
    with TickerProviderStateMixin {
  int _tab = 0;

  // Animated progress bar controllers
  late List<AnimationController> _barCtrl;
  late List<Animation<double>> _barAnim;

  static const _facultyData = [
    ('Computing & IT', 0.88),
    ('Engineering', 0.72),
    ('Business Management', 0.64),
    ('Applied Sciences', 0.57),
    ('Architecture & Design', 0.51),
  ];

  static const _trendingSkills = [
    'Python', 'Flutter', 'UI/UX Research', 'Data Science',
    'AI/ML', 'Cloud Computing', 'Blockchain', 'Technical Writing',
  ];

  // Engineering metrics
  static const _engMetrics = [
    _EngMetric('DAU/MAU Ratio', '34%', '+2%', Icons.people_alt_rounded, 'Stickiness — industry avg 20–30%'),
    _EngMetric('Sync Queue Depth', '12 jobs', '-8', Icons.sync_rounded, 'Pending Firestore writes'),
    _EngMetric('Offline Sessions', '18%', '-3%', Icons.wifi_off_rounded, 'Users on 3G/no-network'),
    _EngMetric('p95 Feed Load', '340ms', '-20ms', Icons.speed_rounded, 'Feed render time on mid-range device'),
    _EngMetric('Collab Rate', '16.6%', '+1.2%', Icons.handshake_rounded, 'Collabs ÷ Total Projects'),
    _EngMetric('Avg Session', '8.4 min', '+0.6', Icons.timer_outlined, 'Mean active session length'),
  ];

  @override
  void initState() {
    super.initState();
    _barCtrl = List.generate(
      _facultyData.length,
      (i) => AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 600 + i * 100)),
    );
    _barAnim = _barCtrl.asMap().entries.map((e) =>
      Tween<double>(begin: 0, end: _facultyData[e.key].$2).animate(
        CurvedAnimation(parent: e.value, curve: Curves.easeOutCubic)),
    ).toList();

    // Stagger bar animations
    for (var i = 0; i < _barCtrl.length; i++) {
      Future.delayed(Duration(milliseconds: 200 + i * 80),
          () { if (mounted) _barCtrl[i].forward(); });
    }
  }

  @override
  void dispose() {
    for (final c in _barCtrl) { c.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ── App bar ────────────────────────────────────────────────────────
      appBar: AppBar(
        leadingWidth: 60,
        leading: const Padding(
          padding: EdgeInsets.all(10),
          child: CircleAvatar(
            backgroundColor: AppColors.primaryTint10,
            child: Icon(Icons.admin_panel_settings_rounded,
                color: AppColors.primary, size: 20),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('System Analytics',
              style: GoogleFonts.lexend(
                fontSize: 16, fontWeight: FontWeight.w700)),
            Text('MUST StarTrack Super Admin',
              style: GoogleFonts.lexend(
                fontSize: 10, fontWeight: FontWeight.w600,
                color: AppColors.primary)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_rounded),
            onPressed: () {},
            tooltip: 'System settings',
          ),
        ],
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── System health ticker ─────────────────────────────────────
            _HealthTicker(),
            const SizedBox(height: 4),

            // ── Quick stats 2×2 ──────────────────────────────────────────
            const _SectionLabel('PLATFORM OVERVIEW'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.35,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: const [
                  _StatCard(icon: Icons.group_rounded,
                      label: 'Total Users', value: '12,450', growth: '+12%'),
                  _StatCard(icon: Icons.bolt_rounded,
                      label: 'Active Today', value: '1,204', growth: '+5%'),
                  _StatCard(icon: Icons.folder_open_rounded,
                      label: 'Total Projects', value: '856', growth: '+8%'),
                  _StatCard(icon: Icons.handshake_rounded,
                      label: 'Collaborations', value: '142', growth: '+15%'),
                ],
              ),
            ),

            // ── User registration chart ──────────────────────────────────
            const _SectionLabel('USER REGISTRATION'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: _cardDecor(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('User Registration',
                                style: GoogleFonts.lexend(
                                  fontSize: 14, fontWeight: FontWeight.w700)),
                              Text('Growth trend last 6 months',
                                style: GoogleFonts.lexend(
                                  fontSize: 11, color: AppColors.textSecondaryLight)),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('12.4k',
                              style: GoogleFonts.lexend(
                                fontSize: 20, fontWeight: FontWeight.w700)),
                            Text('Jan – Jun',
                              style: GoogleFonts.lexend(
                                fontSize: 10, fontWeight: FontWeight.w700,
                                color: AppColors.success)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const SizedBox(
                      height: 120,
                      child: CustomPaint(
                        painter: _ChartPainter(color: AppColors.primary),
                        child: SizedBox.expand()),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: ['Jan','Feb','Mar','Apr','May','Jun'].map((m) =>
                        Text(m, style: GoogleFonts.lexend(
                          fontSize: 10, color: AppColors.textSecondaryLight,
                          fontWeight: FontWeight.w600))).toList(),
                    ),
                  ],
                ),
              ),
            ),

            // ── Faculty engagement ───────────────────────────────────────
            const _SectionLabel('FACULTY ENGAGEMENT'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: _cardDecor(context),
                child: Column(
                  children: _facultyData.asMap().entries.map((e) {
                    final (label, pct) = e.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(label, style: GoogleFonts.lexend(
                                fontSize: 12, fontWeight: FontWeight.w600)),
                              Text('${(pct * 100).toInt()}%',
                                style: GoogleFonts.lexend(
                                  fontSize: 12, fontWeight: FontWeight.w700,
                                  color: AppColors.primary)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
                            child: AnimatedBuilder(
                              animation: _barAnim[e.key],
                              builder: (_, __) => LinearProgressIndicator(
                                value: _barAnim[e.key].value,
                                minHeight: 8,
                                backgroundColor: AppColors.surfaceLight,
                                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            // ── Trending skills ──────────────────────────────────────────
            const _SectionLabel('TRENDING SKILLS'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 8, runSpacing: 8,
                children: _trendingSkills.asMap().entries.map((e) {
                  final isTop = e.key == 0;
                  return AnimatedContainer(
                    duration: Duration(milliseconds: 300 + e.key * 50),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isTop ? AppColors.primary : Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
                      border: Border.all(
                        color: isTop ? AppColors.primary : AppColors.borderLight),
                      boxShadow: isTop ? [BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.25),
                        blurRadius: 8, offset: const Offset(0, 3))] : [],
                    ),
                    child: Text(e.value,
                      style: GoogleFonts.lexend(
                        fontSize: 12, fontWeight: FontWeight.w600,
                        color: isTop ? Colors.white : AppColors.textPrimaryLight)),
                  );
                }).toList(),
              ),
            ),

            // ── Engineering metrics ──────────────────────────────────────
            const _SectionLabel('ENGINEERING METRICS'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.5,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: _engMetrics.map((m) => _EngMetricCard(metric: m)).toList(),
              ),
            ),
          ],
        ),
      ),

      // ── Bottom nav ────────────────────────────────────────────────────
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Overview'),
          NavigationDestination(
            icon: Icon(Icons.group_outlined),
            selectedIcon: Icon(Icons.group_rounded),
            label: 'Users'),
          NavigationDestination(
            icon: Icon(Icons.description_outlined),
            selectedIcon: Icon(Icons.description_rounded),
            label: 'Content'),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings'),
        ],
      ),
    );
  }

  BoxDecoration _cardDecor(BuildContext context) => BoxDecoration(
    color: Theme.of(context).cardColor,
    borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
    border: Border.all(color: AppColors.borderLight),
    boxShadow: [BoxShadow(
      color: Colors.black.withValues(alpha: 0.03),
      blurRadius: 6, offset: const Offset(0, 2))],
  );
}

// ── System health ticker ──────────────────────────────────────────────────────

class _HealthTicker extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        children: const [
          _Pill(
            dot: Color(0xFF10B981), label: '100% Cloud Synced',
            bg: Color(0xFFF0FDF4), border: Color(0xFFBBF7D0),
            fg: Color(0xFF065F46)),
          SizedBox(width: 8),
          _Pill(
            dot: Color(0xFF3B82F6), label: 'Server: Active',
            bg: Color(0xFFEFF6FF), border: Color(0xFFBFDBFE),
            fg: Color(0xFF1E40AF)),
          SizedBox(width: 8),
          _Pill(
            icon: Icons.admin_panel_settings_rounded,
            label: '12 Active Admins',
            bg: AppColors.surfaceLight, border: AppColors.borderLight,
            fg: AppColors.textSecondaryLight),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final Color? dot;
  final IconData? icon;
  final String label;
  final Color bg, border, fg;

  const _Pill({
    this.dot, this.icon, required this.label,
    required this.bg, required this.border, required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
        border: Border.all(color: border)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dot != null)
            Container(width: 8, height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          if (icon != null)
            Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Text(label, style: GoogleFonts.lexend(
            fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 24, 16, 10),
    child: Text(text,
      style: GoogleFonts.lexend(
        fontSize: 11, fontWeight: FontWeight.w700,
        color: AppColors.textSecondaryLight, letterSpacing: 0.1)),
  );
}

// ── Stat card ─────────────────────────────────────────────────────────────────

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String growth;

  const _StatCard({
    required this.icon, required this.label,
    required this.value, required this.growth,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        border: Border.all(color: AppColors.borderLight),
        boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: 0.03),
          blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppColors.primaryTint10,
                  borderRadius: BorderRadius.circular(AppDimensions.radiusSm)),
                child: Icon(icon, color: AppColors.primary, size: 18)),
              Text(growth, style: GoogleFonts.lexend(
                fontSize: 11, fontWeight: FontWeight.w700,
                color: AppColors.success)),
            ],
          ),
          Text(label.toUpperCase(), style: GoogleFonts.lexend(
            fontSize: 9, fontWeight: FontWeight.w700,
            color: AppColors.textSecondaryLight, letterSpacing: 0.08)),
          Text(value, style: GoogleFonts.lexend(
            fontSize: 20, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// ── Engineering metric card ───────────────────────────────────────────────────

class _EngMetric {
  final String label;
  final String value;
  final String delta;
  final IconData icon;
  final String description;
  const _EngMetric(this.label, this.value, this.delta, this.icon, this.description);
}

class _EngMetricCard extends StatelessWidget {
  final _EngMetric metric;
  const _EngMetricCard({required this.metric});

  @override
  Widget build(BuildContext context) {
    final isPositive = metric.delta.startsWith('+') ||
        (metric.delta.startsWith('-') && metric.label.contains('Load'));

    return Tooltip(
      message: metric.description,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
          border: Border.all(color: AppColors.borderLight)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(metric.icon, color: AppColors.primary, size: 18),
                Text(metric.delta, style: GoogleFonts.lexend(
                  fontSize: 10, fontWeight: FontWeight.w700,
                  color: isPositive ? AppColors.success : AppColors.danger)),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(metric.value, style: GoogleFonts.lexend(
                  fontSize: 18, fontWeight: FontWeight.w700)),
                Text(metric.label, style: GoogleFonts.lexend(
                  fontSize: 10, color: AppColors.textSecondaryLight,
                  fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Line chart custom painter ─────────────────────────────────────────────────

class _ChartPainter extends CustomPainter {
  final Color color;
  const _ChartPainter({required this.color});

  // Data points matching the SVG path in the HTML prototype (normalised 0–1)
  static const _points = [
    0.73, 0.14, 0.27, 0.62, 0.22, 0.67, 0.41, 0.30, 0.81, 0.99, 0.01, 0.54, 0.86, 0.17,
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..shader = LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0.0)])
          .createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;

    final path = Path();
    final fillPath = Path();

    for (var i = 0; i < _points.length; i++) {
      final x = size.width * i / (_points.length - 1);
      final y = size.height * _points[i];
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, y);
      } else {
        final prevX = size.width * (i - 1) / (_points.length - 1);
        final prevY = size.height * _points[i - 1];
        final cp1x = prevX + (x - prevX) / 2;
        path.cubicTo(cp1x, prevY, cp1x, y, x, y);
        fillPath.cubicTo(cp1x, prevY, cp1x, y, x, y);
      }
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.lineTo(0, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
