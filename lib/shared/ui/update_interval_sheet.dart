import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/providers/providers.dart';
import 'package:keqdroid/shared/ui/app_theme.dart';
import 'package:keqdroid/shared/ui/expressive.dart';
import 'package:keqdroid/shared/ui/expressive_group.dart';

/// Шторка выбора интервала автообновления подписки.
///
/// Открывается из двух мест: с чипа интервала на карточке подписки и с такого
/// же чипа в шапке её группы серверов. Это одна настройка, и шторка у неё одна
/// — раньше их было две, написанных отдельно, и разойтись они могли молча:
/// правку в одной копии никто бы не перенёс во вторую. Оба входа сторожит
/// `test/widgets/update_interval_sheet_test.dart`.
void showUpdateIntervalSheet(
  BuildContext context,
  WidgetRef ref,
  Subscription sub,
) {
  const options = [1, 3, 6, 12, 24, 48, 72];
  // Локализацию и цвета берём здесь: это функция верхнего уровня, взять их
  // из состояния экрана ей неоткуда.
  final l10n = AppLocalizations.of(context)!;
  final textLightColor = AppTheme.textLight(context);
  final textColor = AppTheme.text(context);

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      final maxHeight = MediaQuery.sizeOf(ctx).height * 0.85;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 12),
            children: [
              Text(
                l10n.subscriptionsAutoUpdateInterval,
                textAlign: TextAlign.center,
                style: Theme.of(ctx)
                    .textTheme
                    .emphasized(Theme.of(ctx).textTheme.titleLarge)
                    ?.copyWith(color: textColor),
              ),
              const SizedBox(height: 4),
              Text(
                l10n.subscriptionsCurrentInterval(sub.updateIntervalHours),
                textAlign: TextAlign.center,
                style: Theme.of(ctx)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: textLightColor),
              ),
              const SizedBox(height: 12),
              // Это выбор, а не список действий: текущий интервал виден
              // заливкой сегмента, а не только жирной подписью с галочкой.
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ExpressiveGroup(
                  children: [
                    // Выключение живёт здесь, а не отдельным значком в
                    // карточке: это одна настройка, и орган управления у неё
                    // должен быть один.
                    ExpressiveActionTile(
                      icon: Icons.update_disabled_rounded,
                      title: l10n.subscriptionsAutoUpdateOff,
                      selected: !sub.autoUpdate,
                      onTap: () {
                        ref
                            .read(subscriptionsProvider.notifier)
                            .setUpdateSchedule(sub.id, autoUpdate: false);
                        Navigator.pop(ctx);
                      },
                    ),
                    for (final h in options)
                      ExpressiveActionTile(
                        icon: h < 24
                            ? Icons.schedule_rounded
                            : Icons.calendar_today_rounded,
                        title: h == 1
                            ? l10n.subscriptionsEveryHour
                            : h < 24
                            ? l10n.subscriptionsEveryHours(h)
                            : h == 24
                            ? l10n.subscriptionsEveryDay
                            : l10n.subscriptionsEveryDays(h ~/ 24),
                        selected:
                            sub.autoUpdate && h == sub.updateIntervalHours,
                        onTap: () {
                          // Выбор интервала означает «включить и поставить
                          // его» — одной операцией, а не двумя подряд.
                          ref
                              .read(subscriptionsProvider.notifier)
                              .setUpdateSchedule(
                                sub.id,
                                autoUpdate: true,
                                hours: h,
                              );
                          Navigator.pop(ctx);
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
