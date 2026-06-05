import '../services/subscription_service.dart';
import 'app_settings.dart';

/// пресеты и разрешение url-пинга
class PingTestConfig {
  PingTestConfig._();

  static const targetGstatic = 'gstatic';
  static const targetCloudflare = 'cloudflare';
  static const targetMicrosoft = 'microsoft';
  static const targetCustom = 'custom';

  static const targets = [
    targetGstatic,
    targetCloudflare,
    targetMicrosoft,
    targetCustom,
  ];

  /// HTTPS only — Android blocks cleartext HTTP (network_security_config).
  static const Map<String, String> presetUrls = {
    targetGstatic: 'https://connectivitycheck.gstatic.com/generate_204',
    targetCloudflare: 'https://one.one.one.one/cdn-cgi/trace',
    targetMicrosoft: 'https://www.msftconnecttest.com/connecttest.txt',
  };

  static const defaultTarget = targetGstatic;

  static String normalizeTarget(String? raw) {
    final v = raw?.trim().toLowerCase();
    if (v != null && targets.contains(v)) return v;
    return defaultTarget;
  }

  static String resolveTestUrl(AppSettings settings) {
    final target = normalizeTarget(settings.pingTestTarget);
    if (target == targetCustom) {
      return _normalizeCustomUrl(settings.pingTestUrlCustom);
    }
    return presetUrls[target] ?? presetUrls[targetGstatic]!;
  }

  static String _normalizeCustomUrl(String raw) {
    var u = raw.trim();
    if (u.isEmpty) return presetUrls[targetGstatic]!;
    if (!u.contains('://')) u = 'https://$u';
    if (u.startsWith('http://')) {
      u = 'https://${u.substring('http://'.length)}';
    }
    return u;
  }

  /// Returns error message if invalid, null if OK.
  static String? validateCustomUrl(String raw) {
    final u = _normalizeCustomUrl(raw);
    if (!SubscriptionService.isSafeUrl(u)) {
      return 'invalid_url';
    }
    return null;
  }

  static String presetLabelKey(String target) => switch (target) {
        targetGstatic => 'settingsPingTargetGstatic',
        targetCloudflare => 'settingsPingTargetCloudflare',
        targetMicrosoft => 'settingsPingTargetMicrosoft',
        targetCustom => 'settingsPingTargetCustom',
        _ => 'settingsPingTargetGstatic',
      };
}
