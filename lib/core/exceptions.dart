abstract class AppException implements Exception {
  final String message;
  final Object? cause;

  const AppException(this.message, {this.cause});

  @override
  String toString() => '$runtimeType: $message${cause != null ? ' (caused by: $cause)' : ''}';
}

// сеть

class NetworkException extends AppException {
  final int? statusCode;

  const NetworkException(super.message, {this.statusCode, super.cause});
}

class SubscriptionFetchException extends NetworkException {
  final String url;

  const SubscriptionFetchException(super.message, {required this.url, super.cause});
}

class TimeoutException extends NetworkException {
  const TimeoutException(super.message, {super.cause});
}

// парсинг

class ParseException extends AppException {
  final String? raw;

  const ParseException(super.message, {this.raw, super.cause});
}

class UnsupportedProtocolException extends ParseException {
  final String scheme;

  const UnsupportedProtocolException(this.scheme)
      : super('Unsupported protocol scheme: $scheme');
}

class InvalidBase64Exception extends ParseException {
  const InvalidBase64Exception(super.message, {super.raw, super.cause});
}

class InvalidUriException extends ParseException {
  const InvalidUriException(super.message, {super.raw, super.cause});
}

// vpn / platform channel

class VpnException extends AppException {
  const VpnException(super.message, {super.cause});
}

class VpnPermissionDeniedException extends VpnException {
  const VpnPermissionDeniedException([
    super.message = 'VPN permission was denied by the user',
  ]);
}

class VpnStartException extends VpnException {
  const VpnStartException(super.message, {super.cause});
}

class PlatformChannelException extends AppException {
  final String channel;

  const PlatformChannelException(super.message, {required this.channel, super.cause});
}

// хранилище

class StorageException extends AppException {
  const StorageException(super.message, {super.cause});
}

// конфиг

class ConfigBuilderException extends AppException {
  const ConfigBuilderException(super.message, {super.cause});
}
