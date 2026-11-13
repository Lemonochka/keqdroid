import '../models/tun_settings.dart';
import '../tunnel/app_routing_mode.dart';

const kTunInterfaceAddress = '172.19.0.1';

const kTunInterfacePrefix = '$kTunInterfaceAddress/30';

const kTunInterfaceIpv6Prefix = 'fdfe:dcba:9876::1/126';

// резолвер системы на Windows, следующий адрес в /30. держать в паре с ConfigGeneratorV2._androidTunDns
const kTunDnsAddress = '172.19.0.2';

// wintun считает GUID из имени, у чужого клиента с тем же именем адаптер общий
const kTunInterfaceName = 'tun-keqdis';

class DesktopTunOptions {
  const DesktopTunOptions({
    required this.windows,
    required this.mtu,
    this.autoRoute = true,
    this.strictRoute = false,
    this.captureIpv6 = false,
    this.udpTimeoutSec = TunSettings.defaultUdpTimeoutSec,
    this.routingMode = AppRoutingMode.allProxy,
    this.managedProcessNames = const [],
    this.appProcessName = '',
  });

  final bool windows;
  final int mtu;
  final bool autoRoute;
  final bool strictRoute;
  final bool captureIpv6;
  final int udpTimeoutSec;
  final AppRoutingMode routingMode;
  final List<String> managedProcessNames;
  final String appProcessName;
}
