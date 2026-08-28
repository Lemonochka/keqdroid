/// Состав карточки подписки: что на ней показано.
///
/// Карточка — это шесть-семь блоков, и нужны они разным людям в разной мере.
/// Кому-то важен только остаток трафика, кому-то мешает объявление провайдера
/// (с него всё и началось: реклама бота в чужой карточке выглядит как реклама
/// в приложении). Поэтому состав — настройка подписки, а не константа вёрстки.
library;

/// Части карточки, которые можно убрать.
///
/// Убирается ОФОРМЛЕНИЕ и факты второго плана. Просроченная подписка, `http`
/// вместо `https` и неудачное обновление в этот список не входят намеренно:
/// спрятанная проблема остаётся проблемой, но выглядит как её отсутствие —
/// ровно то, из-за чего «просто не обновляется» и принимают за баг клиента.
/// Имя подписки с кнопками обновления и меню не убирается тоже: без него
/// карточка перестаёт быть карточкой этой подписки.
enum SubscriptionCardElement {
  /// Объявление провайдера: техработы, смена адреса, ссылка на бота.
  announce,

  /// Трафик крупно и шкала под ним.
  usage,

  /// Тихая строка фактов: срок действия и когда обновлялось.
  meta,

  /// Ряд чипов: интервал автообновления, страница подписки, поддержка.
  actions;

  /// Разбор имени из хранилища. Null — ключ незнакомый: настройку писала
  /// версия новее этой, и молча проглотить её лучше, чем уронить весь список
  /// подписок на разборе одного поля.
  static SubscriptionCardElement? byName(String? name) {
    for (final element in values) {
      if (element.name == name) return element;
    }
    return null;
  }

  /// Набор из хранилища: список имён → множество. Мусор и незнакомые имена
  /// отбрасываются, а не ломают запись.
  static Set<SubscriptionCardElement> setFromJson(Object? raw) {
    if (raw is! List) return const {};
    return {
      for (final item in raw) ?byName(item is String ? item : null),
    };
  }
}

/// Готовые наборы состава — то, что в редакторе выбирается одним нажатием.
///
/// Пресет не хранится: хранится результат (множество скрытых частей), а пресет
/// вычисляется из него обратно ([of]). Иначе два источника правды — набор и
/// его имя — разъезжались бы на первом же переключении отдельной галочки.
enum SubscriptionCardPreset {
  /// Всё, что карточка знает про подписку.
  full(<SubscriptionCardElement>{}),

  /// Без объявления и без строки фактов: имя, трафик и кнопки.
  compact(<SubscriptionCardElement>{
    SubscriptionCardElement.announce,
    SubscriptionCardElement.meta,
  }),

  /// Только имя и трафик — плитка вместо карточки.
  minimal(<SubscriptionCardElement>{
    SubscriptionCardElement.announce,
    SubscriptionCardElement.meta,
    SubscriptionCardElement.actions,
  }),

  /// Собрано вручную и ни с одним набором не совпало. Своего состава не имеет
  /// — этот пресет нельзя «выбрать», в него попадают.
  custom(null);

  const SubscriptionCardPreset(this.hidden);

  /// Что пресет убирает с карточки. Null — только у [custom].
  final Set<SubscriptionCardElement>? hidden;

  /// Пресеты, которые предлагаются в редакторе.
  static List<SubscriptionCardPreset> get selectable =>
      values.where((p) => p.hidden != null).toList();

  /// Какому пресету отвечает текущий состав. [custom] — никакому.
  static SubscriptionCardPreset of(Set<SubscriptionCardElement> hidden) {
    for (final preset in values) {
      final byPreset = preset.hidden;
      if (byPreset != null &&
          byPreset.length == hidden.length &&
          byPreset.every(hidden.contains)) {
        return preset;
      }
    }
    return custom;
  }
}
