part of '../subscriptions_tab.dart';

// sub снят при открытии шторки, currentSub читается в момент нажатия: карточка могла обновиться
void _showSubscriptionShareSheet(
  BuildContext context, {
  required Subscription sub,
  required Subscription Function() currentSub,
}) {
  final l10n = AppLocalizations.of(context)!;
  final qrKey = GlobalKey();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        MediaQuery.of(ctx).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            sub.name,
            style: Theme.of(ctx)
                .textTheme
                .emphasized(Theme.of(ctx).textTheme.titleMedium)
                ?.copyWith(color: AppTheme.text(ctx)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 16),
          RepaintBoundary(
            key: qrKey,
            child: Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: QrImageView(
                data: sub.url,
                version: QrVersions.auto,
                size: 220,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 12),
          SelectableText(
            sub.url,
            textAlign: TextAlign.center,
            maxLines: 3,
            style: Theme.of(ctx)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppTheme.textLight(ctx)),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentContainer(ctx),
                foregroundColor: AppTheme.onAccentContainer(ctx),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ExpressiveShape.large),
                ),
              ),
              icon: Icon(
                Platform.isLinux
                    ? Icons.download_rounded
                    : Icons.share_rounded,
                size: 18,
              ),
              label: Text(
                Platform.isLinux
                    ? l10n.subscriptionsSave
                    : l10n.subscriptionsShareAction,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: () => Platform.isLinux
                  ? _saveSubscriptionQr(context, ctx, qrKey, currentSub)
                  : _shareSubscriptionQr(context, ctx, qrKey, currentSub),
            ),
          ),
        ],
      ),
    ),
  );
}

Future<Uint8List?> _subscriptionQrPng(GlobalKey qrKey) async {
  final boundary =
      qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) return null;
  final image = await boundary.toImage(pixelRatio: 3.0);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  return byteData?.buffer.asUint8List();
}

String _subscriptionQrFileName(String subscriptionName) {
  final safe = subscriptionName.replaceAll(RegExp(r'[^\w\-]+'), '_');
  return 'keqdroid_sub_${safe.isEmpty ? 'qr' : safe}.png';
}

// на Linux share_plus файлы не передаёт и кидает исключение, поэтому сохраняем
Future<void> _saveSubscriptionQr(
  BuildContext context,
  BuildContext ctx,
  GlobalKey qrKey,
  Subscription Function() currentSub,
) async {
  final l10n = AppLocalizations.of(context)!;
  String message;
  try {
    final png = await _subscriptionQrPng(qrKey);
    if (png == null) return;
    final path = await AppFileDialogs.saveFile(
      fileName: _subscriptionQrFileName(currentSub().name),
      bytes: png,
      dialogTitle: l10n.subscriptionsQrSaveTitle,
      mimeType: 'image/png',
    );
    if (path == null) return;
    message = l10n.subscriptionsQrSaved(path);
  } catch (e) {
    if (!context.mounted) return;
    message = l10n.subscriptionsQrSaveFailed(
      e is FileDialogUnavailableException
          ? friendlyErrorDetailed(e, context)
          : friendlyError(e, context),
    );
  }
  if (ctx.mounted) Navigator.of(ctx).pop();
  if (!context.mounted) return;
  AppSnack.of(context)
      .showSnackBar(SnackBar(content: Text(message)));
}

Future<void> _shareSubscriptionQr(
  BuildContext context,
  BuildContext ctx,
  GlobalKey qrKey,
  Subscription Function() currentSub,
) async {
  final sub = currentSub();
  final l10n = AppLocalizations.of(context)!;
  try {
    final png = await _subscriptionQrPng(qrKey);
    if (png == null) return;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${_subscriptionQrFileName(sub.name)}');
    await file.writeAsBytes(png, flush: true);
    await SharePlus.instance.share(
      ShareParams(text: sub.url, files: [XFile(file.path)]),
    );
  } catch (e) {
    if (ctx.mounted) {
      AppSnack.of(ctx).showSnackBar(
        SnackBar(
          content: Text(
            l10n.subscriptionsShareFailed(friendlyError(e, ctx)),
          ),
        ),
      );
    }
  }
}
