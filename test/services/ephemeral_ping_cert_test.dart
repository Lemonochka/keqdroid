import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/core/app_logger.dart';
import 'package:keqdroid/services/ephemeral_xray_ping.dart';

/// Проба пинга открывает TLS на сыром сокете, мимо WindowsSystemTrust. На
/// свежей Windows Dart не доверял сайту проверки, пока Windows сама не
/// докачает корень, и прокси-пинг давал N/A всему списку. Отказ Dart проба
/// переспрашивает у Windows, но чужой сертификат по-прежнему не принимает.

/// Самоподписанный localhost на 100 лет, PKCS12 с паролем keqdroid.
const _selfSigned =
    'MIIEPAIBAzCCA/IGCSqGSIb3DQEHAaCCA+MEggPfMIID2zCCAooGCSqGSIb3DQEHBqCCAnswggJ3AgEAMIICcAYJKoZIhvcNAQcBMF8GCSqGSIb3DQEFDTBSMDEGCSqGSIb3DQEFDDAkBBB+CE+bUGDShFuxjdIkLzDxAgIIADAMBggqhkiG9w0CCQUAMB0GCWCGSAFlAwQBKgQQeOFL1lb3qJ4uCRx0jdWRdoCCAgCIamFNBja8j1PjIdIWscGOiNUNwHfcUCqWevgqzqHqBZLoqS4P/n+pBHjA/Y7zvLPO4IJ+wvOtzheioWYRj7j+HHxH9O2lJUQNn85WcJjiaYbJMG4t4wtsoc4YIOok94Flk/OBbJw8QMvhQAONXefnah/dU/WBl4aKLwkTtCPlDn9CnMTeyNpsyV410kHu9G98XEFDue6gP2tOJ8p4Tc7tVw4QrdDSMh7+iXXKw4prRTSZ2Antst2UxWTE0oVgyAHQu2wn3EBuLclayTOmv74Pd65HJc6JgyGbQ7vv8Y5sj5fBwZmJVWvBUQNJd6V287i4K8aotc3Mx3xfZYQLBregAeE2dx6HQu86pGBXfynyFmPwlmJmN0yAFtRQpL0OzexJ3OiVjzuUdb74xfCSZuapUlwVNPJNaN63NHoCLxk8o7/SbqNKyVUW4stnZm7DEY85Cf4BTm2vkl8Sq8cYEmvu9ct8GO3WjT+kz5SZSautik9e1TI5g1MDMlSgrHwBdUYFFmmfETcZ6H/Jp7IFShT7wpZ/CJJvoAbdaShO3ohveAJv2VIrFVFWa5SCm40/QOAV/q3edQ424159bfeCqMKfxI6Z9URtbI/RH3tXT6HhlJZOEaguVUjXhwcDAOKdK2SJYxdkypl+5/SrCUs9giTjI2HxUROpNMWWUQbQFhHaNzCCAUkGCSqGSIb3DQEHAaCCAToEggE2MIIBMjCCAS4GCyqGSIb3DQEMCgECoIH3MIH0MF8GCSqGSIb3DQEFDTBSMDEGCSqGSIb3DQEFDDAkBBC3GhQvfKdcxnPVy7GnSDVHAgIIADAMBggqhkiG9w0CCQUAMB0GCWCGSAFlAwQBKgQQfy0mgqZZRTgZfenuYISmjwSBkI92yce+XGjfj3kwEdl2LESNqcL3+lgKyfD1ravWnzb2CzoVoervcG6MyG/QUN38Ueq/BIjOdgLmkTyx50jN9uiVbiUNGLYip1JpXInVGEehGD2qx+XQY+aK+PcI+tHxGUz3cPN+b54yNeyI41hDhqvHK9pU4DmaFXEhVAXLf7yrovo1iWvadcalJ7s0aleSQDElMCMGCSqGSIb3DQEJFTEWBBThwKTfJrAVJByVHNUwmLpLA7kiljBBMDEwDQYJYIZIAWUDBAIBBQAEIOBDF442JRElaP8kwY9daHQ9vm8eAxMr5JHEbXlUiUM+BAhKY1hx+/uULwICCAA=';

void main() {
  late Directory logDir;

  setUp(() {
    logDir = Directory.systemTemp.createTempSync('keqdroid_probe_cert');
    AppLogger.instance.enableFileLogIn(logDir);
  });

  tearDown(() {
    try {
      logDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('отказ Dart проба переспрашивает у Windows, чужой сертификат не принимает', () async {
    final p12 = base64.decode(_selfSigned);
    final context = SecurityContext()
      ..useCertificateChainBytes(p12, password: 'keqdroid')
      ..usePrivateKeyBytes(p12, password: 'keqdroid');
    final site = await SecureServerSocket.bind(InternetAddress.loopbackIPv4, 0, context);
    site.listen(
      (client) => client.listen(
        (_) => client.write('HTTP/1.1 204 No Content\r\nContent-Length: 0\r\n\r\n'),
        onError: (Object _) {},
      ),
      onError: (Object _) {},
    );
    // CONNECT принимает как инбаунд ядра и дальше просто гонит байты к сайту
    final proxy = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    proxy.listen((client) async {
      final upstream = await Socket.connect(InternetAddress.loopbackIPv4, site.port);
      var head = '';
      var tunnelled = false;
      upstream.listen(client.add, onDone: client.destroy, onError: (Object _) {});
      client.listen((data) {
        if (tunnelled) {
          upstream.add(data);
          return;
        }
        head += latin1.decode(data);
        if (head.contains('\r\n\r\n')) {
          tunnelled = true;
          client.write('HTTP/1.1 200 Connection established\r\n\r\n');
        }
      }, onDone: upstream.destroy, onError: (Object _) {});
    });
    addTearDown(() async {
      await proxy.close();
      await site.close();
    });

    final result = await EphemeralXrayPing.httpProbeViaSocks(
      testUrl: 'https://localhost:${site.port}/generate_204',
      socksPort: proxy.port,
      timeoutMs: 3000,
    );

    expect(result.success, isFalse);
    expect(result.error, contains('CERTIFICATE_VERIFY_FAILED'));
    final log = await AppLogger.instance.readFileLog();
    if (Platform.isWindows) {
      expect(log, contains('TLS localhost: Windows does not trust the certificate either'));
    } else {
      expect(log, isNot(contains('TLS localhost')));
    }
  });
}
