import 'package:flutter/material.dart';
import '../core/exceptions.dart';
import 'package:keqdroid/l10n/app_localizations.dart';

enum UiErrorKind { permission, network, config, auth, providerConfig, unknown }

/// Конкретный случай ошибки: kind задаёт только заголовок, а для перевода
/// message/action в explainErrorLocalized нужен точный вариант.
enum UiErrorCode {
  tunAdmin,
  vpnPermission,
  hwidBind,
  deviceLimit,
  providerNoHosts,
  configInvalid,
  authDenied,
  subUrlInvalid,
  subUrlInsecureHttp,
  network,
  unknown,
}

class UiErrorMessage {
  final UiErrorKind kind;
  final UiErrorCode code;
  final String title;
  final String message;
  final String action;

  const UiErrorMessage({
    required this.kind,
    this.code = UiErrorCode.unknown,
    required this.title,
    required this.message,
    required this.action,
  });

  String get short => '$title: $message';
  String get full => '$title\n$message\nAction: $action';
}

UiErrorMessage explainError(Object error) {
  final raw = error.toString();
  final msg = raw.toLowerCase();

  if (error is VpnPermissionDeniedException ||
      msg.contains('permission denied') ||
      msg.contains('vpn permission') ||
      msg.contains('administrator rights')) {
    final isWindowsAdmin = msg.contains('administrator');
    return UiErrorMessage(
      kind: UiErrorKind.permission,
      code: isWindowsAdmin ? UiErrorCode.tunAdmin : UiErrorCode.vpnPermission,
      title: 'Permission Required',
      message: isWindowsAdmin
          ? 'TUN mode on Windows needs Administrator rights.'
          : 'VPN permission was not granted.',
      action: isWindowsAdmin
          ? 'Run the app as administrator or switch to Proxy mode in settings.'
          : 'Allow VPN permission in the system dialog and try again.',
    );
  }

  if (msg.contains('hwid') && (msg.contains('bind') || msg.contains('enable'))) {
    return const UiErrorMessage(
      kind: UiErrorKind.auth,
      code: UiErrorCode.hwidBind,
      title: 'Device Binding Required',
      message: 'Provider requires HWID binding for this device.',
      action: 'Bind this device in provider panel, then refresh subscription.',
    );
  }

  if (msg.contains('max-devices-reached') ||
      msg.contains('device limit reached') ||
      msg.contains('x-hwid-limit')) {
    return const UiErrorMessage(
      kind: UiErrorKind.auth,
      code: UiErrorCode.deviceLimit,
      title: 'Device Limit Reached',
      message: 'Provider refused subscription due to device limit.',
      action: 'Remove old devices in provider panel or raise device limit.',
    );
  }

  if ((msg.contains('no hosts found') ||
          msg.contains('check hosts tab') ||
          msg.contains('did you forget to add hosts')) &&
      (msg.contains('service links') || msg.contains('0.0.0.0:1') || msg.contains('remnawave'))) {
    return const UiErrorMessage(
      kind: UiErrorKind.providerConfig,
      code: UiErrorCode.providerNoHosts,
      title: 'Provider Configuration Required',
      message: 'Provider has no hosts assigned to this subscription.',
      action: 'Open provider panel, add/assign hosts, then refresh subscription.',
    );
  }

  // Раньше generic-веток: «insecure http» содержит «http», а тексты про
  // forbidden/401/403 перехватили бы его как чужой случай.
  if (msg.contains('insecure http')) {
    return const UiErrorMessage(
      kind: UiErrorKind.config,
      code: UiErrorCode.subUrlInsecureHttp,
      title: 'Insecure Subscription URL',
      message: 'Subscription link uses plain http, updates are blocked.',
      action: 'Replace the link with its https:// version.',
    );
  }

  if (msg.contains('forbidden url') ||
      msg.contains('unsupported format') ||
      msg.contains('no supported proxy links') ||
      msg.contains('no servers found') ||
      msg.contains('configuration is empty') ||
      msg.contains('unsupported protocol')) {
    return const UiErrorMessage(
      kind: UiErrorKind.config,
      code: UiErrorCode.configInvalid,
      title: 'Configuration Error',
      message: 'Subscription or server configuration is invalid.',
      action: 'Check URL/config format and import a valid subscription link.',
    );
  }

  if (msg.contains('http 401') ||
      msg.contains('http 403') ||
      msg.contains('unauthorized') ||
      msg.contains('forbidden')) {
    return const UiErrorMessage(
      kind: UiErrorKind.auth,
      code: UiErrorCode.authDenied,
      title: 'Authorization Failed',
      message: 'Access to subscription is denied by provider.',
      action: 'Check token/credentials and verify subscription has not expired.',
    );
  }

  if (msg.contains('http 404') ||
      msg.contains('http 410')) {
    return const UiErrorMessage(
      kind: UiErrorKind.config,
      code: UiErrorCode.subUrlInvalid,
      title: 'Subscription URL Invalid',
      message: 'Subscription link is missing or expired.',
      action: 'Request a fresh URL from provider and update it in app.',
    );
  }

  if (msg.contains('failed host lookup') ||
      msg.contains('no address associated') ||
      msg.contains('connection timed out') ||
      msg.contains('timed out') ||
      msg.contains('connection error') ||
      msg.contains('socketexception') ||
      msg.contains('network error') ||
      error is TimeoutException) {
    return const UiErrorMessage(
      kind: UiErrorKind.network,
      code: UiErrorCode.network,
      title: 'Network Error',
      message: 'Cannot reach server right now.',
      action: 'Check internet, DNS, and server availability, then retry.',
    );
  }

  final clean = raw
      .split('\n')
      .first
      .replaceAll(RegExp(r'\w+Exception:\s*'), '')
      .replaceAll(RegExp(r'\s*\(caused by:.*'), '')
      .trim();

  return UiErrorMessage(
    kind: UiErrorKind.unknown,
    code: UiErrorCode.unknown,
    title: 'Operation Failed',
    message: clean.isNotEmpty ? clean : 'Unknown error',
    action: 'Retry operation. If issue repeats, check server and app settings.',
  );
}

