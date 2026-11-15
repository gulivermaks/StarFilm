import 'package:flutter_test/flutter_test.dart';
import 'package:starfilm/core/models/version_comparator.dart';

void main() {
  test('VersionComparator compares +0.01 versions accurately including 0.69 -> 0.70', () {
    expect(VersionComparator.compare('0.61', '0.6'), greaterThan(0));
    expect(VersionComparator.compare('0.69', '0.61'), greaterThan(0));
    expect(VersionComparator.compare('0.70', '0.69'), greaterThan(0));
    expect(VersionComparator.compare('0.7', '0.69'), greaterThan(0));
    expect(VersionComparator.compare('0.99', '0.70'), greaterThan(0));
    expect(VersionComparator.compare('1.00', '0.99'), greaterThan(0));
    expect(VersionComparator.compare('v1.01', '1.00'), greaterThan(0));
    expect(VersionComparator.compare('0.70', '0.7'), 0);

    expect(VersionComparator.formatFromCode(1), '0.01');
    expect(VersionComparator.formatFromCode(10), '0.10');
    expect(VersionComparator.formatFromCode(70), '0.70');
    expect(VersionComparator.formatFromCode(100), '1.00');
  });
}
