import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/utils/server_field_rules.dart';

/// Правила взяты из ядра: `docs/config/transport.md` (матрицы «транспорт ×
/// защита» и «протокол × защита»), `docs/config/outbounds/vless.md` (условия
/// Vision) и `infra/conf/vless.go` (разбор `flow` и `encryption`).
void main() {
  group('Vision', () {
    test('живёт на TCP с TLS и с REALITY', () {
      for (final security in ['tls', 'reality']) {
        expect(
          visionWorksWith(
            transport: 'tcp',
            security: security,
            encryption: 'none',
          ),
          isTrue,
          reason: security,
        );
      }
      // `raw` — то же самое под новым именем.
      expect(
        visionWorksWith(transport: 'raw', security: 'tls', encryption: ''),
        isTrue,
      );
    });

    test('на xhttp его нет — с этого началась жалоба', () {
      expect(
        visionWorksWith(
          transport: 'xhttp',
          security: 'reality',
          encryption: 'none',
        ),
        isFalse,
      );
      expect(
        serverRuleIssues(
          protocol: 'vless',
          transport: 'xhttp',
          security: 'reality',
          flow: 'xtls-rprx-vision',
          publicKey: 'k',
        ),
        contains(ServerRuleIssue.visionNeedsRawTls),
      );
    });

    test('ни на ws, ни на grpc, ни на mkcp', () {
      for (final transport in ['ws', 'grpc', 'kcp', 'httpupgrade']) {
        expect(
          visionWorksWith(
            transport: transport,
            security: 'tls',
            encryption: 'none',
          ),
          isFalse,
          reason: transport,
        );
      }
    });

    test('без TLS на самом TCP тоже не работает', () {
      expect(
        visionWorksWith(
          transport: 'tcp',
          security: 'none',
          encryption: 'none',
        ),
        isFalse,
      );
    });

    test('с VLESS Encryption транспорт уже не важен', () {
      // Документация: «VLESS Encryption 无底层传输限制».
      expect(
        visionWorksWith(
          transport: 'xhttp',
          security: 'none',
          encryption: 'mlkem768x25519plus.native.1rtt.AAAA',
        ),
        isTrue,
      );
    });

    test('выбор предлагается только там, где он рабочий', () {
      expect(
        flowOptionsFor(
          protocol: 'vless',
          transport: 'tcp',
          security: 'reality',
          encryption: 'none',
        ),
        kServerFlows,
      );
      expect(
        flowOptionsFor(
          protocol: 'vless',
          transport: 'ws',
          security: 'tls',
          encryption: 'none',
        ),
        [''],
      );
      // У vmess и trojan `flow` нет вовсе.
      expect(
        flowOptionsFor(
          protocol: 'trojan',
          transport: 'tcp',
          security: 'tls',
          encryption: '',
        ),
        [''],
      );
    });

    test('незнакомый flow — это отказ ядра от всего конфига', () {
      expect(
        serverRuleIssues(
          protocol: 'vless',
          transport: 'tcp',
          security: 'tls',
          flow: 'xtls-rprx-direct',
        ),
        contains(ServerRuleIssue.flowUnknown),
      );
    });
  });

  group('REALITY', () {
    test('несут его только raw, xhttp и grpc', () {
      expect(realityWorksOver('tcp'), isTrue);
      expect(realityWorksOver('raw'), isTrue);
      expect(realityWorksOver('xhttp'), isTrue);
      expect(realityWorksOver('splithttp'), isTrue);
      expect(realityWorksOver('grpc'), isTrue);
      expect(realityWorksOver('ws'), isFalse);
      expect(realityWorksOver('httpupgrade'), isFalse);
      expect(realityWorksOver('kcp'), isFalse);
      expect(realityWorksOver('mkcp'), isFalse);
    });

    test('на ws он в списке защиты не предлагается', () {
      expect(securityOptionsFor('ws'), ['none', 'tls']);
      expect(securityOptionsFor('tcp'), ['none', 'tls', 'reality']);
    });

    test('без публичного ключа соединение не встанет', () {
      expect(
        serverRuleIssues(
          protocol: 'vless',
          transport: 'tcp',
          security: 'reality',
        ),
        contains(ServerRuleIssue.realityNeedsPublicKey),
      );
    });

    test('поверх ws — отдельная претензия, даже когда ключ есть', () {
      expect(
        serverRuleIssues(
          protocol: 'vless',
          transport: 'ws',
          security: 'reality',
          publicKey: 'k',
        ),
        [ServerRuleIssue.realityNeedsOwnTransport],
      );
    });
  });

  group('VLESS Encryption', () {
    test('none и пусто — это выключено', () {
      expect(vlessEncryptionEnabled('none'), isFalse);
      expect(vlessEncryptionEnabled('  '), isFalse);
      expect(vlessEncryptionLooksValid('none'), isTrue);
    });

    test('ключ разбирается по тем же частям, что и в ядре', () {
      expect(
        vlessEncryptionLooksValid('mlkem768x25519plus.native.1rtt.AAAA'),
        isTrue,
      );
      expect(
        vlessEncryptionLooksValid('mlkem768x25519plus.random.0rtt.600s.AAAA'),
        isTrue,
      );
    });

    test('мусор ядро не примет, и конфиг не поднимется целиком', () {
      for (final bad in [
        'auto',
        'mlkem768x25519plus.native',
        'mlkem768x25519plus.turbo.1rtt.AAAA',
        'mlkem768x25519plus.native.2rtt.AAAA',
      ]) {
        expect(vlessEncryptionLooksValid(bad), isFalse, reason: bad);
        expect(
          serverRuleIssues(
            protocol: 'vless',
            transport: 'tcp',
            security: 'tls',
            encryption: bad,
          ),
          contains(ServerRuleIssue.encryptionMalformed),
          reason: bad,
        );
      }
    });
  });

  group('без защиты вовсе', () {
    test('vless и trojan без TLS ядро пускает только в приватную сеть', () {
      for (final protocol in ['vless', 'trojan']) {
        expect(
          serverRuleIssues(
            protocol: protocol,
            transport: 'tcp',
            security: 'none',
          ),
          contains(ServerRuleIssue.noSecurityAtAll),
          reason: protocol,
        );
      }
    });

    test('vless с Encryption — уже не «без защиты»', () {
      expect(
        serverRuleIssues(
          protocol: 'vless',
          transport: 'tcp',
          security: 'none',
          encryption: 'mlkem768x25519plus.native.1rtt.AAAA',
        ),
        isEmpty,
      );
    });

    test('у vmess своё шифрование, к нему претензии нет', () {
      expect(
        serverRuleIssues(
          protocol: 'vmess',
          transport: 'tcp',
          security: 'none',
        ),
        isEmpty,
      );
    });
  });

  test('исправный набор не вызывает ни одной претензии', () {
    expect(
      serverRuleIssues(
        protocol: 'vless',
        transport: 'tcp',
        security: 'reality',
        flow: 'xtls-rprx-vision',
        encryption: 'none',
        publicKey: 'oYXosxG2YU6_mQkkPTS8JUnoRxqvaBaG5mH-y0pc2nA',
      ),
      isEmpty,
    );
  });
}
