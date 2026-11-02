part of 'providers.dart';

final subscriptionTemplateProvider =
    Provider.family<ClashTemplate?, String>((ref, subscriptionId) {
  ref.watch(subscriptionsProvider.select((a) => a.value
      ?.where((s) => s.id == subscriptionId)
      .firstOrNull
      ?.lastUpdatedAt));
  final applies = ref.watch(settingsNotifierProvider
      .select((a) => a.value != null && clashTemplateApplies(a.value!)));
  if (!applies) return null;
  final raw = ref.read(storageProvider).getClashTemplate(subscriptionId);
  return raw == null ? null : ClashTemplate.fromBody(raw);
});

final liveTemplateGroupsProvider = FutureProvider.autoDispose
    .family<Map<String, MihomoGroupState>?, String>((ref, subscriptionId) async {
  final connected = ref.watch(vpnStateProvider
      .select((a) => a.value?.status == VpnStatus.connected));
  final activeSub = ref.watch(serversProvider
      .select((s) => s.activeServer?.subscriptionId));
  if (!connected || activeSub != subscriptionId) return null;
  return MihomoGroupsApi.fetch();
});

