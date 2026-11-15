import 'package:flutter_test/flutter_test.dart';
import 'package:penguin_shared/penguin_shared.dart';

void main() {
  test('every status has its own look and wording', () {
    final looks = {
      for (final status in reportStatuses)
        (reportStyle(status).pin, reportStyle(status).symbol),
    };
    final labels = {for (final status in reportStatuses) reportStyle(status).label};
    // A repeat would collapse two entries into one, making a set smaller than the list
    expect(looks.length, reportStatuses.length);
    expect(labels.length, reportStatuses.length);
  });

  test('the city workflow statuses read the way civilians expect', () {
    expect(reportStyle('ACTIVE').label, 'Being repaired');
    expect(reportStyle('COMPLETED').label, 'Fixed');
    expect(reportStyle('DISMISSED').label, isNot('Checking'));
  });

  test('only PENDING (and unknown statuses) fall into the default case', () {
    final fallback = reportStyle('SOMETHING_NEW');
    expect(reportStyle('PENDING'), fallback);
    for (final status in reportStatuses.where((s) => s != 'PENDING')) {
      expect(reportStyle(status), isNot(fallback), reason: status);
    }
  });
}
