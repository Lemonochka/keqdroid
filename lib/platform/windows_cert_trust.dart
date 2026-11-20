import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:ffi/ffi.dart';

import '../core/app_logger.dart';

// Dart на Windows читает корни из хранилища, но цепочку через CryptoAPI не строит, и недостающий корень Windows не докачивает:
// на свежей системе GitHub и сайты подписок падали CERTIFICATE_VERIFY_FAILED. отказ Dart переспрашиваем у Windows
class WindowsSystemTrust extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)
        ..badCertificateCallback =
            (cert, host, port) => windowsTrustsCertificate(cert.der, host);
}

final _verdicts = <String, bool>{};

bool windowsTrustsCertificate(Uint8List der, String host) {
  final key = '$host ${sha256.convert(der)}';
  final known = _verdicts[key];
  if (known != null) return known;
  final trusted = _verify(der, host);
  _verdicts[key] = trusted;
  AppLogger.instance.info(
    trusted
        ? 'TLS $host: Dart could not verify the chain, Windows trusts it'
        : 'TLS $host: Windows does not trust the certificate either',
  );
  return trusted;
}

const _encoding = 0x00000001 | 0x00010000; // X509_ASN_ENCODING | PKCS_7_ASN_ENCODING
const _authTypeServer = 2;
const _policyBase = 1;
const _policySsl = 4;
const _policyBasicConstraints = 5;
const _basicConstraintsCa = 0x80000000;

final class _EnhkeyUsage extends Struct {
  @Uint32()
  external int count;
  external Pointer<Pointer<Utf8>> identifiers;
}

final class _UsageMatch extends Struct {
  @Uint32()
  external int type;
  external _EnhkeyUsage usage;
}

final class _ChainPara extends Struct {
  @Uint32()
  external int size;
  external _UsageMatch requestedUsage;
}

final class _SslPolicyPara extends Struct {
  @Uint32()
  external int size;
  @Uint32()
  external int authType;
  @Uint32()
  external int checks;
  external Pointer<Utf16> serverName;
}

final class _PolicyPara extends Struct {
  @Uint32()
  external int size;
  @Uint32()
  external int flags;
  external Pointer<Void> extra;
}

final class _PolicyStatus extends Struct {
  @Uint32()
  external int size;
  @Uint32()
  external int error;
  @Int32()
  external int chainIndex;
  @Int32()
  external int elementIndex;
  external Pointer<Void> extra;
}

typedef _CreateContextC = Pointer<Void> Function(Uint32, Pointer<Uint8>, Uint32);
typedef _CreateContext = Pointer<Void> Function(int, Pointer<Uint8>, int);
typedef _GetChainC = Int32 Function(Pointer<Void>, Pointer<Void>, Pointer<Void>,
    Pointer<Void>, Pointer<_ChainPara>, Uint32, Pointer<Void>, Pointer<Pointer<Void>>);
typedef _GetChain = int Function(Pointer<Void>, Pointer<Void>, Pointer<Void>,
    Pointer<Void>, Pointer<_ChainPara>, int, Pointer<Void>, Pointer<Pointer<Void>>);
typedef _VerifyPolicyC = Int32 Function(
    Pointer<Void>, Pointer<Void>, Pointer<_PolicyPara>, Pointer<_PolicyStatus>);
typedef _VerifyPolicy = int Function(
    Pointer<Void>, Pointer<Void>, Pointer<_PolicyPara>, Pointer<_PolicyStatus>);
typedef _FreeC = Void Function(Pointer<Void>);
typedef _Free = void Function(Pointer<Void>);
typedef _FreeContextC = Int32 Function(Pointer<Void>);
typedef _FreeContext = int Function(Pointer<Void>);

bool _verify(Uint8List der, String host) {
  if (!Platform.isWindows || der.isEmpty) return false;
  final crypt32 = DynamicLibrary.open('crypt32.dll');
  final createContext = crypt32
      .lookupFunction<_CreateContextC, _CreateContext>('CertCreateCertificateContext');
  final getChain =
      crypt32.lookupFunction<_GetChainC, _GetChain>('CertGetCertificateChain');
  final verifyPolicy = crypt32.lookupFunction<_VerifyPolicyC, _VerifyPolicy>(
      'CertVerifyCertificateChainPolicy');
  final freeChain =
      crypt32.lookupFunction<_FreeC, _Free>('CertFreeCertificateChain');
  final freeContext = crypt32
      .lookupFunction<_FreeContextC, _FreeContext>('CertFreeCertificateContext');

  return using((arena) {
    final bytes = arena<Uint8>(der.length)..asTypedList(der.length).setAll(0, der);
    final context = createContext(_encoding, bytes, der.length);
    if (context == nullptr) return false;
    final chain = arena<Pointer<Void>>();
    try {
      final serverAuth = arena<Pointer<Utf8>>()
        ..value = '1.3.6.1.5.5.7.3.1'.toNativeUtf8(allocator: arena);
      final para = arena<_ChainPara>();
      para.ref
        ..size = sizeOf<_ChainPara>()
        ..requestedUsage.type = 0
        ..requestedUsage.usage.count = 1
        ..requestedUsage.usage.identifiers = serverAuth;
      if (getChain(nullptr, context, nullptr, nullptr, para, 0, nullptr, chain) == 0) {
        return false;
      }
      bool passes(int oid, int flags, Pointer<Void> extra) {
        final policy = arena<_PolicyPara>();
        policy.ref
          ..size = sizeOf<_PolicyPara>()
          ..flags = flags
          ..extra = extra;
        final status = arena<_PolicyStatus>();
        status.ref.size = sizeOf<_PolicyStatus>();
        return verifyPolicy(Pointer.fromAddress(oid), chain.value, policy, status) != 0 &&
            status.ref.error == 0;
      }

      try {
        final ssl = arena<_SslPolicyPara>();
        ssl.ref
          ..size = sizeOf<_SslPolicyPara>()
          ..authType = _authTypeServer
          ..checks = 0
          ..serverName = host.toNativeUtf16(allocator: arena);
        if (passes(_policySsl, 0, ssl.cast())) return true;
        // Dart отдаёт не лист, а сертификат, на котором оборвалась цепочка; тогда перед нами центр сертификации,
        // и от него нужна только цепочка до доверенного корня. Имя Dart проверяет сам и при несовпадении пришлёт лист
        return passes(_policyBase, 0, nullptr) &&
            passes(_policyBasicConstraints, _basicConstraintsCa, nullptr);
      } finally {
        freeChain(chain.value);
      }
    } finally {
      freeContext(context);
    }
  });
}
