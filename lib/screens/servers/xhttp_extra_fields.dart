import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/shared/ui/app_theme.dart';

import '../../utils/bidi.dart';

// ключи по SplitHTTPConfig и XmuxConfig в infra/conf/transport_method.go Xray. подписи ключами:
// так их пишут панели и документация, перевод разошёлся бы с тем, что человек видит у провайдера
enum _Kind { number, text, flag }

const _padding = <(String, _Kind)>[
  ('xPaddingBytes', _Kind.number),
  ('xPaddingObfsMode', _Kind.flag),
  ('xPaddingKey', _Kind.text),
  ('xPaddingHeader', _Kind.text),
  ('xPaddingPlacement', _Kind.text),
  ('xPaddingMethod', _Kind.text),
];

const _uplink = <(String, _Kind)>[
  ('uplinkHTTPMethod', _Kind.text),
  ('uplinkDataPlacement', _Kind.text),
  ('uplinkDataKey', _Kind.text),
  ('uplinkChunkSize', _Kind.number),
  ('scMaxEachPostBytes', _Kind.number),
  ('scMinPostsIntervalMs', _Kind.number),
  ('scMaxBufferedPosts', _Kind.number),
  ('scStreamUpServerSecs', _Kind.number),
  ('noGRPCHeader', _Kind.flag),
  ('noSSEHeader', _Kind.flag),
];

const _session = <(String, _Kind)>[
  ('sessionIDPlacement', _Kind.text),
  ('sessionIDKey', _Kind.text),
  ('sessionIDTable', _Kind.text),
  ('sessionIDLength', _Kind.number),
  ('seqPlacement', _Kind.text),
  ('seqKey', _Kind.text),
];

const _xmux = <(String, _Kind)>[
  ('maxConcurrency', _Kind.number),
  ('maxConnections', _Kind.number),
  ('cMaxReuseTimes', _Kind.number),
  ('hMaxRequestTimes', _Kind.number),
  ('hMaxReusableSecs', _Kind.number),
  ('hKeepAlivePeriod', _Kind.number),
];

// extra XHTTP полями вместо одной строки JSON. строка остаётся источником: пока поля не трогали, она уходит
// в ссылку байт в байт, а ключи, которых тут нет (headers, downloadSettings), живут в «остальном» как есть
class XhttpExtraFields extends StatefulWidget {
  const XhttpExtraFields({
    super.key,
    required this.json,
    required this.onChanged,
    required this.decoration,
  });

  final String json;
  final ValueChanged<String> onChanged;
  final InputDecoration Function({String? label, String? hint}) decoration;

  static Map<String, dynamic>? parse(String json) {
    final text = json.trim();
    if (text.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(text);
      return decoded is Map ? decoded.cast<String, dynamic>() : null;
    } on FormatException {
      return null;
    }
  }

  @override
  State<XhttpExtraFields> createState() => _XhttpExtraFieldsState();
}

class _XhttpExtraFieldsState extends State<XhttpExtraFields> {
  late Map<String, dynamic> _map;
  final _ctrls = <String, TextEditingController>{};
  late final TextEditingController _rest = TextEditingController();
  bool _restInvalid = false;
  String _emitted = '';

  static final _known = {
    for (final (key, _) in [..._padding, ..._uplink, ..._session]) key,
    'xmux',
  };

  @override
  void initState() {
    super.initState();
    _load(widget.json);
  }