UiErrorMessage explainErrorLocalized(Object error, AppLocalizations l10n) {
  final base = explainError(error);
  final title = switch (base.kind) {
    UiErrorKind.permission => l10n.errorConnectionPermission,
    UiErrorKind.network => l10n.errorConnectionNetwork,
    UiErrorKind.config => l10n.errorConnectionConfig,
    UiErrorKind.auth => l10n.errorConnectionAuth,
    UiErrorKind.providerConfig => l10n.errorProviderConfigTitle,
    UiErrorKind.unknown => l10n.errorConnectionGeneric,
  };
  final (message, action) = switch (base.code) {
    UiErrorCode.tunAdmin => (
        l10n.errorTunAdminMessage,
        l10n.errorTunAdminAction,
      ),
    UiErrorCode.vpnPermission => (
        l10n.errorVpnPermissionMessage,
        l10n.errorVpnPermissionAction,
      ),
    UiErrorCode.hwidBind => (
        l10n.errorHwidBindMessage,
        l10n.errorHwidBindAction,
      ),
    UiErrorCode.deviceLimit => (
        l10n.errorDeviceLimitMessage,
        l10n.errorDeviceLimitAction,
      ),
    UiErrorCode.providerNoHosts => (
        l10n.errorProviderNoHostsMessage,
        l10n.errorProviderNoHostsAction,
      ),
    UiErrorCode.configInvalid => (
        l10n.errorConfigInvalidMessage,
        l10n.errorConfigInvalidAction,
      ),
    UiErrorCode.authDenied => (
        l10n.errorAuthDeniedMessage,
        l10n.errorAuthDeniedAction,
      ),
    UiErrorCode.subUrlInvalid => (
        l10n.errorSubUrlInvalidMessage,
        l10n.errorSubUrlInvalidAction,
      ),
    UiErrorCode.subUrlInsecureHttp => (
        l10n.errorSubInsecureHttpMessage,
        l10n.errorSubInsecureHttpAction,
      ),
    UiErrorCode.network => (
        l10n.errorNetworkMessage,
        l10n.errorNetworkAction,
      ),
    // unknown: message — вычищенный текст исходной ошибки (динамический,
    // перевести нельзя), локализуем только рекомендацию.
    UiErrorCode.unknown => (base.message, l10n.errorUnknownAction),
  };
  return UiErrorMessage(
    kind: base.kind,
    code: base.code,
    title: title,
    message: message,
    action: action,
  );
}

String friendlyError(Object error, [BuildContext? context]) {
  final localized = context != null
      ? explainErrorLocalized(error, AppLocalizations.of(context)!)
      : explainError(error);
  final actionLabel = context != null
      ? AppLocalizations.of(context)!.errorActionLabel(localized.action)
      : localized.action;
  return '${localized.title}\n${localized.message}\n$actionLabel';
}

String friendlyErrorDetailed(Object error, [BuildContext? context]) {
  final localized = (context != null)
      ? explainErrorLocalized(error, AppLocalizations.of(context)!)
      : explainError(error);
  return '${localized.title}: ${localized.message} (${localized.action})';
}

String vpnErrorStatusLabel(String? errorMessage, BuildContext context) {
  final l10n = AppLocalizations.of(context)!;
  final details = explainErrorLocalized(errorMessage ?? 'unknown', l10n);
  return switch (details.kind) {
    UiErrorKind.permission => l10n.errorConnectionPermission,
    UiErrorKind.network => l10n.errorConnectionNetwork,
    UiErrorKind.config => l10n.errorConnectionConfig,
    UiErrorKind.auth => l10n.errorConnectionAuth,
    UiErrorKind.providerConfig => l10n.errorProviderConfigTitle,
    UiErrorKind.unknown => l10n.errorConnectionGeneric,
  };
}

