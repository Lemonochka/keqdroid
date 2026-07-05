// copyWithPrevious помечен @internal, но только он воспроизводит реальный
// переход riverpod при инвалидации (AsyncLoading, сохранивший прежний value).
// ignore_for_file: invalid_use_of_internal_member
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/services/update_service.dart';
import 'package:keqdroid/shared/ui/update_dialog.dart';

UpdateInfo _info(String version) => UpdateInfo(
      currentVersion: '1.0.0',
      latestVersion: version,
      downloadUrl: 'https://example.com/app.apk',
      apkSize: 1,
    );

void main() {
  setUp(() {
    UpdatePrompt.promptedVersionThisSession = null;
  });

  test('prompts on first load of an update', () {
    // первый эмит: loading без значения → данные
    expect(
      shouldAutoPromptForUpdate(
        const AsyncLoading<UpdateInfo?>(),
        AsyncData<UpdateInfo?>(_info('v2.0.0')),
      ),
      isTrue,
    );
  });

  test('does not prompt when there is no update', () {
    expect(
      shouldAutoPromptForUpdate(
        const AsyncLoading<UpdateInfo?>(),
        const AsyncData<UpdateInfo?>(null),
      ),
      isFalse,
    );
  });

  test('periodic re-check with the same version does not re-prompt', () {
    UpdatePrompt.markShown('v2.0.0');
    // инвалидация провайдера: loading с прежним значением → те же данные
    final prev = AsyncLoading<UpdateInfo?>()
        .copyWithPrevious(AsyncData<UpdateInfo?>(_info('v2.0.0')));
    expect(
      shouldAutoPromptForUpdate(prev, AsyncData<UpdateInfo?>(_info('v2.0.0'))),
      isFalse,
    );
  });

  test('a NEW version released mid-session prompts again', () {
    // v2 уже показывали; периодический ре-чек нашёл v3
    UpdatePrompt.markShown('v2.0.0');
    final prev = AsyncLoading<UpdateInfo?>()
        .copyWithPrevious(AsyncData<UpdateInfo?>(_info('v2.0.0')));
    expect(
      shouldAutoPromptForUpdate(prev, AsyncData<UpdateInfo?>(_info('v3.0.0'))),
      isTrue,
    );
  });

  test('update appearing after an "up to date" session start prompts', () {
    // на старте обновления не было (null), таймер нашёл новую версию
    final prev = AsyncLoading<UpdateInfo?>()
        .copyWithPrevious(const AsyncData<UpdateInfo?>(null));
    expect(
      shouldAutoPromptForUpdate(prev, AsyncData<UpdateInfo?>(_info('v2.0.0'))),
      isTrue,
    );
  });
}
