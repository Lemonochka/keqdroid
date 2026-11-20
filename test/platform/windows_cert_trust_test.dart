import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/platform/windows_cert_trust.dart';

/// Отказ Dart переспрашиваем у Windows. Переспрос не должен ослаблять
/// проверку: чужое имя и мусор Windows отвергает так же, как отверг бы Dart.
/// Положительный случай (свежая Windows без нужного корня) проверен вживую:
/// он зависит от сети и от срока сертификата.

/// Лист *.github.com, выдан Sectigo, действителен до 27.11.2026.
const _githubLeaf =
    'MIID7jCCA5SgAwIBAgIQePiujyrk10/aE6gFaAdLbzAKBggqhkjOPQQDAjBgMQswCQYDVQQGEwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMTcwNQYDVQQDEy5TZWN0aWdvIFB1YmxpYyBTZXJ2ZXIgQXV0aGVudGljYXRpb24gQ0EgRFYgRTM2MB4XDTI2MDgzMDAwMDAwMFoXDTI2MTEyNzIzNTk1OVowFzEVMBMGA1UEAwwMKi5naXRodWIuY29tMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE1sM7iCBBQ4ER1JnLvGmL5r5BTu6wy6Brv6UhbjR03DLOqfOf60+MCCMNjM8s3c5DrJWy6DB5yhEtlxb6QSA08KOCAncwggJzMB8GA1UdIwQYMBaAFBeZqATBb+QtcKgKED0D0+kauCZjMB0GA1UdDgQWBBTD7jFglOUX6+JilvgIHwPAP3Q30DAOBgNVHQ8BAf8EBAMCB4AwDAYDVR0TAQH/BAIwADATBgNVHSUEDDAKBggrBgEFBQcDATBJBgNVHSAEQjBAMDQGCysGAQQBsjEBAgIHMCUwIwYIKwYBBQUHAgEWF2h0dHBzOi8vc2VjdGlnby5jb20vQ1BTMAgGBmeBDAECATCBhAYIKwYBBQUHAQEEeDB2ME8GCCsGAQUFBzAChkNodHRwOi8vY3J0LnNlY3RpZ28uY29tL1NlY3RpZ29QdWJsaWNTZXJ2ZXJBdXRoZW50aWNhdGlvbkNBRFZFMzYuY3J0MCMGCCsGAQUFBzABhhdodHRwOi8vb2NzcC5zZWN0aWdvLmNvbTCCAQUGCisGAQQB1nkCBAIEgfYEgfMA8QB3ANdtfRDRp/V3wsfpX9cAv/mCyTNaZeHQswFzF8DIxWl3AAABoFAfT/cAAAQDAEgwRgIhAL+EF7Mh/01jBp2ngOoMgNp5gU4SLDJ9Q1Vdoqkc4+SZAiEAhdrMG/SJRbqEeTr6oW2BzjHFLOIpaMSC1KCiTPMBnKQAdgDIo8R/x7OtuTVrAT9qehJt4zpOQ6XGRvmXrTl1mR3PmgAAAaBQH0/+AAAEAwBHMEUCIQCvJFRalfmFiEGXHLKYOMJaUbik+xHxuK3YKmWG2+aJTwIgQUPuzOEAFiKjS40Vp0B+sLwOOL/A8f9o7ofqQ/7qzBQwIwYDVR0RBBwwGoIMKi5naXRodWIuY29tggpnaXRodWIuY29tMAoGCCqGSM49BAMCA0gAMEUCIE1OmFf3DqBChbvhWFNoQAexCcXadL526Lfq9yHc/ZFyAiEAyel0O87R9q2DDGummwvhF8rmql1p3rC6lhWpcEtOAqg=';

/// Sectigo Public Server Authentication Root E46, подписанный USERTrust ECC,
/// действителен до 18.01.2038. На нём Dart обрывает цепочку GitHub, когда в
/// системе нет USERTrust ECC, и в обратный вызов приходит именно он.
const _sectigoCross =
    'MIIDRjCCAsugAwIBAgIQGp6v7G3o4ZtcGTFBto2Q3TAKBggqhkjOPQQDAzCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCk5ldyBKZXJzZXkxFDASBgNVBAcTC0plcnNleSBDaXR5MR4wHAYDVQQKExVUaGUgVVNFUlRSVVNUIE5ldHdvcmsxLjAsBgNVBAMTJVVTRVJUcnVzdCBFQ0MgQ2VydGlmaWNhdGlvbiBBdXRob3JpdHkwHhcNMjEwMzIyMDAwMDAwWhcNMzgwMTE4MjM1OTU5WjBfMQswCQYDVQQGEwJHQjEYMBYGA1UEChMPU2VjdGlnbyBMaW1pdGVkMTYwNAYDVQQDEy1TZWN0aWdvIFB1YmxpYyBTZXJ2ZXIgQXV0aGVudGljYXRpb24gUm9vdCBFNDYwdjAQBgcqhkjOPQIBBgUrgQQAIgNiAAR2+pmpbiDt+dd34wc7qNs9Xzjoq1WmVk/WSOrsfy2qw7LFeeyZYX8QeccCWvkEN/U0NSt3zn8gj1KjAIns1aeibVvjS5KToID1AZTc8GgHHs3u/iVStSBDHBv+6xnOQ6OjggEgMIIBHDAfBgNVHSMEGDAWgBQ64QmG1M8ZwpZ2dEl23OA1xmNjmjAdBgNVHQ4EFgQU0SLaTFnxS18mOKqd1u7rDcP7qWEwDgYDVR0PAQH/BAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0lBBYwFAYIKwYBBQUHAwEGCCsGAQUFBwMCMBEGA1UdIAQKMAgwBgYEVR0gADBQBgNVHR8ESTBHMEWgQ6BBhj9odHRwOi8vY3JsLnVzZXJ0cnVzdC5jb20vVVNFUlRydXN0RUNDQ2VydGlmaWNhdGlvbkF1dGhvcml0eS5jcmwwNQYIKwYBBQUHAQEEKTAnMCUGCCsGAQUFBzABhhlodHRwOi8vb2NzcC51c2VydHJ1c3QuY29tMAoGCCqGSM49BAMDA2kAMGYCMQCMCyBit99vX2ba6xEkDe+YO7vC0twjbkv9PKpqGGuZ61JZryjFsp+DFpEclCVy4noCMQCwvZDXD/m2Ko1HA5Bkmz7YQOFAiNDD49IWa2wdT7R3DtODaSXH/BiXv8fwB9su4tU=';

void main() {
  final skip = Platform.isWindows ? null : 'CryptoAPI есть только на Windows';

  test('мусор вместо сертификата: отказ без падения', () {
    expect(
      windowsTrustsCertificate(Uint8List.fromList([1, 2, 3]), 'example.com'),
      isFalse,
    );
  }, skip: skip);

  test(
    'центр, на котором оборвалась цепочка: Windows доводит его до корня',
    () {
      // корень USERTrust ECC Windows докачает сама, если его ещё нет
      expect(
        windowsTrustsCertificate(
          base64.decode(_sectigoCross),
          'api.github.com',
        ),
        isTrue,
      );
    },
    skip: skip,
  );

  test('настоящий сертификат на чужое имя: отказ', () {
    expect(
      windowsTrustsCertificate(base64.decode(_githubLeaf), 'example.com'),
      isFalse,
    );
  }, skip: skip);
}
