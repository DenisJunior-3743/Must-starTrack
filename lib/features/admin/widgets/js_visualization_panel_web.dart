// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter

import 'dart:html' as html;
import 'dart:math' as math;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

class JsVisualizationPanel extends StatefulWidget {
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
  State<JsVisualizationPanel> createState() => _JsVisualizationPanelState();
}

class _JsVisualizationPanelState extends State<JsVisualizationPanel> {
  static final Set<String> _registeredViewTypes = <String>{};

  late String _viewType;

  @override
  void initState() {
    super.initState();
    _viewType = _buildViewType();
    _registerIfNeeded();
  }

  @override
  void didUpdateWidget(covariant JsVisualizationPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextViewType = _buildViewType();
    if (nextViewType == _viewType) return;
    setState(() {
      _viewType = nextViewType;
      _registerIfNeeded();
    });
  }

  String _buildViewType() {
    final signature = Object.hashAll([
      widget.title,
      widget.color,
      ...widget.labels,
      ...widget.values.map((value) => value.toStringAsFixed(4)),
    ]).abs();
    return 'js-chart-${widget.chartId}-${widget.labels.length}-${widget.values.length}-$signature';
  }

  void _registerIfNeeded() {
    if (_registeredViewTypes.contains(_viewType)) {
      return;
    }

    final colorHex = _toHex(widget.color);
    final canvasId = 'canvas-${widget.chartId}-${widget.labels.length}';

    ui_web.platformViewRegistry.registerViewFactory(_viewType, (int _) {
      final root = html.DivElement()
        ..style.width = '100%'
        ..style.height = '${widget.height}px'
        ..style.boxSizing = 'border-box'
        ..style.overflow = 'hidden'
        ..style.padding = '12px 8px 22px';

      final title = html.DivElement()
        ..text = widget.title
        ..style.fontWeight = '700'
        ..style.fontSize = '12px'
        ..style.lineHeight = '16px'
        ..style.marginBottom = '10px';

      final canvas = html.CanvasElement()
        ..id = canvasId
        ..style.width = '100%'
        ..style.height = '${math.max(90, widget.height - 62)}px'
        ..style.display = 'block';

      root.children.add(title);
      root.children.add(canvas);

      final renderScript = html.ScriptElement()
        ..type = 'text/javascript'
        ..text = '''
(function () {
  if (typeof window.mustStartrackRenderChart !== 'function') return;
  window.mustStartrackRenderChart({
    canvasId: '$canvasId',
    title: ${_jsString(widget.title)},
    labels: ${_jsArray(widget.labels)},
    values: ${_jsNumberArray(widget.values)},
    colorHex: '$colorHex'
  });
})();
''';

      root.children.add(renderScript);
      return root;
    });

    _registeredViewTypes.add(_viewType);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: HtmlElementView(viewType: _viewType),
    );
  }

  String _toHex(Color color) {
    final r = (color.r * 255.0)
        .round()
        .clamp(0, 255)
        .toRadixString(16)
        .padLeft(2, '0');
    final g = (color.g * 255.0)
        .round()
        .clamp(0, 255)
        .toRadixString(16)
        .padLeft(2, '0');
    final b = (color.b * 255.0)
        .round()
        .clamp(0, 255)
        .toRadixString(16)
        .padLeft(2, '0');
    return '#$r$g$b';
  }

  String _jsString(String input) {
    final escaped = input
        .replaceAll(r'\\', r'\\\\')
        .replaceAll("'", r"\\'")
        .replaceAll('\n', r'\\n');
    return "'$escaped'";
  }

  String _jsArray(List<String> input) {
    return '[${input.map(_jsString).join(',')}]';
  }

  String _jsNumberArray(List<double> input) {
    return '[${input.map((e) => e.toStringAsFixed(6)).join(',')}]';
  }
}
