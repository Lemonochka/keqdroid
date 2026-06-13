import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/utils/kphttp_config_gen.dart';
import 'package:keqdroid/utils/kphttp_profile.dart';

void main() {
  const sampleJson = '''
{
  "protocol": "kphttp",
  "version": 1,
  "remark": "Test VPS",
  "server": "203.0.113.10",
  "port": 443,
  "transport": "h2",
  "crypto": {
    "psk": "SHARED-SECRET-WITH-SERVER",
    "uri_window_secs": 30,
    "path_prefix": "/assets/v1/"
  },
  "tls": {
    "enabled": true,
    "sni": "cdn.example.com",
    "insecure": false
  },
  "uplink": {
    "mode": "packet-up",
    "batch_interval_ms": 5,
    "max_buffer_bytes": 16384
  },
  "obfuscation": {
    "padding_grid": 128,
    "random_padding_min": 0,
    "random_padding_max": 64,
    "dummy_posts": true,
    "dummy_jitter_min_ms": 2000,
    "dummy_jitter_max_ms": 8000
  },
  "headers": {
    "host": "cdn.example.com",
    "user_agent": "Mozilla/5.0"
  },
  "core": {
    "uuid": "00000000-0000-0000-0000-000000000001"
  }
}
''';

  test('parses JSON KpHTTP profile', () {
    final profile = KphttpProfile.parse(sampleJson);
    expect(profile.server, '203.0.113.10');
    expect(profile.port, 443);
    expect(profile.core.uuid, '00000000-0000-0000-0000-000000000001');
  });

  test('round-trips through kphttp:// storage URI', () {
    final uri = KphttpProfile.parse(sampleJson).toStorageUri();
    expect(uri.startsWith('kphttp://'), isTrue);
    final roundTrip = KphttpProfile.parse(uri);
    expect(roundTrip.server, '203.0.113.10');
    expect(roundTrip.remark, 'Test VPS');
  });

  test('splitPastedConfigs keeps multi-line JSON as one entry', () {
    final parts = KphttpProfile.splitPastedConfigs(sampleJson);
    expect(parts.length, 1);
    expect(KphttpProfile.isKphttpConfig(parts.first), isTrue);
  });

  test('splitPastedConfigs still splits multiple URI lines', () {
    final uri = KphttpProfile.parse(sampleJson).toStorageUri();
    final parts = KphttpProfile.splitPastedConfigs('$uri\n$uri');
    expect(parts.length, 2);
  });

  test('generates client TOML with local socks port', () {
    final toml = KphttpConfigGen.generateToml(sampleJson, localSocksPort: 2080);
    expect(toml, contains('server = "203.0.113.10:443"'));
    expect(toml, contains('transport = "h2"'));
    expect(toml, contains('listen = "127.0.0.1:2080"'));
    expect(toml, contains('mode = "socks5"'));
    expect(toml, contains('uuid = "00000000-0000-0000-0000-000000000001"'));
  });
}
