import '../tunnel/app_routing_mode.dart';
import 'process_name_utils.dart';

AppRoutingMode routingModeFromSplit({
  required Set<String> includePackages,
  required Set<String> excludePackages,
}) {
  if (includePackages.isNotEmpty) {
    return AppRoutingMode.onlySelected;
  }
  if (excludePackages.isNotEmpty) {
    return AppRoutingMode.allExceptSelected;
  }
  return AppRoutingMode.allProxy;
}

List<String> processNamesForSplit({
  required Set<String> includePackages,
  required Set<String> excludePackages,
}) {
  final ids = <String>{...includePackages, ...excludePackages};
  return ids.map(normalizeProcessName).where((e) => e.isNotEmpty).toList();
}
