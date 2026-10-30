import '../services/subscription_service.dart';
import 'awg_profile.dart';
import 'custom_clash_config.dart';
import 'custom_xray_config.dart';
import 'singbox_outbounds.dart';
import 'subscription_deep_link.dart';

List<String> splitServerImportPayload(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return const [];
  if (AwgProfile.isAwgConfig(text)) return [text];

  // clash раньше xray: json clash тоже начинается с {
  if (CustomClashConfig.looksLikeClash(text)) {
    final nodes = SubscriptionService.clashNodeConfigs(text);
    if (nodes.isNotEmpty) return nodes;
    final clash = CustomClashConfig.extractConfigs(text);
    return clash.isNotEmpty ? clash : [text];
  }

  // sing-box тоже раньше xray: у его SSR-узла есть поле protocol
  if (SingboxOutbounds.looksLike(text)) {
    final links = SingboxOutbounds.translate(text).links;
    return links.isNotEmpty ? links : [text];
  }

  final custom = CustomXrayConfig.extractConfigs(text);
  if (custom.isNotEmpty) return custom;

  if (text.startsWith('{') || text.startsWith('[')) return [text];

  return text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
}

String? subscriptionUrlFromPastedLine(String line) {
  final text = line.trim();
  final fromPanelButton = subscriptionUrlFromDeepLink(text);
  if (fromPanelButton != null) return fromPanelButton;
  final uri = Uri.tryParse(text);
  if (uri == null || uri.host.isEmpty) return null;
  return uri.isScheme('http') || uri.isScheme('https') ? text : null;
}
