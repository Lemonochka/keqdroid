import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/app_logger.dart';
import '../l10n/app_localizations.dart';
import '../providers/providers.dart';
import '../services/backup_transfer.dart';
import '../services/settings_backup_service.dart';
import '../services/tv_handoff.dart' show findLanAddress;
import '../shared/ui/app_theme.dart';
import '../shared/ui/expressive.dart';
import '../shared/ui/shape_loading_indicator.dart';
import 'backup_transfer_flow.dart';

// показывает код; receive возвращает принятую копию, восстановление спрашивает вызывающий экран
class BackupTransferScreen extends ConsumerStatefulWidget {
  const BackupTransferScreen({super.key, required this.direction});

  final BackupTransferDirection direction;

  static Future<KeqdroidBackup?> open(
    BuildContext context,
    BackupTransferDirection direction,
  ) => Navigator.of(context).push(
    MaterialPageRoute<KeqdroidBackup>(
      builder: (_) => BackupTransferScreen(direction: direction),
    ),
  );

  @visibleForTesting
  static Future<String?> Function() lanAddress = findLanAddress;

  @override
  ConsumerState<BackupTransferScreen> createState() =>
      _BackupTransferScreenState();
}

enum _Phase { starting, waiting, given, failed, noNetwork }

class _BackupTransferScreenState extends ConsumerState<BackupTransferScreen> {
  BackupTransferServer? _server;
  _Phase _phase = _Phase.starting;

  bool get _give => widget.direction == BackupTransferDirection.give;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    unawaited(_server?.close());
    super.dispose();
  }

  Future<void> _start() async {
    try {
      final lan = await BackupTransferScreen.lanAddress();
      if (!mounted) return;
      if (lan == null) {
        setState(() => _phase = _Phase.noNetwork);
        return;
      }
      final server = await BackupTransferServer.start(
        lanAddress: lan,
        direction: widget.direction,
        onReceived: _give ? null : _onReceived,
        provide: _give ? _provide : null,
        onGiven: _give ? _onGiven : null,
      );
      if (!mounted) {
        await server.close();
        return;
      }
      setState(() {
        _server = server;
        _phase = _Phase.waiting;
      });
    } catch (e, st) {
      AppLogger.instance.warn(
        'Backup transfer server failed to start',
        error: e,
        stackTrace: st,
      );
      if (mounted) setState(() => _phase = _Phase.noNetwork);
    }
  }

  Future<List<int>> _provide() async {
    final backup = await SettingsBackupService.buildBackup(
      ref.read(storageProvider),
      sections: allBackupSections,
    );
    return utf8.encode(backup.toJsonString(pretty: false));
  }

  void _onGiven() {
    if (mounted) setState(() => _phase = _Phase.given);
  }

  Future<void> _onReceived(Uint8List plain) async {
    final KeqdroidBackup backup;
    try {
      backup = KeqdroidBackup.parse(plain);
    } catch (e, st) {
      AppLogger.instance.warn(
        'Received backup could not be read',
        error: e,
        stackTrace: st,
      );
      if (mounted) {
        setState(() {
          _phase = _Phase.failed;
          _detail = '$e';
        });
      }
      return;
    }
    if (mounted) Navigator.of(context).pop(backup);
  }

  String _detail = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;

    final info = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _give ? l10n.backupTransferGive : l10n.backupTransferReceive,
            style: textTheme
                .emphasized(textTheme.headlineSmall)
                ?.copyWith(color: AppTheme.text(context)),
          ),
          const SizedBox(height: ExpressiveSpacing.medium),
          Text(
            l10n.backupTransferHowTo,
            style: textTheme.bodyLarge?.copyWith(
              color: AppTheme.textLight(context),
            ),
          ),
          const SizedBox(height: ExpressiveSpacing.largeIncreased),
          _status(context, l10n),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final qr = _QrCard(
              data: _phase == _Phase.waiting ? _server?.link.toLink() : null,
              offline: _phase == _Phase.noNetwork,
              done: _phase == _Phase.given,
            );
            final wide = constraints.maxWidth >= 700;
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(ExpressiveSpacing.extraLarge),
                child: wide
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [qr, const SizedBox(width: 40), info],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          qr,
                          const SizedBox(height: ExpressiveSpacing.extraLarge),
                          info,
                        ],
                      ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _status(BuildContext context, AppLocalizations l10n) {
    final (Widget icon, String text, Color color) = switch (_phase) {
      _Phase.starting || _Phase.waiting => (
        ShapeLoadingIndicator(size: 24, color: AppTheme.accent(context)),
        _give
            ? l10n.backupTransferWaitingGive
            : l10n.backupTransferWaitingReceive,
        AppTheme.accent(context),
      ),
      _Phase.given => (
        Icon(Icons.check_circle_rounded, color: AppTheme.green(context)),
        l10n.backupTransferGiven,
        AppTheme.green(context),
      ),
      _Phase.failed => (
        Icon(Icons.error_outline_rounded, color: AppTheme.red(context)),
        l10n.settingsImportFailed(_detail),
        AppTheme.red(context),
      ),
      _Phase.noNetwork => (
        Icon(Icons.wifi_off_rounded, color: AppTheme.red(context)),
        l10n.backupTransferNoNetwork,
        AppTheme.red(context),
      ),
    };
    return Row(
      children: [
        SizedBox.square(dimension: 24, child: Center(child: icon)),
        const SizedBox(width: ExpressiveSpacing.small),
        Flexible(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}

// на белом: камеры хуже читают код на цветной подложке
class _QrCard extends StatelessWidget {
  const _QrCard({
    required this.data,
    required this.offline,
    required this.done,
  });

  final String? data;
  final bool offline;
  final bool done;

  static const double _size = 240;

  @override
  Widget build(BuildContext context) {
    final data = this.data;
    final Widget child;
    if (data != null) {
      child = QrImageView(
        key: ValueKey<String>(data),
        data: data,
        version: QrVersions.auto,
        size: _size,
        padding: EdgeInsets.zero,
        backgroundColor: Colors.white,
      );
    } else if (done) {
      child = const Center(
        child: Icon(Icons.check_rounded, size: 96, color: Colors.black38),
      );
    } else if (offline) {
      child = const Center(
        child: Icon(Icons.wifi_off_rounded, size: 64, color: Colors.black38),
      );
    } else {
      child = const Center(child: ShapeLoadingIndicator(color: Colors.black38));
    }
    return Container(
      padding: const EdgeInsets.all(ExpressiveSpacing.large),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(ExpressiveShape.large),
      ),
      child: SizedBox.square(dimension: _size, child: child),
    );
  }
}
