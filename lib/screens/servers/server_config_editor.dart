import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/shared/ui/app_theme.dart';

import '../../models/server_item.dart';
import '../../models/server_name_utils.dart';
import '../../providers/providers.dart';
import '../../services/vpn_engine.dart';
import '../../utils/error_messages.dart';
import '../../utils/raw_share_uri.dart';

/// GUI-редактор конфигурации сервера: разбирает share-ссылку (vless / vmess /
/// trojan / ss / hysteria2) на поля по протоколу, даёт править их формой с
/// дропдаунами и собирает ссылку обратно, сохраняя незнакомые query-параметры
/// как есть. AWG/SSR и нераспознанные конфиги редактируются как сырой текст.
class ServerConfigEditorScreen extends ConsumerStatefulWidget {
  final String serverId;

  const ServerConfigEditorScreen({super.key, required this.serverId});

  @override
  ConsumerState<ServerConfigEditorScreen> createState() =>
      _ServerConfigEditorScreenState();
}

class _ServerConfigEditorScreenState
    extends ConsumerState<ServerConfigEditorScreen> {
  ServerItem? _server;
  String _protocol = 'unknown';

  // uri-протоколы (vless/trojan/ss/hysteria*)
  RawShareUri? _uri;
  // vmess: payload целиком, незнакомые ключи сохраняются
  Map<String, dynamic>? _vmess;
  bool _vmessPortWasInt = false;
  String _vmessSecurityKey = 'scy';

  // ss: исходная форма userInfo (base64 sip002 или plain method:password)
  bool _ssBase64 = false;
  // hysteria: где лежал auth в исходной ссылке
  bool _hyAuthInQuery = false;

  final Map<String, TextEditingController> _text = {};
  final Map<String, String> _drop = {};
  final Map<String, bool> _toggle = {};

  bool _rawMode = false;
  bool _rawOnly = false; // awg/ssr/unknown — только сырой текст
  late final TextEditingController _rawCtrl = TextEditingController();

  String? _error;
  bool _saving = false;
  // снапшот для dirty-проверки: без правок сохранение не пересобирает ссылку
  // (пересборка могла бы поменять percent-encoding и зря взвести override)
  late String _initialSnapshot;

  @override
  void initState() {
    super.initState();
    final server = ref.read(serversProvider).byId[widget.serverId];
    _server = server;
    if (server != null) {
      final parseError = _initFromConfig(server.config);
      if (parseError != null) {
        // непарсибельный конфиг — редактируем как текст
        _rawOnly = true;
        _rawMode = true;
        _rawCtrl.text = server.config;
      }
    }
    _initialSnapshot = _snapshot();
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    _rawCtrl.dispose();
    super.dispose();
  }

  TextEditingController _ctrl(String id, [String initial = '']) =>
      _text.putIfAbsent(id, () => TextEditingController(text: initial));

  /// Разбирает конфиг в поля формы. null — успех, иначе причина фолбэка в raw.
  String? _initFromConfig(String rawConfig) {
    final config = rawConfig.trim();
    final lower = config.toLowerCase();

    String protocol = 'unknown';
    if (lower.startsWith('vless://')) {
      protocol = 'vless';
    } else if (lower.startsWith('vmess://')) {
      protocol = 'vmess';
    } else if (lower.startsWith('trojan://')) {
      protocol = 'trojan';
    } else if (lower.startsWith('ss://')) {
      protocol = 'ss';
    } else if (lower.startsWith('hysteria2://') ||
        lower.startsWith('hy2://') ||
        lower.startsWith('hysteria://')) {
      protocol = 'hysteria';
    }

    if (protocol == 'unknown') return 'raw-only protocol';

    if (protocol == 'vmess') {
      return _initVmess(config);
    }

    final uri = RawShareUri.parse(config);
    if (uri == null) return 'unparsable uri';

    _protocol = protocol;
    _uri = uri;
    _ctrl('address', uri.host);
    _ctrl('port', uri.port);

    switch (protocol) {
      case 'vless':
        _ctrl('userInfo', uri.userInfo);
        _ctrl('encryption', uri.takeParam('encryption'));
        _drop['flow'] = uri.takeParam('flow');
        final security = uri.takeParam('security');
        _drop['security'] = security.isEmpty ? 'none' : security;
        break;
      case 'trojan':
        _ctrl('userInfo', uri.userInfo);
        break;
      case 'ss':
        final userInfo = uri.userInfo;
        if (userInfo.isEmpty) return 'ss without userinfo';
        if (userInfo.contains(':')) {
          _ssBase64 = false;
          final idx = userInfo.indexOf(':');
          _ctrl('method', userInfo.substring(0, idx));
          _ctrl('password', userInfo.substring(idx + 1));
        } else {
          _ssBase64 = true;
          try {
            var normalized =
                userInfo.replaceAll('-', '+').replaceAll('_', '/');
            while (normalized.length % 4 != 0) {
              normalized += '=';
            }
            final decoded = utf8.decode(base64.decode(normalized));
            final idx = decoded.indexOf(':');
            if (idx <= 0) return 'bad ss userinfo';
            _ctrl('method', decoded.substring(0, idx));
            _ctrl('password', decoded.substring(idx + 1));
          } catch (_) {
            return 'bad ss base64';
          }
        }
        break;
      case 'hysteria':
        var auth = uri.takeParam('auth');
        if (auth.isEmpty) auth = uri.takeParam('password');
        _hyAuthInQuery = auth.isNotEmpty;
        if (auth.isEmpty && uri.userInfo.isNotEmpty) {
          try {
            auth = Uri.decodeComponent(uri.userInfo);
          } catch (_) {
            auth = uri.userInfo;
          }
        }
        _ctrl('auth', auth);
        break;
    }

    if (protocol == 'vless' || protocol == 'trojan') {
      // общие TLS-поля
      _ctrl('sni', uri.takeParam('sni'));
      _drop['fp'] = uri.takeParam('fp');
      _ctrl('alpn', uri.takeParam('alpn'));
      _ctrl('ech', uri.takeParam('ech'));
      _toggle['insecure'] = _takeInsecure(uri);
      // reality
      if (protocol == 'vless') {
        _ctrl('pbk', uri.takeParam('pbk'));
        _ctrl('sid', uri.takeParam('sid'));
        _ctrl('spx', uri.takeParam('spx'));
      }
      // транспорт
      final type = uri.takeParam('type');
      _drop['type'] = type.isEmpty ? 'tcp' : type;
      _ctrl('path', uri.takeParam('path'));
      _ctrl('host', uri.takeParam('host'));
      _ctrl('serviceName', uri.takeParam('serviceName'));
      _ctrl('mode', uri.takeParam('mode'));
      _drop['headerType'] = uri.takeParam('headerType');
    }

    if (protocol == 'hysteria') {
      _ctrl('sni', uri.takeParam('sni'));
      _drop['fp'] = uri.takeParam('fp');
      _ctrl('alpn', uri.takeParam('alpn'));
      _ctrl('ech', uri.takeParam('ech'));
      _toggle['insecure'] = _takeInsecure(uri);
      _drop['obfs'] = uri.takeParam('obfs');
      _ctrl('obfs-password', uri.takeParam('obfs-password'));
      _ctrl('up', uri.takeParam('up'));
      _ctrl('down', uri.takeParam('down'));
      _ctrl('mport', uri.takeParam('mport'));
      _ctrl('hop-interval', uri.takeParam('hop-interval'));
      _ctrl('pinSHA256', uri.takeParam('pinSHA256'));
    }

    return null;
  }

  bool _takeInsecure(RawShareUri uri) {
    var on = false;
    for (final key in ['insecure', 'allowInsecure', 'skip-cert-verify']) {
      final v = uri.takeParam(key).toLowerCase();
      if (v == '1' || v == 'true' || v == 'yes') on = true;
    }
    return on;
  }

  String? _initVmess(String config) {
    try {
      var payload = config.substring('vmess://'.length).trim();
      payload = payload.replaceAll(RegExp(r'\s+'), '')
          .replaceAll('-', '+')
          .replaceAll('_', '/');
      while (payload.length % 4 != 0) {
        payload += '=';
      }
      final decoded = utf8.decode(base64.decode(payload));
      final json = jsonDecode(decoded);
      if (json is! Map<String, dynamic>) return 'vmess payload is not a map';
      _protocol = 'vmess';
      _vmess = json;
      _vmessPortWasInt = json['port'] is int;
      _vmessSecurityKey = json.containsKey('security') ? 'security' : 'scy';

      String s(String key) => (json[key] ?? '').toString();
      _ctrl('address', s('add'));
      _ctrl('port', s('port'));
      _ctrl('userInfo', s('id'));
      _drop['scy'] = (json[_vmessSecurityKey] ?? '').toString();
      _drop['type'] = s('net').isEmpty ? 'tcp' : s('net');
      _drop['security'] = s('tls') == 'tls' ? 'tls' : 'none';
      _ctrl('sni', s('sni'));
      _ctrl('host', s('host'));
      _ctrl('path', s('path'));
      _ctrl('serviceName', s('serviceName'));
      _drop['fp'] = s('fp');
      _ctrl('alpn', s('alpn'));
      _ctrl('ech', s('ech'));
      var insecure = false;
      for (final k in ['insecure', 'allowInsecure', 'skip-cert-verify']) {
        final v = s(k).trim().toLowerCase();
        if (v == '1' || v == 'true' || v == 'yes') insecure = true;
      }
      _toggle['insecure'] = insecure;
      return null;
    } catch (_) {
      return 'bad vmess payload';
    }
  }

  // ---------- сборка конфига обратно ----------

  String _buildConfig() {
    if (_rawMode) return _rawCtrl.text.trim();
    if (_protocol == 'vmess') return _buildVmess();
    return _buildUri();
  }

  String _v(String id) => _text[id]?.text.trim() ?? '';

  String _buildUri() {
    final uri = _uri!;
    uri.host = _v('address');
    uri.port = _v('port');

    final managed = <MapEntry<String, String>>[];
    void add(String key, String value) =>
        managed.add(MapEntry(key, value.trim()));

    switch (_protocol) {
      case 'vless':
        uri.userInfo = _v('userInfo');
        add('encryption', _v('encryption'));
        add('flow', _drop['flow'] ?? '');
        final security = _drop['security'] ?? 'none';
        add('security', security == 'none' ? 'none' : security);
        if (security == 'tls' || security == 'reality') {
          add('sni', _v('sni'));
          add('fp', _drop['fp'] ?? '');
        }
        if (security == 'tls') {
          add('alpn', _v('alpn'));
          add('ech', _v('ech'));
          if (_toggle['insecure'] ?? false) add('insecure', '1');
        }
        if (security == 'reality') {
          add('pbk', _v('pbk'));
          add('sid', _v('sid'));
          add('spx', _v('spx'));
        }
        _addTransportParams(add);
        break;
      case 'trojan':
        uri.userInfo = _v('userInfo');
        add('sni', _v('sni'));
        add('fp', _drop['fp'] ?? '');
        add('alpn', _v('alpn'));
        add('ech', _v('ech'));
        if (_toggle['insecure'] ?? false) add('insecure', '1');
        _addTransportParams(add);
        break;
      case 'ss':
        final method = _v('method');
        final password = _v('password');
        if (_ssBase64) {
          uri.userInfo = base64Url
              .encode(utf8.encode('$method:$password'))
              .replaceAll('=', '');
        } else {
          uri.userInfo = '$method:$password';
        }
        break;
      case 'hysteria':
        final auth = _v('auth');
        if (_hyAuthInQuery) {
          add('auth', auth);
          uri.userInfo = '';
        } else {
          uri.userInfo = Uri.encodeComponent(auth);
        }
        add('sni', _v('sni'));
        add('fp', _drop['fp'] ?? '');
        add('alpn', _v('alpn'));
        add('ech', _v('ech'));
        if (_toggle['insecure'] ?? false) add('insecure', '1');
        add('obfs', _drop['obfs'] ?? '');
        if ((_drop['obfs'] ?? '').isNotEmpty) {
          add('obfs-password', _v('obfs-password'));
        }
        add('up', _v('up'));
        add('down', _v('down'));
        add('mport', _v('mport'));
        if (_v('mport').isNotEmpty) {
          add('hop-interval', _v('hop-interval'));
        }
        add('pinSHA256', _v('pinSHA256'));
        break;
    }

    return uri.build(managedParams: managed);
  }

  void _addTransportParams(void Function(String, String) add) {
    final type = _drop['type'] ?? 'tcp';
    add('type', type);
    switch (type) {
      case 'ws':
      case 'httpupgrade':
        add('path', _v('path'));
        add('host', _v('host'));
      case 'xhttp':
      case 'splithttp':
        add('path', _v('path'));
        add('host', _v('host'));
        add('mode', _v('mode'));
      case 'grpc':
        add('serviceName', _v('serviceName'));
        add('mode', _v('mode'));
      case 'tcp':
        final headerType = _drop['headerType'] ?? '';
        add('headerType', headerType);
        if (headerType == 'http') add('host', _v('host'));
    }
  }

  String _buildVmess() {
    final payload = Map<String, dynamic>.from(_vmess!);

    void put(String key, String value) {
      if (value.isEmpty) {
        payload.remove(key);
      } else {
        payload[key] = value;
      }
    }

    payload['add'] = _v('address');
    payload['port'] = _vmessPortWasInt
        ? (int.tryParse(_v('port')) ?? _v('port'))
        : _v('port');
    payload['id'] = _v('userInfo');
    put(_vmessSecurityKey, _drop['scy'] ?? '');
    final net = _drop['type'] ?? 'tcp';
    payload['net'] = net;
    final tls = _drop['security'] == 'tls';
    put('tls', tls ? 'tls' : '');
    put('sni', _v('sni'));
    put('host', _v('host'));
    put('path', _v('path'));
    put('serviceName', _v('serviceName'));
    put('fp', _drop['fp'] ?? '');
    put('alpn', _v('alpn'));
    put('ech', _v('ech'));
    payload.remove('allowInsecure');
    payload.remove('skip-cert-verify');
    if (_toggle['insecure'] ?? false) {
      payload['insecure'] = '1';
    } else {
      payload.remove('insecure');
    }

    final json = jsonEncode(payload);
    return 'vmess://${base64.encode(utf8.encode(json))}';
  }

  // ---------- dirty / save ----------

  String _snapshot() {
    if (_rawMode) return 'raw:${_rawCtrl.text}';
    final sb = StringBuffer();
    final textKeys = _text.keys.toList()..sort();
    for (final k in textKeys) {
      sb.write('$k=${_text[k]!.text}|');
    }
    final dropKeys = _drop.keys.toList()..sort();
    for (final k in dropKeys) {
      sb.write('$k=${_drop[k]}|');
    }
    final togKeys = _toggle.keys.toList()..sort();
    for (final k in togKeys) {
      sb.write('$k=${_toggle[k]}|');
    }
    return sb.toString();
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    final server = _server;
    if (server == null) return;

    if (_snapshot() == _initialSnapshot) {
      // ничего не менялось — не пересобираем ссылку (и не взводим override)
      Navigator.of(context).pop();
      return;
    }

    if (!_rawMode) {
      final port = int.tryParse(_v('port'));
      if (port == null || port <= 0 || port > 65535) {
        setState(() => _error = l10n.serverEditorInvalidPort);
        return;
      }
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final config = _buildConfig();
      await ref
          .read(serversProvider.notifier)
          .updateConfig(widget.serverId, config);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = friendlyError(e, context);
      });
      return;
    }

    if (!mounted) return;

    // сервер активен и туннель поднят — применяем правку переподключением
    final isActive =
        ref.read(serversProvider).activeServerId == widget.serverId;
    final status = ref.read(vpnStateProvider).value?.status;
    final reconnect = isActive &&
        (status == VpnStatus.connected || status == VpnStatus.connecting);
    if (reconnect) {
      unawaited(
        ref
            .read(vpnStateProvider.notifier)
            .reconnectToActiveServer()
            .catchError((_) {}),
      );
    }

    final messenger = ScaffoldMessenger.of(context);
    final msg =
        reconnect ? l10n.serverEditorReconnecting : l10n.serverEditorSaved;
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _toggleRawMode() {
    if (_rawOnly) return;
    // если правок ещё не было, «чистота» переезжает через переключение
    // режима: baseline пересчитывается, и no-op сохранение остаётся no-op
    final wasClean = _snapshot() == _initialSnapshot;
    setState(() {
      if (_rawMode) {
        // назад в форму: перечитываем поля из текста
        final err = _reparse(_rawCtrl.text.trim());
        if (err != null) {
          _error = err;
          return;
        }
        _error = null;
        _rawMode = false;
      } else {
        String built;
        try {
          built = _buildConfig();
        } catch (_) {
          built = _server?.config ?? '';
        }
        // без правок показываем исходную ссылку как есть, а не пересборку
        // (пересборка может слегка поменять percent-encoding)
        _rawCtrl.text = wasClean ? (_server?.config ?? built) : built;
        _rawMode = true;
      }
      if (wasClean) _initialSnapshot = _snapshot();
    });
  }

  /// Полный ре-парс конфига (после ручной правки текста): чистит состояние
  /// формы и заполняет заново. null — успех.
  String? _reparse(String config) {
    final l10n = AppLocalizations.of(context)!;
    final validation = ServersNotifier.validateServerConfig(config);
    if (validation != null) return validation;

    for (final c in _text.values) {
      c.dispose();
    }
    _text.clear();
    _drop.clear();
    _toggle.clear();
    _uri = null;
    _vmess = null;
    final err = _initFromConfig(config);
    if (err != null) {
      // текст валиден для добавления, но форма его не понимает (awg и т.п.)
      _rawOnly = true;
      _rawMode = true;
      return l10n.serverEditorRawOnlyNote;
    }
    return null;
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final server = _server;

    if (server == null) {
      return Scaffold(
        backgroundColor: AppTheme.bg(context),
        appBar: AppBar(
          backgroundColor: AppTheme.bg(context),
          elevation: 0,
          iconTheme: IconThemeData(color: AppTheme.text(context)),
        ),
        body: Center(
          child: Text(
            l10n.serverEditorServerMissing,
            style: TextStyle(color: AppTheme.textLight(context)),
          ),
        ),
      );
    }

    final name = ServerNameUtils.formatForDisplay(
      ServerNameUtils.cleanDisplayName(server.displayName),
    );

    Widget body = SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (server.type == ServerItemType.subscription)
            _subscriptionBanner(server, l10n),
          if (_error != null) _errorBanner(),
          if (_rawMode)
            _rawSection(l10n)
          else ...[
            ..._formSections(l10n),
            _previewSection(l10n),
          ],
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentContainer(context),
                foregroundColor: AppTheme.onAccentContainer(context),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.onAccentContainer(context),
                      ),
                    )
                  : Text(
                      l10n.subscriptionsSave,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );

    body = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: body,
      ),
    );

    return Scaffold(
      backgroundColor: AppTheme.bg(context),
      appBar: AppBar(
        backgroundColor: AppTheme.bg(context),
        elevation: 0,
        iconTheme: IconThemeData(color: AppTheme.text(context)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.serverEditorTitle,
              style: TextStyle(
                color: AppTheme.text(context),
                fontWeight: FontWeight.w700,
                fontSize: 17,
              ),
            ),
            Text(
              '${server.protocol.toUpperCase()} · $name',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppTheme.textLight(context),
                fontSize: 11,
              ),
            ),
          ],
        ),
        actions: [
          if (!_rawOnly)
            IconButton(
              tooltip: l10n.serverEditorRawToggle,
              icon: Icon(
                _rawMode ? Icons.tune : Icons.code,
                color:
                    _rawMode ? AppTheme.accent(context) : AppTheme.text(context),
              ),
              onPressed: _toggleRawMode,
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: body,
    );
  }

  Widget _subscriptionBanner(ServerItem server, AppLocalizations l10n) {
    final overridden = server.configOverridden;
    final color =
        overridden ? AppTheme.orange(context) : AppTheme.accent(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                overridden ? Icons.edit_note : Icons.info_outline,
                size: 18,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  overridden
                      ? l10n.serverEditorOverriddenNote
                      : l10n.serverEditorSubscriptionNote,
                  style: TextStyle(fontSize: 12, color: AppTheme.text(context)),
                ),
              ),
            ],
          ),
          if (overridden)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () {
                  final srv = _server!;
                  Navigator.of(context).pop();
                  unawaited(
                    ref
                        .read(serversProvider.notifier)
                        .revertConfigOverride(srv)
                        .catchError((_) {}),
                  );
                },
                icon: Icon(Icons.restore, size: 16, color: color),
                label: Text(
                  l10n.serverEditorRevert,
                  style: TextStyle(fontSize: 12, color: color),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _errorBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.red(context).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        _error!,
        style: TextStyle(fontSize: 12, color: AppTheme.red(context)),
      ),
    );
  }

  Widget _rawSection(AppLocalizations l10n) {
    return _section(
      l10n.serverEditorRawConfig,
      [
        TextField(
          controller: _rawCtrl,
          maxLines: 10,
          minLines: 4,
          style: TextStyle(
            color: AppTheme.text(context),
            fontSize: 12,
            fontFamily: 'monospace',
          ),
          onChanged: (_) => setState(() {}),
          decoration: _inputDecoration(),
        ),
      ],
    );
  }

  List<Widget> _formSections(AppLocalizations l10n) {
    switch (_protocol) {
      case 'vless':
        return [
          _generalSection(l10n, credLabel: 'UUID'),
          _vlessSecuritySection(l10n),
          _transportSection(l10n),
        ];
      case 'trojan':
        return [
          _generalSection(l10n, credLabel: l10n.serverEditorPassword),
          _tlsSection(l10n),
          _transportSection(l10n),
        ];
      case 'vmess':
        return [
          _generalSection(l10n, credLabel: 'UUID'),
          _vmessSecuritySection(l10n),
          _vmessTransportSection(l10n),
        ];
      case 'ss':
        return [_ssSection(l10n)];
      case 'hysteria':
        return [
          _hysteriaGeneralSection(l10n),
          _hysteriaTlsSection(l10n),
          _hysteriaExtrasSection(l10n),
        ];
      default:
        return [];
    }
  }

  Widget _generalSection(AppLocalizations l10n, {required String credLabel}) {
    return _section(
      l10n.serverEditorSectionGeneral,
      [
        _addressPortRow(l10n),
        _textField('userInfo', credLabel, obscurable: true),
        if (_protocol == 'vless')
          _textField(
            'encryption',
            l10n.serverEditorEncryption,
            hint: 'none',
          ),
        if (_protocol == 'vless')
          _dropdown(
            'flow',
            'Flow',
            const ['', 'xtls-rprx-vision', 'xtls-rprx-vision-udp443'],
          ),
      ],
    );
  }

  Widget _vlessSecuritySection(AppLocalizations l10n) {
    final security = _drop['security'] ?? 'none';
    return _section(
      l10n.serverEditorSectionSecurity,
      [
        _dropdown(
          'security',
          l10n.serverEditorSecurityMode,
          const ['none', 'tls', 'reality'],
        ),
        if (security == 'tls' || security == 'reality') ...[
          _textField('sni', 'SNI'),
          _fpDropdown(l10n),
        ],
        if (security == 'tls') ...[
          _textField('alpn', l10n.serverEditorAlpn, hint: 'h2,http/1.1'),
          _textField('ech', 'ECH'),
          _insecureToggle(l10n),
        ],
        if (security == 'reality') ...[
          _textField('pbk', l10n.serverEditorPbk),
          _textField('sid', l10n.serverEditorSid),
          _textField('spx', l10n.serverEditorSpx, hint: '/'),
        ],
      ],
    );
  }

  Widget _tlsSection(AppLocalizations l10n) {
    return _section(
      l10n.serverEditorSectionSecurity,
      [
        _textField('sni', 'SNI'),
        _fpDropdown(l10n),
        _textField('alpn', l10n.serverEditorAlpn, hint: 'h2,http/1.1'),
        _textField('ech', 'ECH'),
        _insecureToggle(l10n),
      ],
    );
  }

  Widget _transportSection(AppLocalizations l10n) {
    final type = _drop['type'] ?? 'tcp';
    final options = _protocol == 'vless'
        ? ['tcp', 'ws', 'grpc', 'xhttp', 'httpupgrade']
        : ['tcp', 'ws', 'grpc'];
    return _section(
      l10n.serverEditorSectionTransport,
      [
        _dropdown('type', l10n.serverEditorTransportType, options),
        if (type == 'ws' ||
            type == 'httpupgrade' ||
            type == 'xhttp' ||
            type == 'splithttp') ...[
          _textField('path', l10n.serverEditorPath, hint: '/'),
          _textField('host', 'Host'),
        ],
        if (type == 'xhttp' || type == 'splithttp')
          _textField('mode', l10n.serverEditorMode, hint: 'auto'),
        if (type == 'grpc') ...[
          _textField('serviceName', l10n.serverEditorServiceName),
          _textField('mode', l10n.serverEditorMode, hint: 'multi'),
        ],
        if (type == 'tcp') ...[
          _dropdown('headerType', l10n.serverEditorHeaderType, const ['', 'http']),
          if ((_drop['headerType'] ?? '') == 'http')
            _textField('host', 'Host'),
        ],
      ],
    );
  }

  Widget _vmessSecuritySection(AppLocalizations l10n) {
    final tls = (_drop['security'] ?? 'none') == 'tls';
    return _section(
      l10n.serverEditorSectionSecurity,
      [
        _dropdown(
          'scy',
          l10n.serverEditorMethod,
          const ['', 'auto', 'none', 'zero', 'aes-128-gcm', 'chacha20-poly1305'],
        ),
        _dropdown('security', l10n.serverEditorSecurityMode, const ['none', 'tls']),
        if (tls) ...[
          _textField('sni', 'SNI'),
          _fpDropdown(l10n),
          _textField('alpn', l10n.serverEditorAlpn, hint: 'h2,http/1.1'),
          _textField('ech', 'ECH'),
          _insecureToggle(l10n),
        ],
      ],
    );
  }

  Widget _vmessTransportSection(AppLocalizations l10n) {
    final type = _drop['type'] ?? 'tcp';
    return _section(
      l10n.serverEditorSectionTransport,
      [
        _dropdown('type', l10n.serverEditorTransportType, const ['tcp', 'ws', 'grpc']),
        if (type == 'ws') ...[
          _textField('path', l10n.serverEditorPath, hint: '/'),
          _textField('host', 'Host'),
        ],
        if (type == 'grpc')
          _textField('serviceName', l10n.serverEditorServiceName),
      ],
    );
  }

  Widget _ssSection(AppLocalizations l10n) {
    return _section(
      l10n.serverEditorSectionGeneral,
      [
        _addressPortRow(l10n),
        _dropdown(
          'ss-method-unused',
          l10n.serverEditorMethod,
          const [],
          textFallbackId: 'method',
        ),
        _textField('password', l10n.serverEditorPassword, obscurable: true),
      ],
    );
  }

  Widget _hysteriaGeneralSection(AppLocalizations l10n) {
    return _section(
      l10n.serverEditorSectionGeneral,
      [
        _addressPortRow(l10n),
        _textField('auth', l10n.serverEditorAuth, obscurable: true),
      ],
    );
  }

  Widget _hysteriaTlsSection(AppLocalizations l10n) {
    return _section(
      l10n.serverEditorSectionSecurity,
      [
        _textField('sni', 'SNI'),
        _fpDropdown(l10n),
        _textField('alpn', l10n.serverEditorAlpn, hint: 'h3'),
        _textField('ech', 'ECH'),
        _textField('pinSHA256', l10n.serverEditorPinSha256),
        _insecureToggle(l10n),
      ],
    );
  }

  Widget _hysteriaExtrasSection(AppLocalizations l10n) {
    final obfs = _drop['obfs'] ?? '';
    return _section(
      l10n.serverEditorSectionProtocol,
      [
        _dropdown('obfs', l10n.serverEditorObfs, const ['', 'salamander']),
        if (obfs.isNotEmpty)
          _textField(
            'obfs-password',
            l10n.serverEditorObfsPassword,
            obscurable: true,
          ),
        Row(
          children: [
            Expanded(child: _textField('up', l10n.serverEditorUp, hint: '50')),
            const SizedBox(width: 10),
            Expanded(
              child: _textField('down', l10n.serverEditorDown, hint: '200'),
            ),
          ],
        ),
        _textField('mport', l10n.serverEditorMport, hint: '20000-30000'),
        if (_v('mport').isNotEmpty)
          _textField('hop-interval', l10n.serverEditorHopInterval, hint: '30'),
      ],
    );
  }

  Widget _addressPortRow(AppLocalizations l10n) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 3, child: _textField('address', l10n.serverEditorAddress)),
        const SizedBox(width: 10),
        Expanded(
          flex: 1,
          child: _textField(
            'port',
            l10n.serverEditorPort,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
        ),
      ],
    );
  }

  Widget _fpDropdown(AppLocalizations l10n) {
    return _dropdown(
      'fp',
      l10n.serverEditorFingerprint,
      const [
        '',
        'chrome',
        'firefox',
        'safari',
        'ios',
        'android',
        'edge',
        '360',
        'qq',
        'random',
        'randomized',
      ],
    );
  }

  Widget _insecureToggle(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: SwitchListTile(
        value: _toggle['insecure'] ?? false,
        dense: true,
        contentPadding: EdgeInsets.zero,
        activeThumbColor: AppTheme.accent(context),
        activeTrackColor: AppTheme.accent(context).withValues(alpha: 0.32),
        title: Text(
          l10n.serverEditorAllowInsecure,
          style: TextStyle(fontSize: 13, color: AppTheme.text(context)),
        ),
        onChanged: (v) => setState(() => _toggle['insecure'] = v),
      ),
    );
  }

  Widget _previewSection(AppLocalizations l10n) {
    String preview;
    try {
      preview = _buildConfig();
    } catch (_) {
      preview = '';
    }
    return _section(
      l10n.serverEditorPreview,
      [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SelectableText(
                preview,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: AppTheme.textLight(context),
                ),
              ),
            ),
            IconButton(
              tooltip: l10n.serversCopyConfig,
              icon: Icon(Icons.copy, size: 16, color: AppTheme.textLight(context)),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: preview));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n.serversConfigCopied),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  // ---------- строительные блоки ----------

  Widget _section(String title, List<Widget> children) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: AppTheme.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: AppTheme.textLight(context),
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  InputDecoration _inputDecoration({String? label, String? hint}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: TextStyle(fontSize: 12, color: AppTheme.textLight(context)),
      hintStyle: TextStyle(
        fontSize: 12,
        color: AppTheme.textLight(context).withValues(alpha: 0.4),
      ),
      isDense: true,
      filled: true,
      fillColor: AppTheme.bg(context),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppTheme.divider(context)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppTheme.divider(context)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppTheme.accent(context), width: 2),
      ),
    );
  }

  Widget _textField(
    String id,
    String label, {
    String? hint,
    bool obscurable = false,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: _ctrl(id),
        style: TextStyle(
          color: AppTheme.text(context),
          fontSize: 13,
          fontFamily: obscurable ? 'monospace' : null,
        ),
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        onChanged: (_) => setState(() {}),
        decoration: _inputDecoration(label: label, hint: hint),
      ),
    );
  }

  /// Дропдаун по [id] из `_drop`; если текущее значение не из [options],
  /// оно добавляется в список (незнакомые значения не теряем).
  /// [textFallbackId] — «дропдаун поверх текстового поля»: значения читаются
  /// и пишутся в текстовый контроллер (метод шифрования ss).
  Widget _dropdown(
    String id,
    String label,
    List<String> options, {
    String? textFallbackId,
  }) {
    final isText = textFallbackId != null;
    final current = isText ? _v(textFallbackId) : (_drop[id] ?? '');

    var opts = options;
    if (isText) {
      opts = const [
        'aes-256-gcm',
        'aes-128-gcm',
        'chacha20-ietf-poly1305',
        'xchacha20-ietf-poly1305',
        '2022-blake3-aes-128-gcm',
        '2022-blake3-aes-256-gcm',
        '2022-blake3-chacha20-poly1305',
        'none',
      ];
    }
    if (!opts.contains(current)) {
      opts = [current, ...opts];
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        // key от значения: после ре-парса из raw-режима FormField пересоздаётся
        // и подхватывает новое значение (initialValue сам по себе не обновляется)
        key: ValueKey('dd-$id-$current'),
        initialValue: current,
        isExpanded: true,
        dropdownColor: AppTheme.card(context),
        style: TextStyle(color: AppTheme.text(context), fontSize: 13),
        icon: Icon(
          Icons.expand_more,
          size: 18,
          color: AppTheme.textLight(context),
        ),
        decoration: _inputDecoration(label: label),
        items: [
          for (final o in opts)
            DropdownMenuItem(
              value: o,
              child: Text(
                o.isEmpty ? '—' : o,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (v) {
          if (v == null) return;
          setState(() {
            if (isText) {
              _ctrl(textFallbackId).text = v;
            } else {
              _drop[id] = v;
            }
          });
        },
      ),
    );
  }
}
