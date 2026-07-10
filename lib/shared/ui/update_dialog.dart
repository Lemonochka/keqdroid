import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keqdroid/shared/extensions/build_context_l10n.dart';

import '../../providers/providers.dart';
import '../../services/update_service.dart';
import '../../tunnel/tunnel_state.dart';
import '../../utils/awg_profile.dart';
import '../../utils/local_vpn_proxy.dart';

/// «Диалог уже показывали в этой сессии» — по ВЕРСИИ, а не булев флаг:
/// ре-раны updateInfoProvider с той же версией не спамят диалогом, но новый
/// релиз, вышедший пока приложение работает (периодический ре-чек),
/// предлагается снова.
class UpdatePrompt {
  UpdatePrompt._();

  static String? promptedVersionThisSession;

  static void markShown(String version) =>
      promptedVersionThisSession = version;
}

/// Показывать диалог при первой загрузке информации об обновлении,
/// но не при повторных refresh провайдера.
bool shouldAutoPromptForUpdate(
  AsyncValue<UpdateInfo?>? prev,
  AsyncValue<UpdateInfo?> next,
) {
  final info = next.value;
  if (info == null) return false;
  if (UpdatePrompt.promptedVersionThisSession == info.latestVersion) {
    return false;
  }

  final prevInfo = prev?.value;
  if (prevInfo?.latestVersion == info.latestVersion) return false;

  // повторный refresh с той же версией — не показываем (диалог уже видели)
  if (prevInfo != null && prev?.isLoading != true) return false;

  return true;
}

/// GitHub release body может содержать HTML-теги, которые flutter_markdown не рендерит.
String sanitizeReleaseNotes(String raw) {
  var text = raw;
  text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  text = text.replaceAll(RegExp(r'</?p>', caseSensitive: false), '\n');
  text = text.replaceAll(RegExp(r'</?details>', caseSensitive: false), '');
  text = text.replaceAll(RegExp(r'</?summary>', caseSensitive: false), '');
  text = text.replaceAll(RegExp(r'<h([1-6])>', caseSensitive: false), '\n## ');
  text = text.replaceAll(RegExp(r'</h[1-6]>', caseSensitive: false), '\n');
  text = text.replaceAll(RegExp(r'<[^>]+>'), '');
  text = text
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
  text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return text.trim();
}

bool _updateDialogOpen = false;

/// Показ диалога обновления (не более одного одновременно).
Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) async {
  if (_updateDialogOpen) return;
  _updateDialogOpen = true;
  UpdatePrompt.markShown(info.latestVersion);
  try {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _UpdateDialog(info: info),
    );
  } finally {
    _updateDialogOpen = false;
  }
}

class _UpdateDialog extends ConsumerStatefulWidget {
  final UpdateInfo info;

  const _UpdateDialog({required this.info});

