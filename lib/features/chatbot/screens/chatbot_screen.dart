import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/di/injection_container.dart';
import '../../../data/local/dao/activity_log_dao.dart';
import '../../../data/remote/firestore_service.dart';
import '../../../data/remote/openai_service.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../bloc/chatbot_cubit.dart';
import '../data/chatbot_repository.dart';
import '../models/chatbot_models.dart';

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
            BoxShadow(color: color, blurRadius: 85, spreadRadius: 24),
          ],
        ),
      ),
    );
  }
}

class ChatbotScreen extends StatelessWidget {
  final ChatbotRepository repository;

  const ChatbotScreen({
    super.key,
    required this.repository,
  });

  factory ChatbotScreen.standalone({Key? key}) {
    return ChatbotScreen(
      key: key,
      repository: ChatbotRepository.defaultForApp(
        openAiService: sl<OpenAiService>(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ChatbotCubit(
        repository: repository,
        firestore: sl<FirestoreService>(),
        activityLogDao: sl<ActivityLogDao>(),
      ),
      child: const _ChatbotView(),
    );
  }
}

class _ChatbotView extends StatefulWidget {
  const _ChatbotView();

  @override
  State<_ChatbotView> createState() => _ChatbotViewState();
}

class _ChatbotViewState extends State<_ChatbotView>
    with SingleTickerProviderStateMixin {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  late final AnimationController _waveController;

  // ── Voice ─────────────────────────────────────────────────────────────────
  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  bool _sttAvailable = false;
  bool _isListening = false;
  bool _voiceOutputEnabled = false;
  List<double> _waveAmplitudes = List.filled(20, 0.05);
  double _minSoundLevel = 50000;
  double _maxSoundLevel = -50000;
  String? _lastSpokenMessageId;
  // ──────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _initTts();
  }

  Future<void> _initStt() async {
    final status = await Permission.microphone.request();
    if (!mounted) return;
    if (!status.isGranted) {
      setState(() => _sttAvailable = false);
      return;
    }
    final available = await _stt.initialize(
      onStatus: (s) {
        if (s == 'done' || s == 'notListening') _stopListening();
      },
      onError: (_) => _stopListening(),
    );
    if (!mounted) return;
    setState(() => _sttAvailable = available);
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setPitch(1.0);
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      _stopListening();
    } else {
      if (!_sttAvailable) {
        await _initStt();
        if (!_sttAvailable) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Microphone permission is required.'),
              ),
            );
          }
          return;
        }
      }
      _startListening();
    }
  }

  void _startListening() {
    if (!_sttAvailable) return;
    _tts.stop();
    setState(() {
      _isListening = true;
      _waveAmplitudes = List.filled(20, 0.05);
    });
    _waveController.repeat();
    _minSoundLevel = 50000;
    _maxSoundLevel = -50000;
    _stt.listen(
      onResult: (SpeechRecognitionResult result) {
        _inputCtrl.text = result.recognizedWords;
        _inputCtrl.selection = TextSelection.fromPosition(
          TextPosition(offset: _inputCtrl.text.length),
        );
        if (result.finalResult) _stopListening();
      },
      onSoundLevelChange: _updateWaveformFromSoundLevel,
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 4),
      localeId: 'en_US',
    );
  }

  void _updateWaveformFromSoundLevel(double level) {
    _minSoundLevel = math.min(_minSoundLevel, level);
    _maxSoundLevel = math.max(_maxSoundLevel, level);

    final dynamicRange = (_maxSoundLevel - _minSoundLevel).clamp(5.0, 50000.0);
    final normalized =
        ((level - _minSoundLevel) / dynamicRange).clamp(0.0, 1.0);
    final smoothed = (0.18 + (normalized * 0.82)).clamp(0.05, 1.0);

    if (!mounted) return;
    setState(() {
      _waveAmplitudes = List<double>.generate(20, (i) {
        final phaseOffset = i / 2.8;
        final ripple =
            0.72 + 0.28 * math.sin(phaseOffset + (normalized * math.pi));
        final previous = _waveAmplitudes[i];
        final next = (smoothed * ripple).clamp(0.05, 1.0);
        return (previous * 0.35 + next * 0.65).clamp(0.05, 1.0);
      });
    });
  }

  void _stopListening() {
    _stt.stop();
    _waveController.stop();
    _waveController.reset();
    if (mounted) {
      setState(() {
        _isListening = false;
        _waveAmplitudes = List.filled(20, 0.05);
      });
    }
  }

  Future<void> _speakLatestReply(ChatbotMessage message) async {
    if (!_voiceOutputEnabled || message.isUser) return;

    final messageId = message.interactionId ?? message.text;
    if (_lastSpokenMessageId == messageId) return;

    _lastSpokenMessageId = messageId;
    await _tts.stop();
    await _tts.speak(message.text);
  }

  Future<void> _toggleVoiceOutput() async {
    final nextValue = !_voiceOutputEnabled;
    if (!nextValue) {
      await _tts.stop();
    }
    if (!mounted) return;
    setState(() {
      _voiceOutputEnabled = nextValue;
    });
  }

  void _scrollToLatest({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      final target = _scrollCtrl.position.maxScrollExtent + 120;
      if (animate) {
        _scrollCtrl.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      } else {
        _scrollCtrl.jumpTo(target);
      }
    });
  }

  @override
  void dispose() {
    _waveController.dispose();
    _stt.stop();
    _tts.stop();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _submit(BuildContext context, String value) {
    final text = value.trim();
    if (text.isEmpty) return;

    FocusScope.of(context).unfocus();
    _inputCtrl.clear();

    final auth = sl<AuthCubit>();
    final userId = auth.currentUser?.id;
    final role = auth.currentUser?.role.name;
    final isGuest = auth.currentUser == null;

    context.read<ChatbotCubit>().ask(
          text,
          isGuest: isGuest,
          role: role,
          userId: userId,
        );

    _scrollToLatest();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgTop = isDark ? const Color(0xFF0B1222) : const Color(0xFFF8FBFF);
    final bgBottom = isDark ? const Color(0xFF111D36) : const Color(0xFFECF3FF);
    final surface = isDark ? const Color(0xFF15233D) : Colors.white;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'App Assistant',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
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
          const Positioned(
            top: -70,
            right: -60,
            child: _GlowBlob(color: Color(0x332563EB)),
          ),
          const Positioned(
            bottom: 120,
            left: -85,
            child: _GlowBlob(color: Color(0x221152D4)),
          ),
          Column(
            children: [
              Expanded(
                child: BlocListener<ChatbotCubit, ChatbotState>(
                  listenWhen: (previous, current) {
                    final prevLen = switch (previous) {
                      ChatbotIdle s => s.messages.length,
                      ChatbotTyping s => s.messages.length,
                      _ => 0,
                    };
                    final nextLen = switch (current) {
                      ChatbotIdle s => s.messages.length,
                      ChatbotTyping s => s.messages.length,
                      _ => 0,
                    };
                    return nextLen != prevLen || current is ChatbotTyping;
                  },
                  listener: (_, state) {
                    _scrollToLatest();

                    if (state is ChatbotIdle && state.messages.isNotEmpty) {
                      final latest = state.messages.last;
                      _speakLatestReply(latest);
                    }
                  },
                  child: BlocBuilder<ChatbotCubit, ChatbotState>(
                    builder: (context, state) {
                      final messages = switch (state) {
                        ChatbotIdle s => s.messages,
                        ChatbotTyping s => s.messages,
                        _ => const <ChatbotMessage>[],
                      };

                      return ListView(
                        controller: _scrollCtrl,
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
                        children: [
                          Container(
                            margin: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: surface.withValues(alpha: 0.82),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color:
                                    AppColors.primary.withValues(alpha: 0.18),
                              ),
                            ),
                            child: Text(
                              'Ask me about features, navigation, settings, and how to use StarTrack faster.',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.white70
                                    : AppColors.textSecondaryLight,
                              ),
                            ),
                          ),
                          ...messages.map(
                            (msg) => _MessageBubble(
                              message: msg,
                              voiceOutputEnabled: _voiceOutputEnabled,
                              onToggleVoiceOutput: _toggleVoiceOutput,
                            ),
                          ),
                          if (state is ChatbotTyping) const _TypingBubble(),
                        ],
                      );
                    },
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Waveform bar — visible while listening
                    if (_isListening)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                        child: AnimatedBuilder(
                          animation: _waveController,
                          builder: (_, __) {
                            return SizedBox(
                              height: 36,
                              child: CustomPaint(
                                painter: _WaveformPainter(
                                  amplitudes: _waveAmplitudes,
                                  color: AppColors.primary,
                                  phase: _waveController.value * 2 * math.pi,
                                ),
                                size: const Size(double.infinity, 36),
                              ),
                            );
                          },
                        ),
                      ),
                    Container(
                      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                      decoration: BoxDecoration(
                        color: surface.withValues(alpha: 0.93),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.18),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black
                                .withValues(alpha: isDark ? 0.28 : 0.06),
                            blurRadius: 14,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _inputCtrl,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (v) => _submit(context, v),
                              decoration: InputDecoration(
                                hintText:
                                    'Ask about navigation, features, or settings...',
                                isDense: true,
                                filled: true,
                                fillColor: isDark
                                    ? Colors.white.withValues(alpha: 0.05)
                                    : const Color(0xFFF8FAFC),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 12,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                      AppDimensions.radiusMd),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                      AppDimensions.radiusMd),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(
                                      AppDimensions.radiusMd),
                                  borderSide: BorderSide(
                                    color: AppColors.primary
                                        .withValues(alpha: 0.35),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Mic button
                          SizedBox(
                            width: 44,
                            height: 44,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                minimumSize: Size.zero,
                                padding: EdgeInsets.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                backgroundColor: _isListening
                                    ? Colors.red
                                    : _sttAvailable
                                        ? AppColors.primary
                                            .withValues(alpha: 0.85)
                                        : Colors.grey,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _toggleListening,
                              child: Icon(
                                _isListening
                                    ? Icons.mic
                                    : Icons.mic_none_rounded,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          // Send button
                          SizedBox(
                            width: 44,
                            height: 44,
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                minimumSize: Size.zero,
                                padding: EdgeInsets.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                backgroundColor: AppColors.success,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () =>
                                  _submit(context, _inputCtrl.text),
                              child: const Icon(Icons.send_rounded),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatbotMessage message;
  final bool voiceOutputEnabled;
  final Future<void> Function() onToggleVoiceOutput;

  const _MessageBubble({
    required this.message,
    required this.voiceOutputEnabled,
    required this.onToggleVoiceOutput,
  });

  @override
  Widget build(BuildContext context) {
    final message = this.message;
    final isUser = message.isUser;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bubbleColor = isUser
        ? AppColors.primary
        : (isDark ? const Color(0xFF1E293B) : Colors.white);

    final textColor = isUser ? Colors.white : AppColors.textPrimary(context);
    final actorUserId = sl<AuthCubit>().currentUser?.id;
    final canSendFeedback =
        !isUser && message.interactionId != null && actorUserId != null;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: isUser
                  ? Colors.transparent
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : AppColors.primary.withValues(alpha: 0.16)),
            ),
            boxShadow: [
              BoxShadow(
                color: isUser
                    ? AppColors.primary.withValues(alpha: 0.22)
                    : Colors.black.withValues(alpha: isDark ? 0.20 : 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment:
                isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Text(
                message.text,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  height: 1.35,
                  color: textColor,
                ),
              ),
              if (!isUser) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: InkWell(
                    onTap: onToggleVoiceOutput,
                    borderRadius: BorderRadius.circular(20),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            voiceOutputEnabled
                                ? Icons.volume_up_outlined
                                : Icons.volume_off_outlined,
                            size: 18,
                            color: isDark ? Colors.white54 : AppColors.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            voiceOutputEnabled ? 'Voice on' : 'Read only',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Colors.white60
                                  : AppColors.textSecondaryLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              if (canSendFeedback) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilterChip(
                      backgroundColor: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : const Color(0xFFF8FAFC),
                      side: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.22),
                      ),
                      selectedColor: AppColors.success.withValues(alpha: 0.16),
                      label: Text(
                        'Helpful',
                        style: GoogleFonts.plusJakartaSans(fontSize: 11),
                      ),
                      selected: message.isHelpful == true,
                      onSelected: (_) =>
                          context.read<ChatbotCubit>().markHelpful(
                                interactionId: message.interactionId!,
                                isHelpful: true,
                                actorUserId: actorUserId,
                              ),
                    ),
                    FilterChip(
                      backgroundColor: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : const Color(0xFFF8FAFC),
                      side: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.22),
                      ),
                      selectedColor: AppColors.danger.withValues(alpha: 0.12),
                      label: Text(
                        'Not Helpful',
                        style: GoogleFonts.plusJakartaSans(fontSize: 11),
                      ),
                      selected: message.isHelpful == false,
                      onSelected: (_) =>
                          context.read<ChatbotCubit>().markHelpful(
                                interactionId: message.interactionId!,
                                isHelpful: false,
                                actorUserId: actorUserId,
                              ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : AppColors.primary.withValues(alpha: 0.16),
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text(
              'Thinking...',
            ),
          ],
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> amplitudes;
  final Color color;
  final double phase;

  const _WaveformPainter({
    required this.amplitudes,
    required this.color,
    required this.phase,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (amplitudes.isEmpty) return;

    final centerY = size.height / 2;
    final baseAmplitude = size.height * 0.34;
    final wavelength = size.width / 2.8;

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    for (double x = 0; x <= size.width; x += 1) {
      final t = x / size.width;
      final envelope = _sampleAmplitude(t).clamp(0.05, 1.0);
      final waveX = (2 * math.pi * x / wavelength) + phase;
      final sine = math.sin(waveX);
      final harmonic = 0.32 * math.sin(3 * waveX);
      final zigzagSine = (sine + harmonic).clamp(-1.2, 1.2);
      final y = centerY + zigzagSine * baseAmplitude * envelope;
      if (x == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, strokePaint);
  }

  double _sampleAmplitude(double t) {
    final safeT = t.clamp(0.0, 1.0);
    final position = safeT * (amplitudes.length - 1);
    final leftIndex = position.floor();
    final rightIndex = math.min(leftIndex + 1, amplitudes.length - 1);
    final blend = position - leftIndex;
    final left = amplitudes[leftIndex];
    final right = amplitudes[rightIndex];
    return left + (right - left) * blend;
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.amplitudes != amplitudes || old.phase != phase || old.color != color;
}
