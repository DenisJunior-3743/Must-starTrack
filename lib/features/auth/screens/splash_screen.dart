// lib/features/auth/screens/splash_screen.dart
//
// MUST StarTrack — Immersive Splash Screen
//
// Deep blue glow aesthetic with:
//   • Layered animated glow orbs that breathe
//   • Rich twinkling star field with sparkle cross-flares on large stars
//   • Floating ambient particle orbs
//   • Expanding pulse rings behind the logo
//   • Logo entrance: scale overshoot + glow burst
//   • Name staggered reveal: MUST slides in, then StarTrack with gradient shimmer
//   • Shimmer-sweep progress bar
//   • Pulsing loading dots with blue glow
//   • Proper 3.5s hold before navigation

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/router/route_guards.dart';
import '../../../core/router/route_names.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Data models
// ─────────────────────────────────────────────────────────────────────────────

class _Star {
  final double x;
  final double y;
  final double size;
  final double phase;
  final double speed;
  final double brightness;

  const _Star({
    required this.x,
    required this.y,
    required this.size,
    required this.phase,
    required this.speed,
    required this.brightness,
  });
}

class _Particle {
  final double x;
  final double y;
  final double size;
  final double phase;
  final double driftX;
  final double driftY;
  final Color color;

  const _Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.phase,
    required this.driftX,
    required this.driftY,
    required this.color,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Splash screen widget
// ─────────────────────────────────────────────────────────────────────────────

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Controllers
  late final AnimationController _ambientCtrl;
  late final AnimationController _starsCtrl;
  late final AnimationController _ringCtrl;
  late final AnimationController _logoCtrl;
  late final AnimationController _nameCtrl;
  late final AnimationController _progressCtrl;
  late final AnimationController _shimmerCtrl;
  late final AnimationController _particleCtrl;

  // Logo animations
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _logoGlow;

  // Name animations
  late final Animation<double> _mustFade;
  late final Animation<Offset> _mustSlide;
  late final Animation<double> _starTrackFade;
  late final Animation<Offset> _starTrackSlide;
  late final Animation<double> _taglineFade;
  late final Animation<double> _subtitleFade;

  // Progress
  late final Animation<double> _progressValue;
  late final Animation<double> _progressFade;

  // Field data
  late final List<_Star> _stars;
  late final List<_Particle> _particles;

  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    final rng = Random(42);

    _stars = List.generate(
      55,
      (_) => _Star(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        size: 1.0 + rng.nextDouble() * 2.8,
        phase: rng.nextDouble() * 2 * pi,
        speed: 0.3 + rng.nextDouble() * 0.7,
        brightness: 0.5 + rng.nextDouble() * 0.5,
      ),
    );

    const particleColors = [
      Color(0xFF60A5FA),
      Color(0xFF93C5FD),
      Color(0xFFBFDBFE),
      Color(0xFF3B82F6),
      Color(0xFFDDE9FF),
    ];
    _particles = List.generate(
      18,
      (i) => _Particle(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        size: 2.0 + rng.nextDouble() * 5.0,
        phase: rng.nextDouble() * 2 * pi,
        driftX: (rng.nextDouble() - 0.5) * 0.04,
        driftY: (rng.nextDouble() - 0.5) * 0.06,
        color: particleColors[i % particleColors.length],
      ),
    );

