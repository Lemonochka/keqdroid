import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/subscription.dart';

/// Две настройки автовыбора у подписки, и они не одно и то же: одна про то,
/// видно ли переключатель, вторая — про то, включён ли он.
void main() {
  const plain = Subscription(id: 'a', name: 'n', url: 'u');

  test('по умолчанию плашки нет и автовыбор выключен', () {
    expect(plain.autoSelectVisible, isFalse);
    expect(plain.autoSelect, isFalse);
    // Умолчание в каждой записи — лишний шум в файле подписок.
    expect(plain.toJson().containsKey('autoSelectVisible'), isFalse);
    expect(plain.toJson().containsKey('autoSelect'), isFalse);
  });

  test('новая подписка приходит с кнопкой «Авто», но не нажатой', () {
    final added = Subscription.create(name: 'n', url: 'https://a.example/sub');
    expect(added.autoSelectVisible, isTrue);
    expect(added.autoSelect, isFalse);
    expect(Subscription.fromJson(added.toJson()).autoSelectVisible, isTrue);
  });

  test('оба флага переживают запись и чтение', () {
    const sub = Subscription(
      id: 'a',
      name: 'n',
      url: 'u',
      autoSelectVisible: true,
      autoSelect: true,
    );

    final restored = Subscription.fromJson(sub.toJson());
    expect(restored.autoSelectVisible, isTrue);
    expect(restored.autoSelect, isTrue);
  });

  test('подписка старого формата читается без них', () {
    final restored = Subscription.fromJson({
      'id': 'a',
      'name': 'n',
      'url': 'u',
    });

    expect(restored.autoSelectVisible, isFalse);
    expect(restored.autoSelect, isFalse);
  });
}
