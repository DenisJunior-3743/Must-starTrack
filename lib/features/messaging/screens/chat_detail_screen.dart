// lib/features/messaging/screens/chat_detail_screen.dart
//
// MUST StarTrack — Chat Detail Screen (Phase 4)
//
// Matches chat_detail.html exactly:
//   • Sticky header: avatar + online status + video/call/menu buttons
//   • Date dividers between message groups
//   • Received messages: white bubble, bl-none rounded corner, avatar
//   • Sent messages: primary-colour bubble, br-none rounded corner
//   • File attachment sent: icon + name + size row inside bubble
//   • Read receipt: done_all icon
//   • Typing indicator animation (three dots)
//   • Bottom input: attach, text field, send button
//   • Contextual toolbar: Share Project + Schedule
//
// HCI:
//   • Affordance: send button scale animation on tap (active state)
//   • Feedback: optimistic message appear instantly before server ack
//   • Visibility: online dot, read receipts, typing indicator
//   • Natural mapping: own messages right, others left (universal convention)

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';

// ── Message model (Phase 5: replace with MessageDao + Firestore stream) ────────

enum _MsgType { text, file }

class _Message {
  final String id;
  final String text;
  final _MsgType type;
  final bool isMine;
  final DateTime sentAt;
  final bool isRead;
  final String? fileName;
  final String? fileSize;

  const _Message({
    required this.id,
    required this.text,
    required this.isMine,
    required this.sentAt,
    this.type = _MsgType.text,
    this.isRead = false,
    this.fileName,
    this.fileSize,
  });
}

// ── Screen ────────────────────────────────────────────────────────────────────

class ChatDetailScreen extends StatefulWidget {
  /// Can be a userId or a conversationId — Phase 5 will resolve to a User object
  final String peerId;

  const ChatDetailScreen({super.key, this.peerId = ''});

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen>
    with TickerProviderStateMixin {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _isTyping = false; // simulates remote "typing…"

  // Typing indicator animation
  late AnimationController _dotCtrl;
  late Animation<double> _dotAnim;

  final _messages = <_Message>[
    _Message(
      id: 'm1',
      text: 'Hello! Have you had a chance to look at the latest project requirements for the StarTrack module?',
      isMine: false,
      sentAt: DateTime.now().subtract(const Duration(minutes: 30)),
    ),
    _Message(
      id: 'm2',
      text: 'Hi Dr. Smith, yes I just finished reviewing them. The timelines for the orbital tracking phase look feasible.',
      isMine: true,
      sentAt: DateTime.now().subtract(const Duration(minutes: 28)),
      isRead: true,
    ),
    _Message(
      id: 'm3',
      text: 'Great. Can you share the initial draft of the star tracking module? I\'d like to present it to the board tomorrow.',
      isMine: false,
      sentAt: DateTime.now().subtract(const Duration(minutes: 27)),
    ),
    _Message(
      id: 'm4_file',
      text: 'StarTrack_Draft_v1.pdf',
      isMine: true,
      sentAt: DateTime.now().subtract(const Duration(minutes: 25)),
      type: _MsgType.file,
      isRead: true,
      fileName: 'StarTrack_Draft_v1.pdf',
      fileSize: '4.2 MB • PDF',
    ),
    _Message(
      id: 'm5',
      text: 'Attached the latest draft. Let me know if you need any modifications before the meeting.',
      isMine: true,
      sentAt: DateTime.now().subtract(const Duration(minutes: 25)),
      isRead: true,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _dotCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _dotAnim = Tween(begin: 0.4, end: 1.0).animate(_dotCtrl);

    // Simulate peer typing after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _isTyping = true);
    });
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _dotCtrl.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _messages.add(_Message(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: text,
        isMine: true,
        sentAt: DateTime.now(),
        isRead: false,
      ));
      _msgCtrl.clear();
      _isTyping = false;
    });

    // Scroll to bottom
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // ── Header ──────────────────────────────────────────────────────────
      appBar: AppBar(
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.primary),
          onPressed: () => context.pop(),
        ),
        title: Row(
          children: [
            Stack(
              children: [
                const CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.primaryTint10,
                  child: Icon(Icons.person_rounded, color: AppColors.primary, size: 22),
                ),
                Positioned(
                  bottom: 0, right: 0,
                  child: Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                      color: AppColors.success, shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5)),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Dr. Jane Smith',
                  style: GoogleFonts.lexend(
                    fontSize: 15, fontWeight: FontWeight.w700,
                    color: Theme.of(context).appBarTheme.foregroundColor)),
                Text(_isTyping ? 'typing…' : 'Online',
                  style: GoogleFonts.lexend(
                    fontSize: 11, fontWeight: FontWeight.w600,
                    color: AppColors.primary)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.videocam_rounded),
            onPressed: () {},
            tooltip: 'Video call',
          ),
          IconButton(
            icon: const Icon(Icons.call_rounded),
            onPressed: () {},
            tooltip: 'Voice call',
          ),
          IconButton(
            icon: const Icon(Icons.more_vert_rounded),
            onPressed: () {},
          ),
        ],
      ),

      body: Column(
        children: [
          // ── Chat area ────────────────────────────────────────────────────
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _messages.length + (_isTyping ? 1 : 0) + 1, // +1 date divider
              itemBuilder: (_, i) {
                if (i == 0) return const _DateDivider(label: 'Today');

                final msgIndex = i - 1;

                // Typing indicator at the end
                if (_isTyping && msgIndex == _messages.length) {
                  return _TypingIndicator(animation: _dotAnim);
                }

                if (msgIndex >= _messages.length) return const SizedBox.shrink();
                return _MessageBubble(msg: _messages[msgIndex]);
              },
            ),
          ),

          // ── Input bar ────────────────────────────────────────────────────
          _InputBar(
            controller: _msgCtrl,
            onSend: _sendMessage,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Date divider
// ─────────────────────────────────────────────────────────────────────────────

class _DateDivider extends StatelessWidget {
  final String label;
  const _DateDivider({required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.primaryTint10,
            borderRadius: BorderRadius.circular(AppDimensions.radiusFull)),
          child: Text(label.toUpperCase(),
            style: GoogleFonts.lexend(
              fontSize: 10, fontWeight: FontWeight.w700,
              color: AppColors.primary, letterSpacing: 0.1)),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Message bubble
// ─────────────────────────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  final _Message msg;
  const _MessageBubble({required this.msg});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (msg.isMine) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12, left: 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  // br-none: matches chat_detail.html
                ),
                boxShadow: [BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  blurRadius: 6, offset: const Offset(0, 2))],
              ),
              child: msg.type == _MsgType.file
                  ? _FileContent(msg: msg)
                  : Text(msg.text,
                      style: GoogleFonts.lexend(
                        fontSize: 14, color: Colors.white, height: 1.5)),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(DateFormat('hh:mm a').format(msg.sentAt),
                  style: GoogleFonts.lexend(
                    fontSize: 10, color: AppColors.textSecondaryLight)),
                const SizedBox(width: 4),
                Icon(Icons.done_all_rounded,
                  size: 14,
                  color: msg.isRead ? AppColors.primary : AppColors.textSecondaryLight),
              ],
            ),
          ],
        ),
      );
    }

    // Received
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, right: 48),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.primaryTint10,
            child: Icon(Icons.person_rounded, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.65),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceDark : Colors.white,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                    // bl-none matches prototype
                  ),
                  boxShadow: isDark ? [] : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 6, offset: const Offset(0, 2))],
                ),
                child: Text(msg.text,
                  style: GoogleFonts.lexend(fontSize: 14, height: 1.5)),
              ),
              const SizedBox(height: 4),
              Text(DateFormat('hh:mm a').format(msg.sentAt),
                style: GoogleFonts.lexend(
                  fontSize: 10, color: AppColors.textSecondaryLight)),
            ],
          ),
        ],
      ),
    );
  }
}

