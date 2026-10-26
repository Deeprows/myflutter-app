import 'package:flutter_test/flutter_test.dart';

import 'package:footbolive/screens/fan_widgets.dart';
import 'package:footbolive/models/fan_prediction.dart';

Map<String, dynamic> pick(int h, int a, int? rh, int? ra, int kickoff) => {
  'home': h,
  'away': a,
  'result_home': rh,
  'result_away': ra,
  'kickoff': kickoff,
};

void main() {
  group('Prediction markets', () {
    Map<String, dynamic> market(
      String type,
      String selection,
      int home,
      int away,
    ) => {
      'market': type,
      'selection': selection,
      'home': 2,
      'away': 1,
      'result_home': home,
      'result_away': away,
    };
    test('outcomes, double chance and BTTS settle from confirmed scores', () {
      expect(fanPickPoints(market('result', 'X', 1, 1)), 1);
      expect(fanPickPoints(market('double_chance', '12', 1, 1)), 0);
      expect(fanPickPoints(market('btts', 'yes', 2, 1)), 1);
      expect(fanPickPoints(market('btts', 'no', 2, 0)), 1);
    });
    test('integer totals push and do not become settled wins or losses', () {
      final p = market('totals', 'over_1', 1, 0);
      expect(fanPredictionPush(p), true);
      expect(fanPickPoints(p), isNull);
      expect(FanStats.from([p]).settled, 0);
      expect(fanPickPoints(market('totals', 'over_1', 2, 0)), 1);
      expect(fanPickPoints(market('totals', 'over_2.5', 1, 1)), 0);
      expect(fanPickPoints(market('totals', 'over_2.5', 2, 1)), 1);
    });
  });
  group('Fan Zone scoring', () {
    test('exact score is 3, right outcome is 1, miss is 0', () {
      expect(fanPickPoints(pick(2, 1, 2, 1, 1)), 3);
      expect(fanPickPoints(pick(2, 1, 3, 0, 1)), 1);
      expect(fanPickPoints(pick(1, 1, 0, 0, 1)), 1);
      expect(fanPickPoints(pick(2, 1, 0, 1, 1)), 0);
    });

    test('unsettled picks have no points', () {
      expect(fanPickPoints(pick(2, 1, null, null, 1)), isNull);
    });
  });

  group('Fan Zone stats', () {
    test('totals, accuracy and current streak', () {
      final stats = FanStats.from([
        pick(1, 0, 1, 0, 5), // newest: exact
        pick(2, 0, 3, 1, 4), // winner
        pick(0, 1, 2, 0, 3), // miss, breaks the streak
        pick(1, 1, 1, 1, 2), // exact
        pick(1, 0, null, null, 6), // not settled yet
      ]);
      expect(stats.picks, 5);
      expect(stats.settled, 4);
      expect(stats.points, 7);
      expect(stats.exact, 2);
      expect(stats.accuracy, 75);
      expect(stats.streak, 2);
      expect(stats.bestStreak, 2);
    });

    test('empty list is safe', () {
      final stats = FanStats.from([]);
      expect(stats.accuracy, 0);
      expect(stats.streak, 0);
    });
  });

  group('Fan levels', () {
    test('levels and next level', () {
      expect(fanLevelFor(0).name, 'Rookie');
      expect(fanLevelFor(15).name, 'Pundit');
      expect(fanLevelFor(500).name, 'Legend');
      expect(fanNextLevel(4)!.name, 'Regular');
      expect(fanNextLevel(500), isNull);
    });
  });

  group('Fan Zone formatting', () {
    test('countdown', () {
      expect(fanCountdown(const Duration(minutes: 5)), '5m');
      expect(fanCountdown(const Duration(hours: 2, minutes: 15)), '2h 15m');
      expect(fanCountdown(const Duration(days: 2, hours: 3)), '2d 3h');
    });

    test('day labels', () {
      final now = DateTime(2026, 10, 24, 12);
      expect(fanDayLabel(DateTime(2026, 10, 24, 20), now), 'Today');
      expect(fanDayLabel(DateTime(2026, 10, 25, 9), now), 'Tomorrow');
    });
  });
}
