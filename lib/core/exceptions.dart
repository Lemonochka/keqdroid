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

/// Свой таймаут запроса — НЕ `dart:async`.
///
/// Имя с приставкой намеренно: раньше класс звался `TimeoutException`, и в
/// файле, импортирующем и его, и `dart:async`, побеждал он (не-SDK объявление
/// перекрывает одноимённое из `dart:`), а в остальных — SDK'шный. Получалось,
/// что `on TimeoutException` в разных файлах ловил РАЗНОЕ, и по имени это никак
/// не читалось.
class RequestTimeoutException extends NetworkException {
  const RequestTimeoutException(super.message, {super.cause});
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

// файловые диалоги

/// Показать системный диалог выбора файла нечем.
///
/// Только Linux: ни портала XDG с backend'ом FileChooser, ни
/// zenity/qarma/kdialog. Своя ветка нужна, чтобы экран мог назвать
/// недостающий пакет и предложить обходной путь — по одному тексту ошибки
/// такое не разберёшь. См. `services/file_dialog_service.dart`.
class FileDialogUnavailableException extends AppException {
  const FileDialogUnavailableException({super.cause})
      : super('No file dialog available: install xdg-desktop-portal-gtk, '
            'zenity or kdialog');
}
