import 'package:intl/intl.dart';

/// "hace 5 min", from a UTC timestamp, for "Actualizado hace X".
String timeAgo(DateTime timestamp, {DateTime? now}) {
  final elapsed = (now ?? DateTime.now()).difference(timestamp.toLocal());
  if (elapsed.inMinutes < 1) return 'hace un momento';
  if (elapsed.inMinutes < 60) return 'hace ${elapsed.inMinutes} min';
  if (elapsed.inHours < 24) return 'hace ${elapsed.inHours} h';
  final days = elapsed.inDays;
  return days == 1 ? 'hace 1 día' : 'hace $days días';
}

/// A transaction's date in its row: "Hoy", "Ayer", "30 oct", with the year only if it isn't the current one
/// ("30 oct 2025").
String rowDate(DateTime day, {DateTime? now}) {
  final today = _dateOnly(now ?? DateTime.now());
  final date = _dateOnly(day);
  if (date == today) return 'Hoy';
  if (date == today.subtract(const Duration(days: 1))) return 'Ayer';

  final pattern = date.year == today.year ? DateFormat('d MMM', 'es_ES') : DateFormat('d MMM y', 'es_ES');
  return pattern.format(date);
}

/// A plain date: "31/01/2027", in local time.
String shortDate(DateTime date) => DateFormat('dd/MM/yyyy', 'es_ES').format(date.toLocal());

/// `2026-11-01`, the API's date format for query parameters.
String apiDate(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
