import 'dart:convert';
import 'dart:io' show gzip;
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as hashes;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

class BackupKeyUnavailable implements Exception {
  const BackupKeyUnavailable();

  @override
  String toString() =>
      'This backup was made by a keqdroid release, and this build does not '
      'carry the release backup key';
}

// файл: KEQB, версия, номер ключа, соль 16 байт, затем nonce 12, шифротекст и тег 16 от AES-256-GCM
class BackupCrypto {
  BackupCrypto._();

  static const keyDev = 0;
  static const keyRelease = 1;
  static const keyTransfer = 2;

  static const _magic = [0x4B, 0x45, 0x51, 0x42];
  static const _version = 1;
  static const _saltLength = 16;
  static const _headerLength = 4 + 1 + 1 + _saltLength;
  static const _nonceLength = 12;
  static const _macLength = 16;

  static final _aes = AesGcm.with256bits();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final _info = utf8.encode('keqdroid backup v1');

  static bool isSealed(List<int> bytes) {
    if (bytes.length < _headerLength + _nonceLength + _macLength) return false;
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) return false;
    }
    return true;
  }

  static Future<Uint8List> seal(
    List<int> plain, {
    required int keyId,
    required List<int> key,
  }) async {
    final random = Random.secure();
    final salt = List<int>.generate(_saltLength, (_) => random.nextInt(256));
    final header = [..._magic, _version, keyId, ...salt];
    final box = await _aes.encrypt(
      gzip.encode(plain),
      secretKey: await _fileKey(key, salt),
      aad: header,
    );
    return Uint8List.fromList([...header, ...box.concatenation()]);
  }

  static Future<Uint8List> open(
    List<int> sealed, {
    required List<int> Function(int keyId) keyFor,
  }) async {
    if (!isSealed(sealed)) {
      throw const FormatException('Not an encrypted keqdroid backup');
    }
    final version = sealed[4];
    if (version != _version) {
      throw FormatException('Unsupported encrypted backup version: $version');
    }
    final header = sealed.sublist(0, _headerLength);
    final key = keyFor(sealed[5]);
    final box = SecretBox.fromConcatenation(
      sealed.sublist(_headerLength),
      nonceLength: _nonceLength,
      macLength: _macLength,
    );
    final List<int> clear;
    try {
      clear = await _aes.decrypt(
        box,
        secretKey: await _fileKey(key, header.sublist(6)),
        aad: header,
      );
    } on SecretBoxAuthenticationError {
      throw const FormatException(
        'The backup is damaged or encrypted with a different key',
      );
    }
    return Uint8List.fromList(gzip.decode(clear));
  }

  // своя соль на каждый файл: nonce GCM случайный, а файлов с одним ключом у всех людей много
  static Future<SecretKey> _fileKey(List<int> key, List<int> salt) =>
      _hkdf.deriveKey(secretKey: SecretKey(key), nonce: salt, info: _info);
}

// ключ выпуска собирается из двух половин, которые сборка берёт из secrets/backup_key.json (вне git), ключ = A xor B
class BackupKeys {
  BackupKeys._();

  static const _a = <int>[
    int.fromEnvironment('KEQ_BK_A0'),
    int.fromEnvironment('KEQ_BK_A1'),
    int.fromEnvironment('KEQ_BK_A2'),
    int.fromEnvironment('KEQ_BK_A3'),
    int.fromEnvironment('KEQ_BK_A4'),
    int.fromEnvironment('KEQ_BK_A5'),
    int.fromEnvironment('KEQ_BK_A6'),
    int.fromEnvironment('KEQ_BK_A7'),
  ];
  static const _b = <int>[
    int.fromEnvironment('KEQ_BK_B0'),
    int.fromEnvironment('KEQ_BK_B1'),
    int.fromEnvironment('KEQ_BK_B2'),
    int.fromEnvironment('KEQ_BK_B3'),
    int.fromEnvironment('KEQ_BK_B4'),
    int.fromEnvironment('KEQ_BK_B5'),
    int.fromEnvironment('KEQ_BK_B6'),
    int.fromEnvironment('KEQ_BK_B7'),
  ];

  @visibleForTesting
  static List<int>? releaseOverride;

  @visibleForTesting
  static bool noReleaseKey = false;

  static List<int>? get release {
    if (noReleaseKey) return null;
    final override = releaseOverride;
    if (override != null) return override;
    return assemble(_a, _b);
  }

  @visibleForTesting
  static List<int>? assemble(List<int> a, List<int> b) {
    if (a.every((w) => w == 0) && b.every((w) => w == 0)) return null;
    final out = <int>[];
    for (var i = 0; i < a.length; i++) {
      final word = (a[i] ^ b[i]) & 0xFFFFFFFF;
      out.addAll([word >> 24 & 0xFF, word >> 16 & 0xFF, word >> 8 & 0xFF, word & 0xFF]);
    }
    return out;
  }

  // сборки без секрета (свои сборки людей, тесты): ключ открытый, копия из них читается любой сборкой
  static final List<int> dev =
      hashes.sha256.convert(utf8.encode('keqdroid public backup key 1')).bytes;

  static int get writeKeyId =>
      release != null ? BackupCrypto.keyRelease : BackupCrypto.keyDev;

  static List<int> get writeKey => release ?? dev;

  static List<int> forReading(int keyId) => switch (keyId) {
        BackupCrypto.keyDev => dev,
        BackupCrypto.keyRelease => release ?? (throw const BackupKeyUnavailable()),
        _ => throw FormatException('Unknown backup key: $keyId'),
      };
}
