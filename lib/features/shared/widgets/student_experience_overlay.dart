import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/router/route_guards.dart';
import '../../../core/router/route_names.dart';
import '../../auth/bloc/auth_cubit.dart';
import 'settings_drawer.dart';

class StudentExperienceOverlay extends StatelessWidget {
  const StudentExperienceOverlay({
    super.key,
    required this.router,
    required this.child,
  });

  final GoRouter router;
  final Widget child;

  bool _isAuthPath(String path) {
    return path == RouteNames.splash ||
        path == RouteNames.guestDiscover ||
        path.startsWith('/auth');
  }

  bool _supportsAppTools(AuthState state, String path) {
    if (_isAuthPath(path)) return false;
    if (state is! AuthAuthenticated) {
      return path.startsWith(RouteNames.home) ||
          path.startsWith(RouteNames.guestDiscover);
    }
    return state.user.role != UserRole.guest;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: router.routeInformationProvider,
      builder: (context, _) {
        final path = router.routeInformationProvider.value.uri.path;
        return BlocBuilder<AuthCubit, AuthState>(
          buildWhen: (previous, current) =>
              previous.runtimeType != current.runtimeType ||
              (previous is AuthAuthenticated &&
                  current is AuthAuthenticated &&
                  previous.user.role != current.user.role),
          builder: (context, authState) {
            final isChatbotRoute = path.startsWith(RouteNames.chatbot);
            final showTools =
                _supportsAppTools(authState, path) && !isChatbotRoute;
            final showMenu = showTools && path != RouteNames.home;
            final showAssistant = showTools;

            return Scaffold(
              endDrawer: showTools ? SettingsDrawer(router: router) : null,
              body: Stack(
                children: [
                  Positioned.fill(child: child),
                  if (showMenu) const _FloatingMenuButton(),
                  if (showAssistant) _DraggableAssistantButton(router: router),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _FloatingMenuButton extends StatelessWidget {
  const _FloatingMenuButton();

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top + 8;
    return Positioned(
      top: top,
      right: 12,
      child: Builder(
        builder: (buttonContext) {
          return Semantics(
            button: true,
            label: 'Open menu',
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              elevation: 8,
              shadowColor: Colors.black.withValues(alpha: 0.18),
              shape: const CircleBorder(),
              child: IconButton(
                icon: const Icon(Icons.menu_rounded),
                color: AppColors.primary,
                onPressed: () => Scaffold.of(buttonContext).openEndDrawer(),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DraggableAssistantButton extends StatefulWidget {
  const _DraggableAssistantButton({required this.router});

  final GoRouter router;

  @override
  State<_DraggableAssistantButton> createState() =>
      _DraggableAssistantButtonState();
}

class _DraggableAssistantButtonState extends State<_DraggableAssistantButton> {
  static const double _size = 58;
  static const double _margin = 14;
  Offset? _offset;
  bool _dragged = false;
  bool _isDragging = false;
  bool _isPressed = false;

  Offset _defaultOffset(Size screen, EdgeInsets padding) {
    return Offset(
      screen.width - _size - _margin,
      screen.height - _size - padding.bottom - 112,
    );
  }

  Offset _clampOffset(Offset value, Size screen, EdgeInsets padding) {
    const minX = _margin;
    final maxX = (screen.width - _size - _margin).clamp(minX, double.infinity);
    final minY = padding.top + _margin;
    final maxY = (screen.height - _size - padding.bottom - _margin)
        .clamp(minY, double.infinity);
    return Offset(
      value.dx.clamp(minX, maxX).toDouble(),
      value.dy.clamp(minY, maxY).toDouble(),
    );
  }

  void _openAssistant() {
    HapticFeedback.lightImpact();
    widget.router.push(RouteNames.chatbot);
  }

  void _snapToEdge(Size screen, EdgeInsets padding, Offset current) {
    final midpoint = screen.width / 2;
    final targetX =
        current.dx < midpoint ? _margin : screen.width - _size - _margin;
    setState(() {
      _offset = _clampOffset(
        Offset(targetX, current.dy),
        screen,
        padding,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screen = media.size;
    final padding = media.padding;
    final current = _clampOffset(
      _offset ?? _defaultOffset(screen, padding),
      screen,
      padding,
    );

    return Positioned(
      left: current.dx,
      top: current.dy,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapCancel: () => setState(() => _isPressed = false),
        onTapUp: (_) => setState(() => _isPressed = false),
        onPanStart: (_) {
          _dragged = false;
          setState(() {
            _isDragging = true;
            _isPressed = false;
          });
        },
        onPanUpdate: (details) {
          _dragged = true;
          setState(() {
            _offset = _clampOffset(current + details.delta, screen, padding);
          });
        },
        onPanEnd: (_) {
          final snapFrom = _offset ?? current;
          _snapToEdge(screen, padding, snapFrom);
          setState(() => _isDragging = false);
        },
        onTap: () {
          if (_dragged) {
            _dragged = false;
            return;
          }
          _openAssistant();
        },
        child: Semantics(
          button: true,
          label: 'Open assistant',
          child: AnimatedScale(
            scale: _isDragging
                ? 1.10
                : _isPressed
                    ? 0.93
                    : 1.0,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isDragging
                    ? const Color(0xFF7ED957)
                    : (_isPressed
                        ? const Color(0xFF8EDC69)
                        : const Color(0xFF9BE87A)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF4CB944)
                        .withValues(alpha: _isDragging ? 0.42 : 0.32),
                    blurRadius: _isDragging ? 24 : 18,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.16),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.90),
                  width: 2,
                ),
              ),
              child: SizedBox(
                width: _size,
                height: _size,
                child: Icon(
                  Icons.support_agent_rounded,
                  color: Colors.green.shade900,
                  size: 30,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
