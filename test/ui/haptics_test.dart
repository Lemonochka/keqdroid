import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/shared/ui/haptics.dart';

void main() {
  test('отдача идёт только когда включена И платформа её умеет', () {
    expect(
      shouldFireHaptics(enabled: true, platformSupports: true),
      isTrue,
    );
    // Настройка выключена — молчим даже на телефоне.
    expect(
      shouldFireHaptics(enabled: false, platformSupports: true),
      isFalse,
    );
    // Десктоп: вибромотора нет, настройка значения не имеет.
    expect(
      shouldFireHaptics(enabled: true, platformSupports: false),
      isFalse,
    );
    expect(
      shouldFireHaptics(enabled: false, platformSupports: false),
      isFalse,
    );
  });

  test('по умолчанию отдача включена', () {
    expect(AppHaptics.enabled, isTrue);
  });
}
