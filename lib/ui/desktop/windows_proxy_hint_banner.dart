import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/providers.dart';
import '../../services/firefox_proxy_helper.dart';
import '../../services/vpn_engine.dart';
import '../../shared/ui/app_theme.dart';

/// windows proxy mode: chromium берёт системный прокси, firefox — отдельная настройка
class WindowsProxyHintBanner extends ConsumerStatefulWidget {
  const WindowsProxyHintBanner({super.key});

  @override
  ConsumerState<WindowsProxyHintBanner> createState() =>
      _WindowsProxyHintBannerState();
}

class _WindowsProxyHintBannerState extends ConsumerState<WindowsProxyHintBanner> {
  String? _firefoxStatus;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows) return const SizedBox.shrink();

    final vpn = ref.watch(vpnStateProvider).value;
    if (vpn?.status != VpnStatus.connected ||
        vpn?.activeMode != ConnectionMode.proxy) {
      return const SizedBox.shrink();
    }

    final settings = ref.watch(settingsNotifierProvider).value;
    final httpPort = settings?.httpPort ?? 2081;
    final proxyLine = '127.0.0.1:$httpPort';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Material(
        color: AppTheme.inset(context),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Прокси для браузеров',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppTheme.text(context),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Chrome и Edge используют системный прокси Windows ($proxyLine) '
                'после полного перезапуска браузера.\n\n'
                'Firefox системный прокси не подхватывает сам — нажмите «Настроить Firefox» '
                '(нужен полный перезапуск Firefox) или вручную: HTTP $proxyLine.',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.35,
                  color: AppTheme.textLight(context),
                ),
              ),
              if (_firefoxStatus != null) ...[
                const SizedBox(height: 6),
                Text(
                  _firefoxStatus!,
                  style: TextStyle(fontSize: 11, color: AppTheme.orange(context)),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: proxyLine));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Скопировано: $proxyLine')),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('Копировать адрес'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _applyFirefox(httpPort),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Настроить Firefox'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      Process.run(
                        'cmd',
                        ['/c', 'start', 'ms-settings:network-proxy'],
                        runInShell: true,
                      );
                    },
                    icon: const Icon(Icons.settings, size: 16),
                    label: const Text('Прокси Windows'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _applyFirefox(int httpPort) async {
    final profiles = await FirefoxProxyHelper.applyManualHttpProxy(httpPort);
    if (!mounted) return;
    setState(() {
      if (profiles.isEmpty) {
        _firefoxStatus =
            'Профили Firefox не найдены в %APPDATA%\\Mozilla\\Firefox';
      } else {
        _firefoxStatus =
            'Обновлено профилей: ${profiles.length}. Полностью закройте и '
            'откройте Firefox.';
      }
    });
  }
}
