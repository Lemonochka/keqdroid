import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/utils/hysteria_uri.dart';

void main() {
  test('parses obfs and builds finalmask', () {
    const uri =
        'hysteria2://pwd@host:443?obfs=salamander&obfs-password=abc&sni=host';
    final p = HysteriaLinkParams.fromConfig(uri);
    expect(p.hasSalamanderObfs, isTrue);
    expect(p.buildFinalmask(), isNotNull);
  });

  // Схема `hysteria://` носит обе версии, и различаются они только параметрами.
  // Ошибка в любую сторону дорогая: первую соберём как вторую — молчащий
  // сервер; вторую примем за первую — выбросим рабочий узел.
  group('версия по признакам ссылки', () {
    test('первую узнаём по её собственным параметрам', () {
      for (final link in [
        'hysteria://host:443?auth=x&upmbps=100&downmbps=200',
        'hysteria://host:443?auth=x&downmbps=200',
        'hysteria://host:443?auth=x&peer=sni.example',
        'hysteria://host:443?auth=x&protocol=faketcp',
        'hysteria://host:443?auth_str=secret',
        'hysteria://host:443?auth=x&obfsParam=abc',
        'hysteria://host:443?auth=x&version=1',
      ]) {
        expect(HysteriaLinkParams.isV1(link), isTrue, reason: link);
      }
    });

    test('вторая под старой схемой остаётся второй', () {
      for (final link in [
        'hysteria://pwd@host:443?sni=host&obfs=salamander&obfs-password=abc',
        'hysteria://host:443?auth=secret&insecure=0&sni=host',
        'hysteria://pwd@host:443?up=100&down=200',
      ]) {
        expect(HysteriaLinkParams.isV1(link), isFalse, reason: link);
      }
    });

    test('чужие схемы не трогаем', () {
      expect(HysteriaLinkParams.isV1('hysteria2://pwd@host:443?upmbps=100'),
          isFalse);
      expect(HysteriaLinkParams.isV1('vless://uuid@host:443?peer=x'), isFalse);
    });
  });

  test('formatBandwidth adds mbps suffix for plain numbers', () {
    expect(HysteriaLinkParams.formatBandwidth('100'), '100mbps');
    expect(HysteriaLinkParams.formatBandwidth('50 Mbps'), '50 Mbps');
  });
}
