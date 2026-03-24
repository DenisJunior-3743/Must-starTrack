// lib/features/auth/screens/splash_screen.dart
//
// MUST StarTrack — Gamified Splash Screen
//
// Shown on app launch while:
//   1. DatabaseHelper initialises SQLite
//   2. AuthRepository checks for a persisted session
//
// After checking, routes to:
//   - /home (authenticated student/lecturer)
//   - /admin (authenticated admin)
//   - /explore (guest / no session)
//
// HCI: Feedback, Identity, Gamification — animated stars, bouncing
//      logo, staggered text reveal, progress dots.

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/router/route_names.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Particle data model
// ─────────────────────────────────────────────────────────────────────────────

class _Star {
  final double x;      // 0..1 (fraction of screen width)
  final double y;      // 0..1 (fraction of screen height)
  final double size;
  final double phase;  // animation phase offset (0..1)
  final double speed;  // relative drift speed

  const _Star({
    required this.x,
    required this.y,
    required this.size,
    required this.phase,
    required this.speed,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {

  // Logo + main content
  late final AnimationController _mainCtrl;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoFade;
  late final Animation<double> _titleFade;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _subtitleFade;
  late final Animation<double> _dotsFade;

  // Stars particle system
  late final AnimationController _starsCtrl;
  late final List<_Star> _stars;

  // Progress dots pulse
  late final AnimationController _dotsCtrl;

  @override
  void initState() {
    super.initState();

    // ── Particle system ─────────────────────────────────────────────────────
    final rng = Random(42);
    _stars = List.generate(28, (_) => _Star(
      x: rng.nextDouble(),
      y: rng.nextDouble(),
      size: 2 + rng.nextDouble() * 3,
      phase: rng.nextDouble(),
      speed: 0.4 + rng.nextDouble() * 0.6,
    ));

    _starsCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();

    // ── Main staggered animation ─────────────────────────────────────────────
    _mainCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    // Logo bounces in   0–600 ms
    _logoScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.15), weight: 55),
      TweenSequenceItem(tween: Tween(begin: 1.15, end: 0.92), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 0.92, end: 1.0),  weight: 25),
    ]).animate(CurvedAnimation(
      parent: _mainCtrl,
      curve: const Interval(0.0, 0.35, curve: Curves.easeOut),
    ));

    _logoFade = CurvedAnimation(
      parent: _mainCtrl,
      curve: const Interval(0.0, 0.25, curve: Curves.easeIn),
    );

    // Title slides + fades in  400–850 ms
    _titleFade = CurvedAnimation(
      parent: _mainCtrl,
      curve: const Interval(0.20, 0.50, curve: Curves.easeOut),
    );
    _titleSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _mainCtrl,
      curve: const Interval(0.20, 0.55, curve: Curves.easeOut),
    ));

    // Subtitle   600–1000 ms
    _subtitleFade = CurvedAnimation(
      parent: _mainCtrl,
      curve: const Interval(0.38, 0.65, curve: Curves.easeOut),
    );

    // Progress dots  800 ms →
    _dotsFade = CurvedAnimation(
      parent: _mainCtrl,
      curve: const Interval(0.55, 0.80, curve: Curves.easeOut),
    );

    _mainCtrl.forward();

    // ── Dots pulse ───────────────────────────────────────────────────────────
    _dotsCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    // ── Navigate ─────────────────────────────────────────────────────────────
    _navigate();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(milliseconds: 2800));
    if (!mounted) return;
    context.go(RouteNames.home);
  }

  @override
  void dispose() {
    _mainCtrl.dispose();
    _starsCtrl.dispose();
    _dotsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF060E2D),   // near-black navy
              Color(0xFF0D3FA8),   // MUST primary dark
              Color(0xFF1152D4),   // MUST primary
            ],
          ),
        ),
        child: Stack(
          children: [
            // ── Animated star particles ────────────────────────────────────
            AnimatedBuilder(
              animation: _starsCtrl,
              builder: (_, __) {
                final t = _starsCtrl.value;
                return CustomPaint(
                  size: size,
                  painter: _StarPainter(stars: _stars, progress: t),
                );
              },
            ),

            // ── Main content ───────────────────────────────────────────────
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo
                    FadeTransition(
                      opacity: _logoFade,
                      child: ScaleTransition(
                        scale: _logoScale,
                        child: Container(
                          width: 108,
                          height: 108,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.25),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.6),
                                blurRadius: 24,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(26),
                            child: Image.asset(
                              'assets/icons/icon.png',
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.rocket_launch_rounded,
                                size: 56,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 28),

                    // App name
                    FadeTransition(
                      opacity: _titleFade,
                      child: SlideTransition(
                        position: _titleSlide,
                        child: Text(
                          AppStrings.appName,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 38,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.8,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    // Tagline
                    FadeTransition(
                      opacity: _subtitleFade,
                      child: Text(
                        'Discover · Collaborate · Innovate',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.70),
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),

                    const SizedBox(height: 10),

                    // University name
                    FadeTransition(
                      opacity: _subtitleFade,
                      child: Text(
                        AppStrings.university,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: Colors.white.withValues(alpha: 0.55),
                          letterSpacing: 0.3,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),

                    const SizedBox(height: 52),

                    // Animated pulsing dots
                    FadeTransition(
                      opacity: _dotsFade,
                      child: AnimatedBuilder(
                        animation: _dotsCtrl,
                        builder: (_, __) {
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: List.generate(3, (i) {
                              final phase = (i / 3.0);
                              final pulse = sin((_dotsCtrl.value + phase) * pi);
                              final sz = 7.0 + pulse.clamp(0.0, 1.0) * 5.0;
                              final opacity = 0.35 + pulse.clamp(0.0, 1.0) * 0.65;
                              return AnimatedContainer(
                                duration: Duration.zero,
                                margin: const EdgeInsets.symmetric(horizontal: 5),
                                width: sz,
                                height: sz,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white.withValues(alpha: opacity),
                                ),
                              );
                            }),
                          );
                        },
                      ),
                    ),
                  ],
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
// Star particle painter
// ─────────────────────────────────────────────────────────────────────────────

class _StarPainter extends CustomPainter {
  final List<_Star> stars;
  final double progress; // 0..1 repeating

  const _StarPainter({required this.stars, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;

    for (final star in stars) {
      final twinkle = sin((progress * 2 * pi * star.speed) + star.phase * 2 * pi);
      final opacity = 0.15 + (twinkle * 0.5 + 0.5) * 0.55;
      final radius = star.size * (0.7 + (twinkle * 0.5 + 0.5) * 0.3);

      // Slow vertical drift
      final dy = (star.y + progress * 0.08 * star.speed) % 1.0;

      paint.color = Colors.white.withValues(alpha: opacity);
      canvas.drawCircle(
        Offset(star.x * size.width, dy * size.height),
        radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_StarPainter old) => old.progress != progress;
}



