import 'package:flutter/material.dart';
import '../core/exceptions.dart';
import 'package:keqdroid/l10n/app_localizations.dart';

enum UiErrorKind { permission, network, config, auth, providerConfig, unknown }

class UiErrorMessage {
  final UiErrorKind kind;
  final String title;
  final String message;
  final String action;

  const UiErrorMessage({
    required this.kind,
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
      title: 'Provider Configuration Required',
      message: 'Provider has no hosts assigned to this subscription.',
      action: 'Open provider panel, add/assign hosts, then refresh subscription.',
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
      title: 'Authorization Failed',
      message: 'Access to subscription is denied by provider.',
      action: 'Check token/credentials and verify subscription has not expired.',
    );
  }

  if (msg.contains('http 404') ||
      msg.contains('http 410')) {
    return const UiErrorMessage(
      kind: UiErrorKind.config,
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
    title: 'Operation Failed',
    message: clean.isNotEmpty ? clean : 'Unknown error',
    action: 'Retry operation. If issue repeats, check server and app settings.',
  );
}

UiErrorMessage explainErrorLocalized(Object error, AppLocalizations l10n) {
  final base = explainError(error);
  return switch (base.kind) {
    UiErrorKind.permission => UiErrorMessage(
        kind: base.kind,
        title: l10n.errorConnectionPermission,
        message: base.message,
        action: base.action,
      ),
    UiErrorKind.network => UiErrorMessage(
        kind: base.kind,
        title: l10n.errorConnectionNetwork,
        message: base.message,
        action: base.action,
      ),
    UiErrorKind.config => UiErrorMessage(
        kind: base.kind,
        title: l10n.errorConnectionConfig,
        message: base.message,
        action: base.action,
      ),
    UiErrorKind.auth => UiErrorMessage(
        kind: base.kind,
        title: l10n.errorConnectionAuth,
        message: base.message,
        action: base.action,
      ),
    UiErrorKind.providerConfig => UiErrorMessage(
        kind: base.kind,
        title: l10n.errorProviderConfigTitle,
        message: l10n.errorProviderNoHostsMessage,
        action: l10n.errorProviderNoHostsAction,
      ),
    UiErrorKind.unknown => UiErrorMessage(
        kind: base.kind,
        title: l10n.errorConnectionGeneric,
        message: base.message,
        action: base.action,
      ),
  };
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