    _ambientCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);

    _starsCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    )..repeat();

    _ringCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();

    _particleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();

    _logoCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _logoScale = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 0.0, end: 1.18)
              .chain(CurveTween(curve: Curves.easeOutCubic)),
          weight: 50),
      TweenSequenceItem(
          tween: Tween(begin: 1.18, end: 0.94)
              .chain(CurveTween(curve: Curves.easeInCubic)),
          weight: 20),
      TweenSequenceItem(
          tween: Tween(begin: 0.94, end: 1.0)
              .chain(CurveTween(curve: Curves.elasticOut)),
          weight: 30),
    ]).animate(_logoCtrl);

    _logoFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoCtrl,
        curve: const Interval(0.0, 0.30, curve: Curves.easeOut),
      ),
    );

    _logoGlow = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 0.0, end: 1.0)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 40),
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 0.55)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: 60),
    ]).animate(_logoCtrl);

    _nameCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    _mustFade = CurvedAnimation(
      parent: _nameCtrl,
      curve: const Interval(0.0, 0.40, curve: Curves.easeOut),
    );

    _mustSlide = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _nameCtrl,
        curve: const Interval(0.0, 0.45, curve: Curves.easeOutBack),
      ),
    );

    _starTrackFade = CurvedAnimation(
      parent: _nameCtrl,
      curve: const Interval(0.30, 0.75, curve: Curves.easeOut),
    );

    _starTrackSlide = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _nameCtrl,
        curve: const Interval(0.30, 0.78, curve: Curves.easeOutBack),
      ),
    );

    _taglineFade = CurvedAnimation(
      parent: _nameCtrl,
      curve: const Interval(0.60, 0.90, curve: Curves.easeOut),
    );

    _subtitleFade = CurvedAnimation(
      parent: _nameCtrl,
      curve: const Interval(0.75, 1.0, curve: Curves.easeOut),
    );

    _progressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    );

    _progressValue = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _progressCtrl, curve: Curves.easeInOutCubic),
    );

    _progressFade = CurvedAnimation(
      parent: _progressCtrl,
      curve: const Interval(0.0, 0.12, curve: Curves.easeIn),
    );

    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();

    _startSequence();
  }

  Future<void> _startSequence() async {
    if (_isNavigating) return;

    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    _logoCtrl.forward();

    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    _nameCtrl.forward();
    _progressCtrl.forward();

    // Hold on screen — total ~3.8s from launch
    await Future.delayed(const Duration(milliseconds: 2800));
    if (!mounted || _isNavigating) return;
    _isNavigating = true;

    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    final guards = sl<RouteGuards>();
    final destination = guards.isAuthenticated
        ? switch (guards.currentRole) {
            UserRole.lecturer => RouteNames.lecturerDashboard,
            UserRole.admin => RouteNames.adminDashboard,
            UserRole.superAdmin => RouteNames.superAdminDashboard,
            _ => RouteNames.home,
          }
        : RouteNames.home;

    context.go(destination);
  }

  @override
  void dispose() {
    _ambientCtrl.dispose();
    _starsCtrl.dispose();
    _ringCtrl.dispose();
    _logoCtrl.dispose();
    _nameCtrl.dispose();
    _progressCtrl.dispose();
    _shimmerCtrl.dispose();
    _particleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFF030B1F),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0.0, 0.38, 0.72, 1.0],
            colors: [
              Color(0xFF020914),
              Color(0xFF050F2A),
              Color(0xFF071540),
              Color(0xFF030B1F),
            ],
          ),
        ),
        child: Stack(
          children: [
            // ── Shared glow shell accents (matches other screens) ─────────
            const Positioned(
              top: -90,
              right: -85,
              child: _GlowBlob(size: 260, color: Color(0x332563EB)),
            ),
            const Positioned(
              bottom: -100,
              left: -95,
              child: _GlowBlob(size: 300, color: Color(0x221152D4)),
            ),

            // ── Animated ambient glow orbs ─────────────────────────────────
            AnimatedBuilder(
              animation: _ambientCtrl,
              builder: (_, __) {
                final t = _ambientCtrl.value;
                final pulse = sin(t * pi);
                return Stack(
                  children: [
                    Positioned(
                      top: -160 + (t * 30),
                      right: -140 + (t * 20),
                      child: _GlowOrb(
                        size: 380,
                        color: Color.fromARGB(
                            (55 + pulse * 25).round(), 55, 130, 255),
                      ),
                    ),
                    Positioned(
                      bottom: -180 + ((1 - t) * 30),
                      left: -130 + ((1 - t) * 25),
                      child: _GlowOrb(
                        size: 420,
                        color: Color.fromARGB(
                            (40 + pulse * 20).round(), 30, 100, 220),
                      ),
                    ),
                    Positioned(
                      top: size.height * 0.32 + sin(t * pi * 1.5) * 18,
                      left: size.width * 0.5 - 200,
                      child: _GlowOrb(
                        size: 400,
                        color: Color.fromARGB(
                            (28 + pulse * 18).round(), 80, 160, 255),
                      ),
                    ),
                    Positioned(
                      top: 60 + sin(t * pi * 2) * 12,
                      left: 20 + cos(t * pi) * 10,
                      child: _GlowOrb(
                        size: 160,
                        color: Color.fromARGB(
                            (35 + pulse * 20).round(), 100, 180, 255),
                      ),
                    ),
                  ],
                );
              },
            ),

            // ── Star field ─────────────────────────────────────────────────
            AnimatedBuilder(
              animation: _starsCtrl,
              builder: (_, __) => CustomPaint(
                size: size,
                painter: _StarPainter(
                    stars: _stars, progress: _starsCtrl.value),
              ),
            ),

            // ── Floating ambient particles ──────────────────────────────────
            AnimatedBuilder(
              animation: _particleCtrl,
              builder: (_, __) => CustomPaint(
                size: size,
                painter: _ParticlePainter(
                    particles: _particles, progress: _particleCtrl.value),
              ),
            ),

            // ── Radial vignette ────────────────────────────────────────────
            Container(
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.05,
                  colors: [
                    Colors.transparent,
                    Color(0x18010408),
                    Color(0x55010408),
                    Color(0xCC010408),
                  ],
                  stops: [0.3, 0.6, 0.82, 1.0],
                ),
              ),
            ),

            // ── Pulse rings behind logo ────────────────────────────────────
            Center(
              child: AnimatedBuilder(
                animation: Listenable.merge([_ringCtrl, _logoCtrl]),
                builder: (_, __) => CustomPaint(
                  size: const Size(300, 300),
                  painter: _PulseRingPainter(
                    progress: _ringCtrl.value,
                    opacity: (_logoCtrl.value - 0.3).clamp(0.0, 1.0),
                    color: const Color(0xFF3B82F6),
                  ),
                ),
              ),
            ),

            // ── Main content ───────────────────────────────────────────────
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Logo ──────────────────────────────────────────────
                    AnimatedBuilder(
                      animation:
                          Listenable.merge([_logoCtrl, _ambientCtrl]),
                      builder: (_, __) {
                        final ambientPulse =
                            sin(_ambientCtrl.value * pi * 2) * 0.5 + 0.5;
                        final glowI = _logoGlow.value;
                        final innerR = 40.0 + ambientPulse * 20 + glowI * 30;
                        final outerR = 60.0 + ambientPulse * 25 + glowI * 50;

                        return FadeTransition(
                          opacity: _logoFade,
                          child: ScaleTransition(
                            scale: _logoScale,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                // Outer soft glow
                                Container(
                                  width: 180,
                                  height: 180,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF3B82F6)
                                            .withValues(
                                                alpha: 0.12 +
                                                    ambientPulse * 0.08 +
                                                    glowI * 0.2),
                                        blurRadius: outerR,
                                        spreadRadius: 10,
                                      ),
                                    ],
                                  ),
                                ),
                                // Inner glow
                                Container(
                                  width: 140,
                                  height: 140,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF60A5FA)
                                            .withValues(
                                                alpha: 0.18 +
                                                    ambientPulse * 0.12 +
                                                    glowI * 0.28),
                                        blurRadius: innerR,
                                        spreadRadius: 4,
                                      ),
                                    ],
                                  ),
                                ),
                                // Glass logo card
                                Container(
                                  width: 112,
                                  height: 112,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Colors.white.withValues(alpha: 0.18),
                                        Colors.white.withValues(alpha: 0.08),
                                      ],
                                    ),
                                    borderRadius:
                                        BorderRadius.circular(30),
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                          alpha: 0.22 + ambientPulse * 0.10),
                                      width: 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF2563EB)
                                            .withValues(
                                                alpha: 0.5 +
                                                    glowI * 0.35 +
                                                    ambientPulse * 0.15),
                                        blurRadius: 28,
                                        spreadRadius: 2,
                                      ),
                                      BoxShadow(
                                        color: Colors.white
                                            .withValues(alpha: 0.06),
                                        blurRadius: 1,
                                        offset: const Offset(0, -1),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius:
                                        BorderRadius.circular(28),
                                    child: Image.asset(
                                      'assets/icons/icon.png',
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          const Icon(
                                        Icons.rocket_launch_rounded,
                                        size: 56,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 36),

                    // ── App name ──────────────────────────────────────────
                    AnimatedBuilder(
                      animation: _nameCtrl,
                      builder: (_, __) => Column(
                        children: [
                          // MUST · StarTrack
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FadeTransition(
                                  opacity: _mustFade,
                                  child: SlideTransition(
                                    position: _mustSlide,
                                    child: Text(
                                      'MUST',
                                      style: GoogleFonts.spaceGrotesk(
                                        fontSize: 42,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                        letterSpacing: -1.0,
                                        height: 1.0,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                FadeTransition(
                                  opacity: _starTrackFade,
                                  child: SlideTransition(
                                    position: _starTrackSlide,
                                    child: ShaderMask(
                                      shaderCallback: (bounds) =>
                                          const LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Color(0xFFFFFFFF),
                                          Color(0xFFBFDBFE),
                                          Color(0xFF60A5FA),
                                          Color(0xFF93C5FD),
                                        ],
                                        stops: [0.0, 0.35, 0.70, 1.0],
                                      ).createShader(bounds),
                                      child: Text(
                                        'StarTrack',
                                        style: GoogleFonts.spaceGrotesk(
                                          fontSize: 42,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                          letterSpacing: -1.0,
                                          height: 1.0,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 14),

                          // Tagline
                          FadeTransition(
                            opacity: _taglineFade,
                            child: Text(
                              'Discover  ·  Collaborate  ·  Innovate',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color:
                                    Colors.white.withValues(alpha: 0.55),
                                letterSpacing: 1.5,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),

                          const SizedBox(height: 6),

                          // University name
                          FadeTransition(
                            opacity: _subtitleFade,
                            child: Text(
                              AppStrings.university,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 11,
                                fontWeight: FontWeight.w400,
                                color:
                                    Colors.white.withValues(alpha: 0.38),
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 56),

                    // ── Progress bar + dots ───────────────────────────────
                    AnimatedBuilder(
                      animation: Listenable.merge(
                          [_progressCtrl, _shimmerCtrl, _ambientCtrl]),
                      builder: (_, __) => FadeTransition(
                        opacity: _progressFade,
                        child: Column(
                          children: [
                            // Bar
                            ClipRRect(
                              borderRadius: BorderRadius.circular(99),
                              child: SizedBox(
                                width: 180,
                                height: 3,
                                child: Stack(
                                  children: [
                                    // Track
                                    Container(
                                      color: Colors.white
                                          .withValues(alpha: 0.08),
                                    ),
                                    // Fill
                                    FractionallySizedBox(
                                      widthFactor: _progressValue.value,
                                      child: Container(
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              Color(0xFF3B82F6),
                                              Color(0xFF60A5FA),
                                              Color(0xFFBFDBFE),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    // Shimmer sweep
                                    if (_progressValue.value > 0.05)
                                      Positioned.fill(
                                        child: FractionallySizedBox(
                                          widthFactor:
                                              _progressValue.value,
                                          alignment:
                                              Alignment.centerLeft,
                                          child: LayoutBuilder(
                                            builder: (_, c) {
                                              final w = c.maxWidth;
                                              final x =
                                                  _shimmerCtrl.value *
                                                      (w + 40) -
                                                  20;
                                              return ClipRect(
                                                child: Transform.translate(
                                                  offset: Offset(x, 0),
                                                  child: Container(
                                                    width: 40,
                                                    decoration:
                                                        BoxDecoration(
                                                      gradient:
                                                          LinearGradient(
                                                        colors: [
                                                          Colors.white
                                                              .withValues(
                                                                  alpha: 0),
                                                          Colors.white
                                                              .withValues(
                                                                  alpha:
                                                                      0.55),
                                                          Colors.white
                                                              .withValues(
                                                                  alpha: 0),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 16),

                            // Pulsing dots with blue glow
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: List.generate(3, (i) {
                                final phase = (i / 3.0) * 2 * pi;
                                final pulse = sin(
                                      _ambientCtrl.value * pi * 4 +
                                          phase,
                                    ) *
                                    0.5 +
                                    0.5;
                                final sz = 5.0 + pulse * 4.0;
                                final op = 0.25 + pulse * 0.65;
                                return Container(
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 4),
                                  width: sz,
                                  height: sz,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.white
                                        .withValues(alpha: op),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF60A5FA)
                                            .withValues(
                                                alpha: op * 0.7),
                                        blurRadius: 8,
                                        spreadRadius: 1,
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Version tag ────────────────────────────────────────────────
            Positioned(
              bottom: 32,
              left: 0,
              right: 0,
              child: AnimatedBuilder(
                animation: _subtitleFade,
                builder: (_, __) => FadeTransition(
                  opacity: _subtitleFade,
                  child: Text(
                    'v1.0.0',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.18),
                      letterSpacing: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Custom painters
// ─────────────────────────────────────────────────────────────────────────────

class _StarPainter extends CustomPainter {
  final List<_Star> stars;
  final double progress;

  const _StarPainter({required this.stars, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (final star in stars) {
      final twinkle = sin(progress * 2 * pi * star.speed + star.phase);
      final normalT = twinkle * 0.5 + 0.5;
      final opacity =
          (star.brightness * (0.12 + normalT * 0.75)).clamp(0.0, 1.0);
      final radius = star.size * (0.65 + normalT * 0.35);
      final dy = (star.y + progress * 0.055 * star.speed) % 1.0;
      final cx = star.x * size.width;
      final cy = dy * size.height;

      if (star.size > 2.5) {
        // Sparkle cross flare for bigger stars
        paint.color = Colors.white.withValues(alpha: opacity);
        canvas.drawCircle(Offset(cx, cy), radius, paint);
        paint.color = Colors.white.withValues(alpha: opacity * 0.3);
        canvas.drawRect(
          Rect.fromCenter(
              center: Offset(cx, cy),
              width: radius * 5.5,
              height: radius * 0.55),
          paint,
        );
        canvas.drawRect(
          Rect.fromCenter(
              center: Offset(cx, cy),
              width: radius * 0.55,
              height: radius * 5.5),
          paint,
        );
      } else {
        paint.color = Colors.white.withValues(alpha: opacity);
        canvas.drawCircle(Offset(cx, cy), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_StarPainter old) => old.progress != progress;
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;

  const _ParticlePainter(
      {required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (final p in particles) {
      final t = sin(progress * 2 * pi + p.phase) * 0.5 + 0.5;
      final opacity = (0.04 + t * 0.16).clamp(0.0, 1.0);
      final dx = (p.x + progress * p.driftX) % 1.0;
      final dy = (p.y + progress * p.driftY) % 1.0;
      final center = Offset(dx * size.width, dy * size.height);

      for (int ring = 3; ring >= 1; ring--) {
        paint.color =
            p.color.withValues(alpha: opacity * (0.3 / ring));
        canvas.drawCircle(center, p.size * ring, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) => old.progress != progress;
}

class _PulseRingPainter extends CustomPainter {
  final double progress;
  final double opacity;
  final Color color;

  const _PulseRingPainter({
    required this.progress,
    required this.opacity,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (int i = 0; i < 3; i++) {
      final t = (progress + i / 3.0) % 1.0;
      final radius = 60.0 + t * 100.0;
      final ringOpacity = (1.0 - t) * 0.18 * opacity;
      paint.color =
          color.withValues(alpha: ringOpacity.clamp(0.0, 1.0));
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_PulseRingPainter old) =>
      old.progress != progress || old.opacity != opacity;
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper widgets
// ─────────────────────────────────────────────────────────────────────────────

class _GlowBlob extends StatelessWidget {
  final double size;
  final Color color;

  const _GlowBlob({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color,
              blurRadius: 80,
              spreadRadius: 25,
            ),
          ],
        ),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  final double size;
  final Color color;

  const _GlowOrb({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: color, blurRadius: 100, spreadRadius: 30),
          ],
        ),
      ),
    );
  }
}