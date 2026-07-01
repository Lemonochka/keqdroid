import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/utils/subscription_diff.dart';

Subscription _sub(String id, {String name = 'n', int serverCount = 0}) =>
    Subscription(
      id: id,
      name: name,
      url: 'https://example.com/$id',
      serverCount: serverCount,
    );

void main() {
  group('subscriptionsDiffer', () {
    test('identical reference is not a change', () {
      final list = [_sub('a'), _sub('b')];
      expect(subscriptionsDiffer(list, list), isFalse);
    });

    test('equal content in same order is not a change', () {
      expect(
        subscriptionsDiffer([_sub('a'), _sub('b')], [_sub('a'), _sub('b')]),
        isFalse,
      );
    });

    test('reordering the same items is NOT a change (compared by id)', () {
      expect(
        subscriptionsDiffer([_sub('a'), _sub('b')], [_sub('b'), _sub('a')]),
        isFalse,
      );
    });

    test('different length is a change', () {
      expect(
        subscriptionsDiffer([_sub('a')], [_sub('a'), _sub('b')]),
        isTrue,
      );
    });

    test('same length but different ids is a change', () {
      expect(
        subscriptionsDiffer([_sub('a'), _sub('b')], [_sub('a'), _sub('c')]),
        isTrue,
      );
    });

    test('a changed field (serverCount) on a matching id is a change', () {
      expect(
        subscriptionsDiffer(
          [_sub('a', serverCount: 1)],
          [_sub('a', serverCount: 2)],
        ),
        isTrue,
      );
    });

    test('a changed name on a matching id is a change', () {
      expect(
        subscriptionsDiffer(
          [_sub('a', name: 'old')],
          [_sub('a', name: 'new')],
        ),
        isTrue,
      );
    });
  });
}