  @override
  void didUpdateWidget(XhttpExtraFields old) {
    super.didUpdateWidget(old);
    // чужая правка (переход из «Текста») пересобирает поля; своя пришла бы тем же текстом
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

  void _load(String json) {
    _emitted = json;
    _map = XhttpExtraFields.parse(json) ?? <String, dynamic>{};
    for (final c in _ctrls.values) {
      c.dispose();
    }
    _ctrls.clear();
    final rest = {
      for (final e in _map.entries)
        if (!_known.contains(e.key)) e.key: e.value,
    };
    _rest.text =
        rest.isEmpty ? '' : const JsonEncoder.withIndent('  ').convert(rest);
    _restInvalid = false;
  }

  Map<String, dynamic> _xmuxMap() {
    final x = _map['xmux'];
    return x is Map ? x.cast<String, dynamic>() : <String, dynamic>{};
  }

  static String _show(Object? v) {
    if (v == null) return '';
    if (v is Map) {
      final from = v['from'], to = v['to'];
      return from == to ? '$from' : '$from-$to';
    }
    return '$v';
  }

  TextEditingController _ctrl(String id, Object? value) =>
      _ctrls.putIfAbsent(id, () => TextEditingController(text: _show(value)));

  void _emit() {
    _emitted = _map.isEmpty ? '' : jsonEncode(_map);
    widget.onChanged(_emitted);
  }

  void _set(Map<String, dynamic> target, String key, _Kind kind, String text) {
    final t = text.trim();
    if (t.isEmpty) {
      target.remove(key);
    } else if (kind == _Kind.number && RegExp(r'^\d+$').hasMatch(t)) {
      target[key] = int.parse(t);
    } else {
      target[key] = t;
    }
  }

  void _onRest(String text) {
    final parsed = XhttpExtraFields.parse(text);
    setState(() => _restInvalid = parsed == null);
    if (parsed == null) return;
    _map.removeWhere((key, _) => !_known.contains(key));
    _map.addAll(parsed);
    _emit();
  }

  Widget _field(String key, _Kind kind, {bool inXmux = false}) {
    final target = inXmux ? _xmuxMap() : _map;
    if (kind == _Kind.flag) {
      return SwitchListTile(
        value: target[key] == true,
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
          setState(() {
            if (v) {
              target[key] = true;
            } else {
              target.remove(key);
            }
            if (inXmux) _putXmux(target);
          });
          _emit();
        },
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: _ctrl(inXmux ? 'xmux.$key' : key, target[key]),
        textDirection: technicalInputDirection,
        keyboardType: TextInputType.text,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: AppTheme.text(context)),
        decoration: widget.decoration(
          label: key,
          hint: kind == _Kind.number ? '100-1000' : null,
        ),
        onChanged: (text) {
          _set(target, key, kind, text);
          if (inXmux) _putXmux(target);
          _emit();
        },
      ),
    );
  }

  void _putXmux(Map<String, dynamic> xmux) {
    if (xmux.isEmpty) {
      _map.remove('xmux');
    } else {
      _map['xmux'] = xmux;
    }
  }

  Widget _group(String title, List<Widget> fields) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, top: 4, bottom: 8),
            child: Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: AppTheme.textLight(context)),
            ),
          ),
          ...fields,
        ],
      );

  // пустые поля прячем: их три десятка, а у сервера заданы обычно два-три
  bool _all = false;

  List<Widget> _fields(
    List<(String, _Kind)> keys, {
    bool inXmux = false,
  }) {
    final target = inXmux ? _xmuxMap() : _map;
    return [
      for (final (key, kind) in keys)
        if (_all ||
            target.containsKey(key) ||
            _ctrls.containsKey(inXmux ? 'xmux.$key' : key))
          _field(key, kind, inXmux: inXmux),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final groups = [
      (l10n.serverEditorXhttpPadding, _fields(_padding)),
      (l10n.serverEditorXhttpUplink, _fields(_uplink)),
      (l10n.serverEditorXhttpSession, _fields(_session)),
      (l10n.serverEditorXhttpXmux, _fields(_xmux, inXmux: true)),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (title, fields) in groups)
          if (fields.isNotEmpty) _group(title, fields),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            onPressed: () => setState(() => _all = !_all),
            icon: Icon(
              _all ? Icons.unfold_less_rounded : Icons.unfold_more_rounded,
              size: 18,
            ),
            label: Text(
              _all ? l10n.serverEditorXhttpHideEmpty : l10n.serverEditorXhttpShowAll,
            ),
          ),
        ),
        if (_all || _rest.text.isNotEmpty) _group(l10n.serverEditorXhttpRest, [
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
              decoration: widget.decoration(hint: '"headers": { }').copyWith(
                    errorText:
                        _restInvalid ? l10n.serverEditorXhttpRestInvalid : null,
                  ),
              onChanged: _onRest,
            ),
          ),
        ]),
      ],
    );
  }
}
