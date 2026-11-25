import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/tunnel/connection_mode.dart';
import 'package:keqdroid/tunnel/mihomo_session_shell.dart';
import 'package:keqdroid/tunnel/tunnel_session_request.dart';
import 'package:keqdroid/tunnel/vpn_backend.dart';

TunnelSessionRequest _session(
  Map<String, dynamic> config, {
  ConnectionMode mode = ConnectionMode.tun,
  List<String> exclude = const [],
  bool processLog = false,
}) => TunnelSessionRequest(
  mode: mode,
  vpnBackend: VpnBackend.mihomo,
  xrayConfig: '',
  mihomoConfig: jsonEncode(config),
  excludePackages: exclude,
  processLog: processLog,
);

Map<String, dynamic> _config({
  String server = 'a.example.com',
  int mtu = 9000,
  String nameserver = '1.1.1.1',
  String dnsListen = '127.0.0.1:1053',
}) => {
  'mixed-port': 7890,
  'external-controller': '127.0.0.1:9090',
  'secret': 's',
  'tun': {'enable': true, 'stack': 'mixed', 'mtu': mtu},
  'dns': {
    'enable': true,
    'listen': dnsListen,
    'nameserver': [nameserver],
    'nameserver-policy': {server: nameserver},
  },
  'proxies': [
    {'name': 'proxy', 'server': server, 'port': 443},
  ],
  'rules': ['DOMAIN,$server,DIRECT', 'MATCH,proxy'],
};

void main() {
  test('другой сервер и его правила оболочку не меняют', () {
    expect(
      sameTunnelShell(
        _session(_config()),
        _session(_config(server: 'b.example.com', nameserver: '8.8.8.8')),
      ),
      isTrue,
    );
  });

  test('другой TUN или слушатель DNS требуют переподключения', () {
    expect(
      sameTunnelShell(_session(_config()), _session(_config(mtu: 1500))),
      isFalse,
    );
    expect(
      sameTunnelShell(
        _session(_config()),
        _session(_config(dnsListen: '127.0.0.1:2053')),
      ),
      isFalse,
    );
  });

  test('другой режим или список приложений требуют переподключения', () {
    expect(
      sameTunnelShell(
        _session(_config()),
        _session(_config(), mode: ConnectionMode.proxy),
      ),
      isFalse,
    );
    expect(
      sameTunnelShell(
        _session(_config()),
        _session(_config(), exclude: const ['org.telegram.messenger']),
      ),
      isFalse,
    );
    expect(
      sameTunnelShell(
        _session(_config()),
        _session(_config(), processLog: true),
      ),
      isFalse,
    );
  });

  test('нечитаемый конфиг на ходу не меняют', () {
    const broken = TunnelSessionRequest(
      mode: ConnectionMode.tun,
      vpnBackend: VpnBackend.mihomo,
      xrayConfig: '',
      mihomoConfig: 'proxies: [',
    );
    expect(sameTunnelShell(_session(_config()), broken), isFalse);
  });
}
