import 'package:flutter_test/flutter_test.dart';

import 'package:frontend/core/widgets/formatting.dart';

void main() {
  group('formatNumber', () {
    test('keeps whole numbers whole', () {
      expect(formatNumber(0), '0');
      expect(formatNumber(12), '12');
    });

    test('rounds decimals to two places', () {
      expect(formatNumber(0.16800000000000007), '0.17');
      expect(formatNumber(0.006), '0.01');
      expect(formatNumber(12.5), '12.5');
      expect(formatNumber(12.345), '12.35');
    });

    test('drops the decimals when rounding makes the number whole', () {
      expect(formatNumber(0.999), '1');
    });
  });

  test('formatLiters adds the unit', () {
    expect(formatLiters(0.16800000000000007), '0.17 L');
  });
}
