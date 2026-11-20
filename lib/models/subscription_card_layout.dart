library;

enum SubscriptionCardElement {
  announce,

  usage,

  meta,

  actions;

  static SubscriptionCardElement? byName(String? name) {
    for (final element in values) {
      if (element.name == name) return element;
    }
    return null;
  }

  static Set<SubscriptionCardElement> setFromJson(Object? raw) {
    if (raw is! List) return const {};
    return {for (final item in raw) ?byName(item is String ? item : null)};
  }
}

enum SubscriptionCardPreset {
  full(<SubscriptionCardElement>{}),

  compact(<SubscriptionCardElement>{
    SubscriptionCardElement.announce,
    SubscriptionCardElement.meta,
  }),

  minimal(<SubscriptionCardElement>{
    SubscriptionCardElement.announce,
    SubscriptionCardElement.meta,
    SubscriptionCardElement.actions,
  }),

  custom(null);

  const SubscriptionCardPreset(this.hidden);

  final Set<SubscriptionCardElement>? hidden;

  static List<SubscriptionCardPreset> get selectable =>
      values.where((p) => p.hidden != null).toList();

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
