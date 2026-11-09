import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

class ReleaseSignature {
  ReleaseSignature._();

  static const sumsName = 'SHA256SUMS';
  static const signatureName = 'SHA256SUMS.sig';

  // второй ключ запасной и хранится не на GitHub: без него потеря основного навсегда закрыла бы обновления
  @visibleForTesting
  static List<String> publicKeys = const [
    'pPWpQvbW0WGwkEr/YcOsnEIeZ2CZTsOh/d/4Y+g6Q9k=',
    'pMuHfej/dlfiszKhI7UCgfX3Ljch5YiCSv9TzIRRzpw=',
  ];

  static Map<String, dynamic>? sumsAsset(List? assets) =>
      _byName(assets, sumsName);

  static Map<String, dynamic>? signatureAsset(List? assets) =>
      _byName(assets, signatureName);

  static Map<String, dynamic>? _byName(List? assets, String name) {
    if (assets == null) return null;
    final wanted = name.toLowerCase();
    for (final asset in assets) {
      if (asset is! Map) continue;
      if ((asset['name'] ?? '').toString().toLowerCase() == wanted) {
        return Map<String, dynamic>.from(asset);
      }
    }
    return null;
  }

  // подпись: base64 от 64 байт Ed25519 над файлом как есть, tool/sign_sums.sh
  static Future<bool> verify(List<int> sums, String signature) async {
    final List<int> sig;
    try {
      sig = base64.decode(signature.trim());
    } on FormatException {
      return false;
    }
    if (sig.length != 64) return false;

    final algorithm = Ed25519();
    for (final key in publicKeys) {
      final publicKey = SimplePublicKey(
        base64.decode(key),
        type: KeyPairType.ed25519,
      );
      if (await algorithm.verify(
        sums,
        signature: Signature(sig, publicKey: publicKey),
      )) {
        return true;
      }
    }
    return false;
  }

  static Future<String> fetchVerifiedSums(
    Dio dio, {
    required String sumsUrl,
    required String signatureUrl,
  }) async {
    final sums = await dio.get<List<int>>(
      sumsUrl,
      options: Options(responseType: ResponseType.bytes),
    );
    final signature = await dio.get<String>(
      signatureUrl,
      options: Options(responseType: ResponseType.plain),
    );
    final bytes = sums.data;
    if (bytes == null || !await verify(bytes, signature.data ?? '')) {
      throw StateError(
        '$sumsName of this release is not signed by the keqdroid release key; '
        'refusing to trust it.',
      );
    }
    return utf8.decode(bytes);
  }
}