  @override
  ConsumerState<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends ConsumerState<_UpdateDialog> {
  bool _downloading = false;
  bool _applying = false;
  double _progress = 0;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final textColor = Theme.of(context).colorScheme.onSurface;
    final subtitleColor = Theme.of(context).colorScheme.onSurfaceVariant;
    final notes = widget.info.releaseNotes;
    final sanitizedNotes =
        notes != null && notes.isNotEmpty ? sanitizeReleaseNotes(notes) : null;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.system_update, color: accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(context.l10n.updateTitle)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'v${widget.info.displayCurrentVersion} → v${widget.info.displayLatestVersion}',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              context.l10n.updateSizeLabel(widget.info.formattedSize),
              style: TextStyle(fontSize: 13, color: subtitleColor),
            ),
            if (sanitizedNotes != null && sanitizedNotes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                context.l10n.updateWhatsNew,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                constraints: const BoxConstraints(maxHeight: 140),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.all(10),
                child: SingleChildScrollView(
                  child: MarkdownBody(
                    data: sanitizedNotes,
                    shrinkWrap: true,
                    softLineBreak: true,
                    selectable: true,
                    styleSheet: MarkdownStyleSheet(
                      p: TextStyle(
                        fontSize: 12,
                        color: subtitleColor,
                        height: 1.4,
                      ),
                      h1: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                      h2: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                      h3: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                      listBullet: TextStyle(
                        fontSize: 12,
                        color: subtitleColor,
                        height: 1.4,
                      ),
                      listIndent: 16,
                      strong: TextStyle(
                        fontSize: 12,
                        color: subtitleColor,
                        fontWeight: FontWeight.w600,
                      ),
                      em: TextStyle(
                        fontSize: 12,
                        color: subtitleColor,
                        fontStyle: FontStyle.italic,
                      ),
                      a: TextStyle(color: accent),
                      code: TextStyle(
                        fontSize: 11,
                        color: subtitleColor,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ),
            ],
            if (_downloading) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: _applying || _progress <= 0 ? null : _progress,
                borderRadius: BorderRadius.circular(4),
              ),
              const SizedBox(height: 6),
              Text(
                _statusLabel(context),
                style: TextStyle(fontSize: 12, color: subtitleColor),
              ),
            ],
          ],
        ),
      ),
      actions: [
        // «Пропустить версию» — осознанный отказ: пишет skip-настройку,
        // эта версия больше не предлагается автоматически.
        TextButton(
          onPressed: _downloading
              ? null
              : () async {
                  await UpdateService.skipVersion(widget.info.latestVersion);
                  if (context.mounted) Navigator.pop(context);
                },
          child: Text(
            context.l10n.updateActionSkip,
            style: TextStyle(color: subtitleColor),
          ),
        ),
        // «Позже» просто закрывает диалог — БЕЗ записи skip: пользователь ждёт
        // напоминания, а skip навсегда убирает версию из авто-предложений.
        TextButton(
          onPressed: _downloading
              ? null
              : () => Navigator.pop(context),
          child: Text(context.l10n.updateActionLater),
        ),
        FilledButton(
          onPressed: _downloading ? null : _downloadAndInstall,
          style: FilledButton.styleFrom(
            backgroundColor: accent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Text(
            _downloading
                ? _statusLabel(context)
                : widget.info.openInBrowser
                    ? context.l10n.updateOpenDownload
                    : context.l10n.updateActionNow,
          ),
        ),
      ],
    );
  }

  String _statusLabel(BuildContext context) {
    if (_applying) return context.l10n.updateApplying;
    if (_progress > 0) return '${(_progress * 100).toInt()}%';
    return context.l10n.settingsDownloading;
  }

  Future<void> _downloadAndInstall() async {
    setState(() {
      _downloading = true;
      _applying = false;
      _progress = 0;
    });

    try {
      final vpn = ref.read(vpnStateProvider).value;
      final activeServer = ref.read(serversProvider).activeServer;
      final settings = await ref.read(storageProvider).getSettings();
      final restarting = await UpdateService.downloadAndInstall(
        widget.info,
        viaLocalProxy: tunnelHasLocalHttpProxy(
          vpnConnected: vpn?.status == VpnStatus.connected,
          awgBackend: activeServer != null &&
              AwgProfile.isAwgConfig(activeServer.config),
        ),
        httpPort: settings.httpPort,
        onProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() => _progress = received / total);
          }
        },
        // Desktop restarts (Windows zip, Linux AppImage in-place) tear the VPN
        // down first. Only invoked right before the app exits to apply — the
        // browser/deb hand-off path returns without calling it.
        beforeRestart: Platform.isWindows || Platform.isLinux
            ? () async {
                if (mounted) setState(() => _applying = true);
                await ref.read(vpnStateProvider.notifier).disconnect();
              }
            : null,
      );
      if (restarting) return;
      if (mounted) {
        setState(() => _downloading = false);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloading = false;
          _applying = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.settingsDownloadFailed('$e'))),
        );
      }
    }
  }
}
