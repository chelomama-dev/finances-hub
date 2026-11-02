import 'package:finances_hub/core/dates.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('es_ES'));

  final now = DateTime(2026, 11, 2, 12);

  test('says how long ago a sync was', () {
    expect(timeAgo(now.subtract(const Duration(seconds: 20)), now: now), 'hace un momento');
    expect(timeAgo(now.subtract(const Duration(minutes: 5)), now: now), 'hace 5 min');
    expect(timeAgo(now.subtract(const Duration(hours: 3)), now: now), 'hace 3 h');
    expect(timeAgo(now.subtract(const Duration(days: 2)), now: now), 'hace 2 días');
  });

  test('names the days of the list', () {
    expect(dayHeader(DateTime(2026, 11, 2), now: now), 'Hoy');
    expect(dayHeader(DateTime(2026, 11, 1), now: now), 'Ayer');
    expect(dayHeader(DateTime(2026, 10, 30), now: now), 'viernes, 30 de octubre');
    expect(dayHeader(DateTime(2025, 10, 30), now: now), contains('2025'));
  });

  test('formats query dates as the API expects', () => expect(apiDate(DateTime(2026, 1, 5)), '2026-01-05'));
}
