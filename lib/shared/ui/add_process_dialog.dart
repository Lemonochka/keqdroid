import 'dart:io' show Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../platform/platform_bootstrap.dart';
import '../../services/file_dialog_service.dart';
import '../../utils/bidi.dart';
import '../../utils/error_messages.dart';
import '../../utils/macos_app_bundle.dart';
import 'app_theme.dart';

// программы, которая не запущена, в списке процессов нет, и иначе её не выбрать; проверку имени делает вызывающий код
Future<String?> showAddProcessDialog(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final ctrl = TextEditingController();
  var pickedPath = '';

  // ошибка выбора файла прямо в диалоге: снекбар Scaffold рисует под ним, за модальным барьером
  String? pickError;

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      // заливка и форма из dialogTheme: локальный backgroundColor шёл мимо темы, и flair-темы не получали скруглений
      builder: (ctx, setDialogState) => AlertDialog(
        title: Text(l10n.splitAddAppTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctrl,
              textDirection: technicalInputDirection,
              decoration: InputDecoration(
                hintText: Platform.isLinux || Platform.isMacOS
                    ? l10n.splitAddAppHintLinux
                    : l10n.splitAddAppHint,
              ),
              autofocus: true,
            ),
            if (PlatformBootstrap.isDesktop) ...[
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () async {
                    try {
                      // Unix executables have no .exe extension.
                      final unix = Platform.isLinux || Platform.isMacOS;
                      final r = await AppFileDialogs.pickFile(
                        dialogTitle: l10n.splitAddAppPickFile,
                        type: unix ? FileType.any : FileType.custom,
                        allowedExtensions: unix ? null : const ['exe'],
                      );
                      if (r?.path != null) {
                        pickedPath = r!.path!;
                        ctrl.text = pickedPath;
                      }
                    } catch (e) {
                      // путь можно вписать руками, поэтому диалог не закрываем
                      setDialogState(
                        () => pickError = friendlyErrorDetailed(e, ctx),
                      );
                    }
                  },
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  label: Text(l10n.splitAddAppPickFile),
                ),
              ),
              if (pickError != null) ...[
                const SizedBox(height: 8),
                Text(
                  pickError!,
                  style: Theme.of(
                    ctx,
                  ).textTheme.bodySmall?.copyWith(color: AppTheme.red(ctx)),
                ),
              ],
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.splitAddApp),
          ),
        ],
      ),
    ),
  );

  if (ok != true) return null;
  final path = pickedPath.isNotEmpty ? pickedPath : ctrl.text;
  return Platform.isMacOS ? MacosAppBundle.resolveProcessPath(path) : path;
}
