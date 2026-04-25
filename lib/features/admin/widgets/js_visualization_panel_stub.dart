import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class JsVisualizationPanel extends StatelessWidget {
  const JsVisualizationPanel({
    super.key,
    required this.chartId,
    required this.title,
    required this.labels,
    required this.values,
    this.height = 260,
    this.color = const Color(0xFF1152D4),
  });

  final String chartId;
  final String title;
  final List<String> labels;
  final List<double> values;
  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final maxValue = values.isEmpty
        ? 1.0
        : values.reduce((a, b) => a > b ? a : b).clamp(0.001, double.infinity);

    return Container(
      height: height,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$title (Flutter fallback)',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: values.length,
              itemBuilder: (context, index) {
                final label = labels.length > index ? labels[index] : 'Item ${index + 1}';
                final value = values[index];
                final fraction = (value / maxValue).clamp(0.0, 1.0);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 110,
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(fontSize: 11),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: LinearProgressIndicator(
                          value: fraction,
                          minHeight: 8,
                          borderRadius: BorderRadius.circular(999),
                          color: color,
                          backgroundColor: color.withValues(alpha: 0.14),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 44,
                        child: Text(
                          value.toStringAsFixed(2),
                          textAlign: TextAlign.end,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
