import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/shared/ui/app_theme.dart';

import '../../utils/bidi.dart';
import 'editor_layers.dart';

// раскладка ключей узла mihomo по тем же слоям, что у ссылки. подписи ключами, как в docs/config/proxies:
// узлы бывают двадцати типов, и перевод каждого поля разошёлся бы с тем, что пишет провайдер
const _serverKeys = {
  'server', 'port', 'uuid', 'password', 'username', 'cipher', 'auth',
  'auth-str', 'token', 'psk', 'version', 'private-key', 'public-key',
  'pre-shared-key', 'ip', 'ipv6', 'peers',
};
const _securityKeys = {
  'tls', 'sni', 'servername', 'alpn', 'skip-cert-verify', 'client-fingerprint',
  'fingerprint', 'reality-opts', 'ech-opts',
};
const _transportKeys = {
  'network', 'flow', 'encryption', 'packet-encoding', 'ws-opts', 'grpc-opts',
  'h2-opts', 'http-opts', 'xhttp-opts', 'smux', 'plugin', 'plugin-opts',
  'udp-over-tcp', 'udp-over-tcp-version',
};
const _tuningKeys = {
  'up', 'down', 'obfs', 'obfs-password', 'ports', 'hop-interval',
  'congestion-controller', 'udp-relay-mode', 'reduce-rtt', 'mtu', 'reserved',
  'allowed-ips', 'persistent-keepalive', 'amnezia-wg-option',
};
// имя и тип в шапке: смена типа это другой протокол, её делают текстом
const _hidden = {'name', 'type'};

// узел готового Clash полями. источник строка узла: пока поля не трогали, конфиг уходит как был
class ClashNodeFields extends StatefulWidget {
  const ClashNodeFields({
    super.key,
    required this.json,
    required this.onChanged,
    required this.decoration,
  });

  final String json;
  final ValueChanged<String> onChanged;
  final InputDecoration Function({String? label, String? hint}) decoration;

  @override
  State<ClashNodeFields> createState() => _ClashNodeFieldsState();
}

class _ClashNodeFieldsState extends State<ClashNodeFields> {
  late Map<String, dynamic> _node;
  final _ctrls = <String, TextEditingController>{};
  final _invalid = <String>{};
  late final TextEditingController _rest = TextEditingController();
  String _emitted = '';

  @override
  void initState() {
    super.initState();
    _load(widget.json);
  }

  @override
  void didUpdateWidget(ClashNodeFields old) {
    super.didUpdateWidget(old);
    if (widget.json != _emitted && widget.json != old.json) _load(widget.json);
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    _rest.dispose();
    super.dispose();
  }

  bool _classified(String key) =>
      _hidden.contains(key) ||
      _serverKeys.contains(key) ||
      _securityKeys.contains(key) ||
      _transportKeys.contains(key) ||
      _tuningKeys.contains(key);

  void _load(String json) {
    _emitted = json;
    final decoded = jsonDecode(json);
    _node = (decoded as Map).cast<String, dynamic>();
    for (final c in _ctrls.values) {
      c.dispose();
    }
    _ctrls.clear();
    _invalid.clear();
    final rest = {
      for (final e in _node.entries)
        if (!_classified(e.key)) e.key: e.value,
    };
    _rest.text =
        rest.isEmpty ? '' : const JsonEncoder.withIndent('  ').convert(rest);
  }

  void _emit() {
    _emitted = jsonEncode(_node);
    widget.onChanged(_emitted);
  }

  static bool _scalar(Object? v) => v == null || v is String || v is num;

  static String _show(Object? v) {
    if (v is List) return v.join(', ');
    return v == null ? '' : '$v';
  }

  // тип значения сохраняем: порт числом, alpn списком, иначе mihomo отказал бы конфигу
  static Object? _typed(Object? was, String text) {
    final t = text.trim();
    if (was is List) {
      final parts = [
        for (final p in t.split(',')) if (p.trim().isNotEmpty) p.trim(),
      ];
      final numeric = was.isNotEmpty && was.every((e) => e is num);
      return [for (final p in parts) numeric ? (num.tryParse(p) ?? p) : p];
    }
    if (was is int) return int.tryParse(t) ?? t;
    if (was is double) return double.tryParse(t) ?? t;
    return t;
  }

