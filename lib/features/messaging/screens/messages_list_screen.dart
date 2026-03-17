import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/router/route_names.dart';
import '../bloc/message_cubit.dart';

class MessagesListScreen extends StatefulWidget {
  const MessagesListScreen({super.key});

  @override
  State<MessagesListScreen> createState() => _MessagesListScreenState();
}

class _MessagesListScreenState extends State<MessagesListScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _onRefresh() {
    return context.read<MessageCubit>().loadConversations();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Messages',
          style: GoogleFonts.lexend(fontWeight: FontWeight.w700),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                  'Compose flow is coming next. Open a profile and tap Message for now.'),
            ),
          );
        },
        icon: const Icon(Icons.edit_rounded),
        label: Text(
          'Compose',
          style: GoogleFonts.lexend(fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: context.read<MessageCubit>().searchConversations,
              decoration: InputDecoration(
                hintText: 'Search conversations...',
                hintStyle: GoogleFonts.lexend(fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          Expanded(
            child: BlocBuilder<MessageCubit, MessageState>(
              builder: (context, state) {
                if (state is ConversationsLoading || state is MessageInitial) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (state is MessageError) {
                  return _ErrorView(
                    message: state.message,
                    onRetry: () =>
                        context.read<MessageCubit>().loadConversations(),
                  );
                }

                if (state is! ConversationsLoaded) {
                  return const SizedBox.shrink();
                }

                if (state.conversations.isEmpty) {
                  return _EmptyView(query: state.query);
                }

                return RefreshIndicator(
                  onRefresh: _onRefresh,
                  child: ListView.builder(
                    itemCount: state.conversations.length,
                    itemBuilder: (context, index) {
                      final convo = state.conversations[index];
                      return Dismissible(
                        key: Key(convo.id),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (_) =>
                            _confirmDelete(context, convo.peerName),
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 16),
                          color: AppColors.danger,
                          child: const Icon(
                            Icons.delete_outline_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        onDismissed: (_) => context
                            .read<MessageCubit>()
                            .deleteConversation(convo.id),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 6,
                          ),
                          leading: Stack(
                            children: [
                              CircleAvatar(
                                radius: 26,
                                backgroundColor: AppColors.primaryTint10,
                                backgroundImage: convo.peerPhotoUrl != null
                                    ? NetworkImage(convo.peerPhotoUrl!)
                                    : null,
                                child: convo.peerPhotoUrl == null
                                    ? Text(
                                        convo.peerName.isNotEmpty
                                            ? convo.peerName[0].toUpperCase()
                                            : '?',
                                        style: GoogleFonts.lexend(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.primary,
                                        ),
                                      )
                                    : null,
                              ),
                            ],
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  convo.peerName,
                                  style: GoogleFonts.lexend(
                                    fontSize: 14,
                                    fontWeight: convo.unreadCount > 0
                                        ? FontWeight.w700
                                        : FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (convo.isPeerLecturer)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.roleLecturer
                                        .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(
                                        AppDimensions.radiusFull),
                                  ),
                                  child: Text(
                                    'Lecturer',
                                    style: GoogleFonts.lexend(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.roleLecturer,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Text(
                            convo.lastMessage,
                            style: GoogleFonts.lexend(
                              fontSize: 12,
                              color: convo.unreadCount > 0
                                  ? AppColors.textPrimaryLight
                                  : AppColors.textSecondaryLight,
                              fontWeight: convo.unreadCount > 0
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                timeago.format(convo.lastMessageAt,
                                    allowFromNow: true),
                                style: GoogleFonts.lexend(
                                  fontSize: 10,
                                  color: AppColors.textSecondaryLight,
                                ),
                              ),
                              const SizedBox(height: 4),
                              if (convo.unreadCount > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    borderRadius: BorderRadius.circular(
                                        AppDimensions.radiusFull),
                                  ),
                                  child: Text(
                                    convo.unreadCount.toString(),
                                    style: GoogleFonts.lexend(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          onTap: () {
                            context.push(
                              Routes.chat(convo.id),
                              extra: {
                                'peerName': convo.peerName,
                                'peerPhotoUrl': convo.peerPhotoUrl,
                                'isPeerLecturer': convo.isPeerLecturer,
                              },
                            );
                          },
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context, String peerName) async {
    final decision = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete conversation?'),
          content:
              Text('This removes your chat with $peerName on this device.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    return decision ?? false;
  }
}

class _EmptyView extends StatelessWidget {
  final String query;

  const _EmptyView({required this.query});

  @override
  Widget build(BuildContext context) {
    final hasQuery = query.trim().isNotEmpty;
    return Center(
      child: Text(
        hasQuery
            ? 'No conversations match your search.'
            : 'No conversations yet.',
        style: GoogleFonts.lexend(color: AppColors.textSecondaryLight),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 42),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
