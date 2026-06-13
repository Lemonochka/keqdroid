import 'kphttp_profile.dart';

/// Builds kphttp-client TOML from a parsed profile.
class KphttpConfigGen {
  static String generateToml(
    String input, {
    required int localSocksPort,
  }) {
    final profile = KphttpProfile.parse(input);
    return _buildToml(profile, localSocksPort: localSocksPort);
  }

  static String _buildToml(KphttpProfile profile, {required int localSocksPort}) {
    final buffer = StringBuffer()
      ..writeln('server = "${_escapeToml(profile.server)}:${profile.port}"')
      ..writeln('transport = "${profile.transport}"')
      ..writeln()
      ..writeln('[crypto]')
      ..writeln('psk = "${_escapeToml(profile.crypto.psk)}"')
      ..writeln('uri_window_secs = ${profile.crypto.uriWindowSecs}')
      ..writeln('path_prefix = "${_escapeToml(profile.crypto.pathPrefix)}"')
      ..writeln()
      ..writeln('[tls]')
      ..writeln('enabled = ${profile.tls.enabled}')
      ..writeln('sni = "${_escapeToml(profile.tls.sni)}"');
    if (profile.tls.serverName != null && profile.tls.serverName!.isNotEmpty) {
      buffer.writeln('server_name = "${_escapeToml(profile.tls.serverName!)}"');
    }
    buffer
      ..writeln('insecure = ${profile.tls.insecure}')
      ..writeln()
      ..writeln('[uplink]')
      ..writeln('mode = "${profile.uplink.mode}"')
      ..writeln('batch_interval_ms = ${profile.uplink.batchIntervalMs}')
      ..writeln('max_buffer_bytes = ${profile.uplink.maxBufferBytes}')
      ..writeln()
      ..writeln('[obfuscation]')
      ..writeln('padding_grid = ${profile.obfuscation.paddingGrid}')
      ..writeln('random_padding_min = ${profile.obfuscation.randomPaddingMin}')
      ..writeln('random_padding_max = ${profile.obfuscation.randomPaddingMax}')
      ..writeln('dummy_posts = ${profile.obfuscation.dummyPosts}')
      ..writeln('dummy_jitter_min_ms = ${profile.obfuscation.dummyJitterMinMs}')
      ..writeln('dummy_jitter_max_ms = ${profile.obfuscation.dummyJitterMaxMs}');

    final headers = profile.headers.toJson();
    if (headers.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('[headers]');
      for (final entry in headers.entries) {
        if (entry.key == 'extra' && entry.value is Map) {
          final extra = Map<String, dynamic>.from(entry.value as Map);
          if (extra.isNotEmpty) {
            buffer.writeln('[headers.extra]');
            for (final e in extra.entries) {
              buffer.writeln(
                '${_escapeTomlKey(e.key.toString())} = "${_escapeToml(e.value.toString())}"',
              );
            }
          }
        } else {
          buffer.writeln(
            '${_escapeTomlKey(entry.key)} = "${_escapeToml(entry.value.toString())}"',
          );
        }
      }
    }

    buffer
      ..writeln()
      ..writeln('[core]')
      ..writeln('uuid = "${_escapeToml(profile.core.uuid)}"')
      ..writeln()
      ..writeln('[local]')
      ..writeln('listen = "127.0.0.1:$localSocksPort"')
      ..writeln('mode = "socks5"');

    return buffer.toString();
  }

  static String _escapeToml(String value) =>
      value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');

  static String _escapeTomlKey(String key) {
    if (RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(key)) return key;
    return '"${_escapeToml(key)}"';
  }
}