  Widget _jsonField(String id, String label, Object? value, ValueChanged<Object?> set) {
    final ctrl = _ctrls.putIfAbsent(
      id,
      () => TextEditingController(
        text: const JsonEncoder.withIndent('  ').convert(value),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        textDirection: technicalInputDirection,
        minLines: 2,
        maxLines: 10,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppTheme.text(context),
              fontFamily: 'monospace',
            ),
        decoration: widget.decoration(label: label).copyWith(
              errorText: _invalid.contains(id)
                  ? AppLocalizations.of(context)!.serverEditorXhttpRestInvalid
                  : null,
            ),
        onChanged: (text) {
          Object? parsed;
          var ok = true;
          try {
            parsed = jsonDecode(text);
          } on FormatException {
            ok = false;
          }
          setState(() => ok ? _invalid.remove(id) : _invalid.add(id));
          if (!ok) return;
          set(parsed);
          _emit();
        },
      ),
    );
  }

  Widget _value(Map<String, dynamic> target, String key, String id) {
    final value = target[key];
    if (value is bool) {
      return SwitchListTile(
        value: value,
        dense: true,
        contentPadding: EdgeInsets.zero,
        activeThumbColor: AppTheme.accent(context),
        activeTrackColor: AppTheme.accent(context).withValues(alpha: 0.32),
        title: Text(
          key,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppTheme.text(context)),
        ),
        onChanged: (v) {
          setState(() => target[key] = v);
          _emit();
        },
      );
    }
    if (value is Map) {
      final nested = value.cast<String, dynamic>();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, top: 4, bottom: 8),
            child: Text(
              key,
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: AppTheme.textLight(context)),
            ),
          ),
          for (final child in nested.keys.toList())
            _value(nested, child, '$id.$child'),
        ],
      );
    }
    final scalarList = value is List && value.every(_scalar);
    if (value is List && !scalarList) {
      return _jsonField(id, key, value, (v) => target[key] = v);
    }
    final ctrl =
        _ctrls.putIfAbsent(id, () => TextEditingController(text: _show(value)));
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        textDirection: technicalInputDirection,
        keyboardType: value is num ? TextInputType.number : TextInputType.text,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: AppTheme.text(context)),
        decoration: widget.decoration(label: key),
        onChanged: (text) {
          target[key] = _typed(value, text);
          _emit();
        },
      ),
    );
  }

  EditorLayer? _layer(IconData icon, String title, Set<String> keys) {
    final present = [
      for (final key in _node.keys)
        if (keys.contains(key)) key,
    ];
    if (present.isEmpty) return null;
    return EditorLayer(icon, title, [
      for (final key in present) _value(_node, key, key),
    ]);
  }

  void _onRest(String text) {
    final trimmed = text.trim();
    Map<String, dynamic>? parsed;
    if (trimmed.isEmpty) {
      parsed = <String, dynamic>{};
    } else {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map) parsed = decoded.cast<String, dynamic>();
      } on FormatException {
        parsed = null;
      }
    }
    setState(() => parsed == null ? _invalid.add('rest') : _invalid.remove('rest'));
    if (parsed == null) return;
    _node.removeWhere((key, _) => !_classified(key));
    _node.addAll(parsed);
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return EditorLayers([
      ?_layer(Icons.dns_rounded, l10n.serverEditorSectionGeneral, _serverKeys),
      ?_layer(Icons.shield_rounded, l10n.serverEditorSectionSecurity, _securityKeys),
      ?_layer(Icons.alt_route_rounded, l10n.serverEditorSectionTransport, _transportKeys),
      ?_layer(Icons.speed_rounded, l10n.serverEditorSectionProtocol, _tuningKeys),
      EditorLayer(Icons.data_object_rounded, l10n.serverEditorClashRest, [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
            controller: _rest,
            textDirection: technicalInputDirection,
            minLines: 2,
            maxLines: 12,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.text(context),
                  fontFamily: 'monospace',
                ),
            decoration: widget.decoration(hint: '{ }').copyWith(
                  errorText: _invalid.contains('rest')
                      ? l10n.serverEditorXhttpRestInvalid
                      : null,
                ),
            onChanged: _onRest,
          ),
        ),
      ]),
    ]);
  }
}