class _FileContent extends StatelessWidget {
  final _Message msg;
  const _FileContent({required this.msg});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.20),
            borderRadius: BorderRadius.circular(AppDimensions.radiusSm)),
          child: const Icon(Icons.description_rounded,
              color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(msg.fileName ?? msg.text,
              style: GoogleFonts.lexend(
                fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
              maxLines: 1, overflow: TextOverflow.ellipsis),
            if (msg.fileSize != null)
              Text(msg.fileSize!,
                style: GoogleFonts.lexend(
                  fontSize: 10, color: Colors.white70,
                  fontWeight: FontWeight.w700)),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Typing indicator
// ─────────────────────────────────────────────────────────────────────────────

class _TypingIndicator extends StatelessWidget {
  final Animation<double> animation;
  const _TypingIndicator({required this.animation});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          const CircleAvatar(radius: 16, backgroundColor: AppColors.primaryTint10,
            child: Icon(Icons.person_rounded, size: 18, color: AppColors.primary)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(AppDimensions.radiusMd)),
            child: Row(
              children: List.generate(3, (i) => Padding(
                padding: EdgeInsets.only(left: i > 0 ? 4 : 0),
                child: FadeTransition(
                  opacity: Tween(begin: 0.3 + i * 0.2, end: 1.0).animate(
                    CurvedAnimation(parent: animation, curve: Curves.easeInOut)),
                  child: Container(
                    width: 7, height: 7,
                    decoration: const BoxDecoration(
                      color: AppColors.primary, shape: BoxShape.circle)),
                ),
              )),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Input bar
// ─────────────────────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;

  const _InputBar({required this.controller, required this.onSend});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: const Border(top: BorderSide(color: AppColors.borderLight))),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                // Attach
                IconButton(
                  icon: const Icon(Icons.add_circle_outline_rounded),
                  color: AppColors.textSecondaryLight,
                  onPressed: () {},
                  tooltip: 'Attach',
                ),

                // Text input
                Expanded(
                  child: TextField(
                    controller: controller,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend(),
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: GoogleFonts.lexend(fontSize: 14),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
                        borderSide: BorderSide.none),
                      filled: true,
                      fillColor: Theme.of(context).scaffoldBackgroundColor,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.attach_file_rounded, size: 20),
                        color: AppColors.textSecondaryLight,
                        onPressed: () {},
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                // Send button
                _SendButton(onSend: onSend),
              ],
            ),

            // Contextual toolbar
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
              child: Row(
                children: [
                  _ToolbarBtn(
                    icon: Icons.link_rounded,
                    label: 'Share Project',
                    onTap: () {},
                  ),
                  const SizedBox(width: 20),
                  _ToolbarBtn(
                    icon: Icons.schedule_rounded,
                    label: 'Schedule',
                    onTap: () {},
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SendButton extends StatefulWidget {
  final VoidCallback onSend;
  const _SendButton({required this.onSend});

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 120));
    _scale = Tween(begin: 1.0, end: 0.88)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeIn));
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) { _ctrl.reverse(); widget.onSend(); },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: AppColors.primary, shape: BoxShape.circle,
            boxShadow: [BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.3),
              blurRadius: 8, offset: const Offset(0, 3))]),
          child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _ToolbarBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ToolbarBtn({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textSecondaryLight),
          const SizedBox(width: 4),
          Text(label.toUpperCase(),
            style: GoogleFonts.lexend(
              fontSize: 9, fontWeight: FontWeight.w700,
              color: AppColors.textSecondaryLight, letterSpacing: 0.08)),
        ],
      ),
    );
  }
}
