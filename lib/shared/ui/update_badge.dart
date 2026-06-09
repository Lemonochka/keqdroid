import 'package:flutter/material.dart';
import 'package:keqdroid/shared/extensions/build_context_l10n.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../services/update_service.dart';
import 'package:keqdroid/shared/ui/update_dialog.dart';

/// версия приложения и бейдж обновления
class AppVersionInfo extends StatefulWidget {
  const AppVersionInfo({super.key});

  @override
  State<AppVersionInfo> createState() => _AppVersionInfoState();
}

class _AppVersionInfoState extends State<AppVersionInfo> {
  UpdateInfo? _updateInfo;
  bool _checking = false;
  bool _updateAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
    if (_checking) return;
    setState(() => _checking = true);

    try {
      final info = await UpdateService.checkForUpdate();
      if (mounted) {
        setState(() {
          _updateInfo = info;
          _updateAvailable = info != null;
          _checking = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _checking = false);
      }
    }
  }

  Future<void> _forceCheck() async {
    setState(() => _checking = true);

    try {
      final info = await UpdateService.checkForUpdate(force: true);
      if (mounted) {
        setState(() {
          _updateInfo = info;
          _updateAvailable = info != null;
          _checking = false;
        });
        if (info != null && mounted) {
          showUpdateDialog(context, info);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _checking = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.settingsCheckFailedError('$e'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtitleColor = Theme.of(context).colorScheme.onSurfaceVariant;
    final accent = Theme.of(context).colorScheme.primary;

    return Column(
      children: [
        FutureBuilder<String?>(
          future: _getVersion(),
          builder: (context, snapshot) {
            final version = snapshot.data ?? '...';
            return Text(
              'Version $version',
              style: TextStyle(
                fontSize: 12,
                color: subtitleColor,
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _checking || _updateAvailable ? null : _forceCheck,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _updateAvailable
                  ? accent.withValues(alpha: 0.15)
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
              border: _updateAvailable
                  ? Border.all(color: accent.withValues(alpha: 0.4))
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_checking)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: accent,
                    ),
                  )
                else if (_updateAvailable)
                  Icon(Icons.update, size: 14, color: accent)
                else
                  Icon(Icons.check_circle_outline, size: 14, color: subtitleColor),
                const SizedBox(width: 4),
                Text(
                  _checking
                      ? 'Checking...'
                      : _updateAvailable
                          ? 'Update available'
                          : 'Up to date',
                  style: TextStyle(
                    fontSize: 11,
                    color: _updateAvailable ? accent : subtitleColor,
                    fontWeight: _updateAvailable ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_updateAvailable && _updateInfo != null) ...[
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: () => showUpdateDialog(context, _updateInfo!),
            icon: const Icon(Icons.download, size: 18),
            label: Text('v${_updateInfo!.displayLatestVersion}'),
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ],
    );
  }

  Future<String> _getVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (e) {
      return '...';
    }
  }
}
