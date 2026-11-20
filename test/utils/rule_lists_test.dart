import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/utils/rule_lists.dart';

/// Списки по ссылке: какие записи поля — ссылки и какие домены берутся из
/// списка фильтров. VPN блокирует соединение целиком, поэтому из AdBlock
/// годится только то, что значит «весь домен».
void main() {
  group('ссылки в поле', () {
    test('находятся среди обычных записей, без повторов', () {
      const field =
          'ru, vk.com\n'
          'https://lists.example/ads.txt,\n'
          'geosite:category-ads-all, http://plain.example/x\n'
          'https://lists.example/ads.txt';
      expect(ruleListUrls(field), [
        'https://lists.example/ads.txt',
        'http://plain.example/x',
      ]);
    });

    test('убираются из поля, остальное остаётся', () {
      expect(
        routingEntries(
          withoutRuleListUrls('ru, https://a.example/l.txt\nvk.com'),
        ),
        ['ru', 'vk.com'],
      );
    });

    test('поле без ссылок возвращается байт в байт', () {
      const field = 'ru,  vk.com\n\n10.0.0.0/8';
      expect(withoutRuleListUrls(field), same(field));
    });
  });

  group('разбор списка фильтров', () {
    test('AdBlock: домен целиком, с безобидными условиями', () {
      expect(
        parseFilterList('''
[Adblock Plus 2.0]
! Title: test
||ads.example.com^
||track.example.org^|
||important.example^\$important
||Upper.Example.NET^
'''),
        {
          'ads.example.com',
          'track.example.org',
          'important.example',
          'upper.example.net',
        },
      );
    });

    test(
      'AdBlock: путь, условия, регулярки и скрытие элементов пропускаются',
      () {
        expect(
          parseFilterList(r'''
||example.com/ads/banner.js
||thirdparty.example^$third-party
||scoped.example^$domain=site.example
||prefix.example.
||ads
.subdomains-only.example^
/banner\d+\.example/
example.com##.ad-banner
##.global-ad
example.com#@#.ad
||*.wild.example^
'''),
          isEmpty,
        );
      },
    );

    test('исключение @@ убирает домен', () {
      expect(
        parseFilterList('||ads.example^\n||ok.example^\n@@||ok.example^'),
        {'ads.example'},
      );
    });

    // Так в списке AdGuard DNS снимают ложные срабатывания.
    test(r'$badfilter отменяет такое же правило', () {
      expect(
        parseFilterList(r'''
||ads.example^
||fp.example^
||fp.example^$badfilter
||fp2.example^$important
||fp2.example^$important,badfilter
'''),
        {'ads.example'},
      );
    });

    // В DNS-списках `||host` без `^` пишут для имени с зоной целиком.
    test('полное имя без ^ — тоже домен', () {
      expect(parseFilterList('||id-msp.newsbreak.example'), {
        'id-msp.newsbreak.example',
      });
    });

    test('hosts: адреса-заглушки, комментарии, имена самой машины', () {
      expect(
        parseFilterList('''
# StevenBlack
127.0.0.1 localhost
::1 localhost ip6-localhost
0.0.0.0 0.0.0.0
0.0.0.0 ads.example.com # comment
0.0.0.0 a.example b.example
192.168.1.10 printer.lan
'''),
        {'ads.example.com', 'a.example', 'b.example'},
      );
    });

    test('голые домены, с точкой и звёздочкой в начале', () {
      expect(
        parseFilterList(
          'ads.example\n.track.example\n*.wild.example\n'
          'not a domain\n1.2.3.4\nlocalhost\n',
        ),
        {'ads.example', 'track.example', 'wild.example'},
      );
    });

    test('Windows-переводы строк и BOM не мешают', () {
      expect(parseFilterList('﻿||a.example^\r\n0.0.0.0 b.example\r\n'), {
        'a.example',
        'b.example',
      });
    });
  });
}
