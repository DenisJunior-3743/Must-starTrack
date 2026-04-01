import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/di/injection_container.dart';
import '../../../data/remote/firestore_service.dart';

class ChatbotAnalyticsScreen extends StatefulWidget {
  const ChatbotAnalyticsScreen({super.key});

  @override
  State<ChatbotAnalyticsScreen> createState() => _ChatbotAnalyticsScreenState();
}

class _ChatbotAnalyticsScreenState extends State<ChatbotAnalyticsScreen> {
  final _firestore = sl<FirestoreService>();

  bool _loading = true;
  int _total = 0;
  int _faqCount = 0;
  int _aiCount = 0;
  int _fallbackCount = 0;
  int _feedbackCount = 0;
  int _helpfulCount = 0;
  double _avgConfidence = 0;
  List<Map<String, dynamic>> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await _firestore.getRecentChatbotInteractions(limit: 250);
      var faq = 0;
      var ai = 0;
      var fallback = 0;
      var feedback = 0;
      var helpful = 0;
      double confidenceSum = 0;
      int confidenceCount = 0;

      for (final row in rows) {
        final source = row['source']?.toString() ?? '';
        if (source == 'faq') faq++;
        if (source == 'ai') ai++;
        if (source == 'fallback') fallback++;

        final c = (row['confidence'] as num?)?.toDouble();
        if (c != null) {
          confidenceSum += c;
          confidenceCount++;
        }

        if (row['is_helpful'] != null) {
          feedback++;
          if (row['is_helpful'] == true) helpful++;
        }
      }

      if (!mounted) return;
      setState(() {
        _rows = rows;
        _total = rows.length;
        _faqCount = faq;
        _aiCount = ai;
        _fallbackCount = fallback;
        _feedbackCount = feedback;
        _helpfulCount = helpful;
        _avgConfidence = confidenceCount == 0 ? 0 : (confidenceSum / confidenceCount);
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _pct(int top, int bottom) {
    if (bottom <= 0) return '0%';
    final v = (top / bottom) * 100;
    return '${v.toStringAsFixed(1)}%';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chatbot Accuracy Analytics'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _metricCard('Total interactions', '$_total', Icons.forum_rounded),
                    _metricCard('Average confidence', '${(_avgConfidence * 100).toStringAsFixed(1)}%', Icons.speed_rounded),
                    _metricCard('Feedback coverage', _pct(_feedbackCount, _total), Icons.rate_review_rounded),
                    _metricCard('Helpful ratio', _pct(_helpfulCount, _feedbackCount), Icons.thumb_up_rounded),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Source Mix',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondaryLight,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        _sourceRow('FAQ answers', _faqCount, _total, const Color(0xFF0EA5E9)),
                        _sourceRow('AI fallback', _aiCount, _total, const Color(0xFF6366F1)),
                        _sourceRow('Safe fallback', _fallbackCount, _total, const Color(0xFFF59E0B)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Recent Traces',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondaryLight,
                  ),
                ),
                const SizedBox(height: 8),
                if (_rows.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(14),
                      child: Text('No chatbot traces available yet.'),
                    ),
                  ),
                ..._rows.take(80).map((row) => _traceCard(context, row)),
              ],
            ),
    );
  }

  Widget _metricCard(String label, String value, IconData icon) {
    return Container(
      width: 170,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: AppColors.textSecondaryLight,
                  ),
                ),
                Text(
                  value,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sourceRow(String label, int count, int total, Color color) {
    final ratio = total == 0 ? 0.0 : count / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '$count (${_pct(count, total)})',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: AppColors.textSecondaryLight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: ratio.clamp(0.0, 1.0),
            minHeight: 8,
            color: color,
            backgroundColor: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
          ),
        ],
      ),
    );
  }

  Widget _traceCard(BuildContext context, Map<String, dynamic> row) {
    final source = row['source']?.toString() ?? 'unknown';
    final confidence = ((row['confidence'] as num?)?.toDouble() ?? 0) * 100;
    final helpful = row['is_helpful'];
    final created = row['created_at']?.toString() ?? '';

    final sourceColor = switch (source) {
      'faq' => const Color(0xFF0EA5E9),
      'ai' => const Color(0xFF6366F1),
      _ => const Color(0xFFF59E0B),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: sourceColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    source.toUpperCase(),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: sourceColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Conf ${confidence.toStringAsFixed(0)}%',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: AppColors.textSecondaryLight,
                  ),
                ),
                const Spacer(),
                Text(
                  helpful == null
                      ? 'no feedback'
                      : (helpful == true ? 'helpful' : 'not helpful'),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: helpful == null
                        ? AppColors.textSecondaryLight
                        : (helpful == true ? const Color(0xFF059669) : AppColors.danger),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              row['question']?.toString() ?? '-',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              row['answer']?.toString() ?? '-',
              style: GoogleFonts.plusJakartaSans(fontSize: 12),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            if (created.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                created,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  color: AppColors.textSecondaryLight,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
