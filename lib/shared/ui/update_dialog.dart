import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:keqdroid/shared/extensions/build_context_l10n.dart';

import '../../services/update_service.dart';

/// диалог обновления
Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _UpdateDialog(info: info),
  );
}

class _UpdateDialog extends StatefulWidget {
  final UpdateInfo info;

  const _UpdateDialog({required this.info});

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _downloading = false;
  double _progress = 0;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final textColor = Theme.of(context).colorScheme.onSurface;
    final subtitleColor = Theme.of(context).colorScheme.onSurfaceVariant;

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
          Text(context.l10n.updateTitle),
        ],
      ),
      content: Column(
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
            'Size: ${widget.info.formattedSize}',
            style: TextStyle(fontSize: 13, color: subtitleColor),
          ),
          if (widget.info.releaseNotes != null && widget.info.releaseNotes!.isNotEmpty) ...[
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
              height: 100,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.all(10),
              child: SingleChildScrollView(
                child: MarkdownBody(
                  data: widget.info.releaseNotes!,
                  styleSheet: MarkdownStyleSheet(
                    p: TextStyle(fontSize: 12, color: subtitleColor, height: 1.4),
                    listBullet: TextStyle(fontSize: 12, color: subtitleColor, height: 1.4),
                    strong: TextStyle(fontSize: 12, color: subtitleColor, fontWeight: FontWeight.w600),
                    a: TextStyle(color: Theme.of(context).colorScheme.primary),
                  ),
                ),
              ),
            ),
          ],
          if (_downloading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: _progress > 0 ? _progress : null,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 6),
            Text(
              _progress > 0
                  ? '${(_progress * 100).toInt()}%'
                  : 'Downloading...',
              style: TextStyle(fontSize: 12, color: subtitleColor),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _downloading
              ? null
              : () async {
                  await UpdateService.skipVersion(widget.info.latestVersion);
                  if (context.mounted) Navigator.pop(context);
                },
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
                ? 'Downloading...'
                : widget.info.openInBrowser
                    ? 'Open download'
                    : context.l10n.updateActionNow,
          ),
        ),
      ],
    );
  }

  Future<void> _downloadAndInstall() async {
    setState(() => _downloading = true);

    try {
      await UpdateService.downloadAndInstall(
        widget.info,
        onProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() => _progress = received / total);
          }
        },
      );
      // Не закрываем диалог сразу - пользователь может быть в процессе установки
    } catch (e) {
      if (mounted) {
        setState(() => _downloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.settingsDownloadFailed('$e'))),
        );
      }
    }
  }
}

