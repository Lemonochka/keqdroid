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
  final path = await showDialog<String>(
    context: context,
    builder: (ctx) => const _AddProcessDialog(),
  );
  if (path == null) return null;
  return Platform.isMacOS ? MacosAppBundle.resolveProcessPath(path) : path;
}

class _AddProcessDialog extends StatefulWidget {
  const _AddProcessDialog();

  @override
  State<_AddProcessDialog> createState() => _AddProcessDialogState();
}

class _AddProcessDialogState extends State<_AddProcessDialog> {
  final _ctrl = TextEditingController();

  // ошибка выбора файла прямо в диалоге: снекбар Scaffold рисует под ним, за модальным барьером
  String? _pickError;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // заливка и форма из dialogTheme: локальный backgroundColor шёл мимо темы, и flair-темы не получали скруглений
    return AlertDialog(
      title: Text(l10n.splitAddAppTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _ctrl,
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
                    final unix = Platform.isLinux || Platform.isMacOS;
                    final r = await AppFileDialogs.pickFile(
                      dialogTitle: l10n.splitAddAppPickFile,
                      type: unix ? FileType.any : FileType.custom,
                      allowedExtensions: unix ? null : const ['exe'],
                    );
                    if (!mounted) return;
                    if (r?.path != null) {
                      _ctrl.text = r!.path!;
                      if (_pickError != null) {
                        setState(() => _pickError = null);
                      }
                    }
                  } catch (e) {
                    if (!context.mounted) return;
                    // путь можно вписать руками, поэтому диалог не закрываем
                    setState(
                      () => _pickError = friendlyErrorDetailed(e, context),
                    );
                  }
                },
                icon: const Icon(Icons.folder_open_rounded, size: 18),
                label: Text(l10n.splitAddAppPickFile),
              ),
            ),
            if (_pickError != null) ...[
              const SizedBox(height: 8),
              Text(
                _pickError!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppTheme.red(context)),
              ),
            ],
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          child: Text(l10n.splitAddApp),
        ),
      ],
    );
  }
}
