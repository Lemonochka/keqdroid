import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/utils/fake_ip.dart';
import 'package:keqdroid/utils/mihomo_config_gen.dart';

// Список не подменять один на все ядра: mihomo читает его как есть, xray и
// sing-box в переводе на синтаксис правил.
void main() {
  test('mihomo берёт тот же список', () {
    expect(MihomoConfigGen.fakeIpFilter, same(kFakeIpFilter));
  });

  test('перевод в синтаксис правил', () {
    final rules = fakeIpFilterAsRules();
    expect(rules, hasLength(kFakeIpFilter.length));
    expect(rules, contains('full:localhost'));
    expect(rules, contains('full:connectivitycheck.gstatic.com'));
    expect(rules, contains('domain:lan'));
    expect(rules, contains('domain:msftconnecttest.com'));
    expect(rules, contains(r'regexp:^time\.[^.]+\.com$'));
  });

  test('регулярное выражение ловит одну метку, а не любую строку', () {
    final pattern = RegExp(r'^time\.[^.]+\.com$');
    expect(pattern.hasMatch('time.windows.com'), isTrue);
    expect(pattern.hasMatch('time.a.b.com'), isFalse);
  });
}
