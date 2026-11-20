abstract class AppException implements Exception {
  final String message;
  final Object? cause;

  const AppException(this.message, {this.cause});

  @override
  String toString() =>
      '$runtimeType: $message${cause != null ? ' (caused by: $cause)' : ''}';
}

class NetworkException extends AppException {
  final int? statusCode;

  const NetworkException(super.message, {this.statusCode, super.cause});
}

class SubscriptionFetchException extends NetworkException {
  final String url;

  const SubscriptionFetchException(
    super.message, {
    required this.url,
    super.cause,
  });
}

// TimeoutException перекрывал одноимённый из dart:async там, где импортированы оба
class RequestTimeoutException extends NetworkException {
  const RequestTimeoutException(super.message, {super.cause});
}

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

  const PlatformChannelException(
    super.message, {
    required this.channel,
    super.cause,
  });
}

class StorageException extends AppException {
  const StorageException(super.message, {super.cause});
}

class FileDialogUnavailableException extends AppException {
  const FileDialogUnavailableException({super.cause})
    : super(
        'No file dialog available: install xdg-desktop-portal-gtk, '
        'zenity or kdialog',
      );
}
