import 'package:flutter/material.dart';

/// Series colours for the charts: a categorical palette checked for colour-blind readers, in a fixed order that
/// keeps neighbouring slices apart, with its own steps for the dark theme. Text never takes these colours.
class ChartColors {
  const ChartColors._(this.series, this.other);

  factory ChartColors.of(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? _dark : _light;

  static const _light = ChartColors._([
    Color(0xFF2A78D6), // blue
    Color(0xFFEB6834), // orange
    Color(0xFF1BAF7A), // aqua
    Color(0xFFEDA100), // yellow
    Color(0xFFE87BA4), // magenta
  ], Color(0xFF9E9D98));

  static const _dark = ChartColors._([
    Color(0xFF3987E5),
    Color(0xFFD95926),
    Color(0xFF199E70),
    Color(0xFFC98500),
    Color(0xFFD55181),
  ], Color(0xFF6E6D68));

  /// One per top description, in order.
  final List<Color> series;

  /// "Otros": a neutral grey, so it never looks like one more description.
  final Color other;

  Color get income => series[0];
  Color get expenses => series[1];
}
