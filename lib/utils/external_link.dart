import 'package:url_launcher/url_launcher.dart';

/// Открытие ссылок, пришедших от провайдера подписки.
///
/// Адрес приходит заголовком с чужого сервера, поэтому перед открытием он
/// проверяется ещё раз, даже если уже был отфильтрован при разборе ответа:
/// значение могло прилететь из сохранённого профиля, записанного прошлой
/// версией приложения с другими правилами.
Future<bool> openExternalLink(String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !isSafeExternalLink(uri)) return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on Object {
    // Нет браузера/обработчика — не роняем экран из-за косметической кнопки.
    return false;
  }
}

/// Только http(s) с непустым хостом: `javascript:`, `file:` и `intent:` из
/// заголовка чужого сервера открывать нельзя.
bool isSafeExternalLink(Uri uri) =>
    (uri.scheme == 'http' || uri.scheme == 'https') &&
    uri.hasAuthority &&
    uri.host.isNotEmpty;
