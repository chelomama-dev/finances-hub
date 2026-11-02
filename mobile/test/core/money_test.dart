import 'package:decimal/decimal.dart';
import 'package:finances_hub/core/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Money eur(String amount) => Money(Decimal.parse(amount), 'EUR');

  group('format', () {
    test('uses Spanish separators and the euro sign', () => expect(eur('1234.56').format(), '1.234,56 €'));
    test('groups every three digits', () => expect(eur('1234567.8').format(), '1.234.567,80 €'));
    test('shows expenses with a minus sign', () => expect(eur('-23.40').format(), '-23,40 €'));
    test('always shows two decimals', () => expect(eur('1650').format(), '1.650,00 €'));
    test('small amounts have no group separator', () => expect(eur('0.5').format(), '0,50 €'));
    test('shows the currency the API sends', () {
      final formatted = Money(Decimal.parse('10'), 'USD').format();
      expect(formatted, contains('\$'));
      expect(formatted, isNot(contains('€')));
    });
  });

  test('parses the API shape without going through a double', () {
    // 0.1 + 0.2 is not 0.3 in floating point; with decimals it is
    final sum = Money.fromJson({'amount': '0.1', 'currency': 'EUR'}).amount +
        Money.fromJson({'amount': '0.2', 'currency': 'EUR'}).amount;

    expect(sum, Decimal.parse('0.3'));
  });

  test('knows an expense from its sign', () {
    expect(eur('-0.01').isNegative, isTrue);
    expect(eur('0').isNegative, isFalse);
  });
}
