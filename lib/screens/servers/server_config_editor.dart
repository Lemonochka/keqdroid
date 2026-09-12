import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:keqdroid/l10n/app_localizations.dart';
import 'package:keqdroid/shared/ui/app_theme.dart';
import 'package:keqdroid/shared/ui/expressive.dart';
import 'package:keqdroid/shared/ui/expressive_button_group.dart';
import 'package:keqdroid/shared/ui/expressive_elements.dart';
import 'package:keqdroid/shared/ui/expressive_group.dart';
import 'package:keqdroid/shared/ui/shape_loading_indicator.dart';
import 'package:keqdroid/shared/ui/scrolled_under.dart';

import '../../models/server_item.dart';
import '../../models/server_name_utils.dart';
import '../../providers/providers.dart';
import '../../services/vpn_engine.dart';
import '../../utils/custom_xray_config.dart';
import '../../utils/error_messages.dart';
import '../../utils/raw_share_uri.dart';
import '../../utils/server_field_rules.dart';

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
        // У trojan TLS подразумевается самим протоколом, и ссылки сплошь не
        // пишут `security` — пустое значение означает здесь именно tls, а не
        // «без защиты» (так же считает и генератор конфига).
        final trojanSecurity = uri.takeParam('security');
        _drop['security'] =
            trojanSecurity.isEmpty ? 'tls' : trojanSecurity;
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
      // Проверки сертификата сверх обычной: закреплённый отпечаток и имя,
      // по которому его сверять. Оба уезжают в tlsSettings генератором.
      _ctrl('pcs', uri.takeParam('pcs'));
      _ctrl('vcn', uri.takeParam('vcn'));
      // reality: у trojan он тоже бывает, ветка разбора общая
      _ctrl('pbk', uri.takeParam('pbk'));
      _ctrl('sid', uri.takeParam('sid'));
      _ctrl('spx', uri.takeParam('spx'));
      _ctrl('pqv', uri.takeParam('pqv'));
      // транспорт
      final type = uri.takeParam('type');
      _drop['type'] = type.isEmpty ? 'tcp' : type;
      _ctrl('path', uri.takeParam('path'));
      _ctrl('host', uri.takeParam('host'));
      _ctrl('serviceName', uri.takeParam('serviceName'));
      _drop['mode'] = uri.takeParam('mode');
      _ctrl('authority', uri.takeParam('authority'));
      _ctrl('ed', uri.takeParam('ed'));
      _ctrl('extra', uri.takeParam('extra'));
      _ctrl('x_padding_bytes', uri.takeParam('x_padding_bytes'));
      _ctrl('seed', uri.takeParam('seed'));
      _ctrl('mtu', uri.takeParam('mtu'));
      _ctrl('tti', uri.takeParam('tti'));
      _ctrl('method', uri.takeParam('method'));
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
        if (security == 'tls' || security == 'reality') {
          add('pcs', _v('pcs'));
          add('vcn', _v('vcn'));
        }
        if (security == 'reality') {
          add('pbk', _v('pbk'));
          add('sid', _v('sid'));
          add('spx', _v('spx'));
          add('pqv', _v('pqv'));
        }
        _addTransportParams(add);
        break;
      case 'trojan':
        uri.userInfo = _v('userInfo');
        final trojanSecurity = _drop['security'] ?? 'tls';
        // `tls` не пишем: он у trojan и так по умолчанию, а лишний параметр в
        // ссылке — повод пометить сервер как изменённый на ровном месте.
        add('security', trojanSecurity == 'tls' ? '' : trojanSecurity);
        add('sni', _v('sni'));
        add('fp', _drop['fp'] ?? '');
        if (trojanSecurity == 'tls') {
          add('alpn', _v('alpn'));
          add('ech', _v('ech'));
          add('pcs', _v('pcs'));
          add('vcn', _v('vcn'));
          if (_toggle['insecure'] ?? false) add('insecure', '1');
        }
        if (trojanSecurity == 'reality') {
          add('pbk', _v('pbk'));
          add('sid', _v('sid'));
          add('spx', _v('spx'));
          add('pqv', _v('pqv'));
        }
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

  /// Параметры транспорта в ссылку.
  ///
  /// Пишутся только те, что относятся к выбранному транспорту. Остальные
  /// исчезают сами: при разборе их забрал `takeParam`, а обратно в ссылку
  /// уезжает только то, что здесь названо. Поэтому смена ws на grpc не тащит
  /// за собой путь и хост.
  void _addTransportParams(void Function(String, String) add) {
    final type = _drop['type'] ?? 'tcp';
    add('type', type);
    switch (normalizeTransport(type)) {
      case 'ws':
      case 'httpupgrade':
        add('path', _v('path'));
        add('host', _v('host'));
        add('ed', _v('ed'));
      case 'xhttp':
        add('path', _v('path'));
        add('host', _v('host'));
        add('mode', _drop['mode'] ?? '');
        add('extra', _v('extra'));
        add('x_padding_bytes', _v('x_padding_bytes'));
      case 'grpc':
        add('serviceName', _v('serviceName'));
        add('mode', _drop['mode'] ?? '');
        add('authority', _v('authority'));
      case 'kcp':
        add('headerType', _drop['headerType'] ?? '');
        add('seed', _v('seed'));
        add('mtu', _v('mtu'));
        add('tti', _v('tti'));
      case 'tcp':
        final headerType = _drop['headerType'] ?? '';
        add('headerType', headerType);
        if (headerType == 'http') {
          add('host', _v('host'));
          add('path', _v('path'));
          add('method', _v('method'));
        }
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ExpressiveShape.medium)),
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
        appBar: AppBar(),
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
          ?_issuesNotice(l10n),
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
                  borderRadius: BorderRadius.circular(ExpressiveShape.large),
                ),
                elevation: 0,
              ),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? ShapeLoadingIndicator(
                      size: 20,
                      color: AppTheme.onAccentContainer(context),
                    )
                  : Text(
                      l10n.subscriptionsSave,
                      style: Theme.of(context)
                          .textTheme
                          .emphasized(Theme.of(context).textTheme.labelLarge),
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
      appBar: ExpressiveScrolledUnderBar(
        builder: (context, background) => AppBar(
        backgroundColor: background,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.serverEditorTitle,
              style: Theme.of(context)
                  .textTheme
                  .emphasized(Theme.of(context).textTheme.titleMedium)
                  ?.copyWith(color: AppTheme.text(context)),
            ),
            Text(
              '${server.protocol.toUpperCase()} · $name',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppTheme.textLight(context)),
            ),
          ],
        ),
        actions: [
          if (!_rawOnly)
            IconButton(
              tooltip: l10n.serverEditorRawToggle,
              icon: Icon(
                _rawMode ? Icons.tune_rounded : Icons.code_rounded,
                color:
                    _rawMode ? AppTheme.accent(context) : AppTheme.text(context),
              ),
              onPressed: _toggleRawMode,
            ),
          const SizedBox(width: 4),
        ],
        ),
      ),
      body: body,
    );
  }

  /// Что в наборе полей не сойдётся у ядра.
  ///
  /// Плашка, а не запрет: правила описывают ядро, а ссылку мог выдать сервер,
  /// живущий по своим (тот же REALITY поверх ws умеет mihomo). Поэтому здесь
  /// сказано, что именно не так, а решение остаётся за человеком — молча
  /// переписывать чужую ссылку хуже, чем показать причину.
  Widget? _issuesNotice(AppLocalizations l10n) {
    if (_rawMode) return null;
    final issues = serverRuleIssues(
      protocol: _protocol,
      transport: _drop['type'] ?? 'tcp',
      security: _drop['security'] ?? (_protocol == 'trojan' ? 'tls' : 'none'),
      flow: _drop['flow'] ?? '',
      encryption: _v('encryption'),
      publicKey: _v('pbk'),
    );
    if (issues.isEmpty) return null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ExpressiveNotice(
        color: AppTheme.orange(context),
        icon: Icons.error_outline_rounded,
        text: [for (final issue in issues) _issueText(l10n, issue)].join('\n'),
      ),
    );
  }

  String _issueText(AppLocalizations l10n, ServerRuleIssue issue) =>
      switch (issue) {
        ServerRuleIssue.visionNeedsRawTls => l10n.serverEditorIssueVision,
        ServerRuleIssue.flowUnknown => l10n.serverEditorIssueFlow,
        ServerRuleIssue.realityNeedsOwnTransport =>
          l10n.serverEditorIssueRealityTransport,
        ServerRuleIssue.realityNeedsPublicKey =>
          l10n.serverEditorIssueRealityKey,
        ServerRuleIssue.encryptionMalformed =>
          l10n.serverEditorIssueEncryption,
        ServerRuleIssue.noSecurityAtAll => l10n.serverEditorIssueNoSecurity,
      };

  Widget _subscriptionBanner(ServerItem server, AppLocalizations l10n) {
    final overridden = server.configOverridden;
    final color =
        overridden ? AppTheme.orange(context) : AppTheme.accent(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(ExpressiveShape.medium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                overridden ? Icons.edit_note_rounded : Icons.info_outline_rounded,
                size: 18,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  overridden
                      ? l10n.serverEditorOverriddenNote
                      : l10n.serverEditorSubscriptionNote,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppTheme.text(context)),
                ),
              ),
            ],
          ),
          if (overridden)
            Align(
              alignment: AlignmentDirectional.centerEnd,
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
                icon: Icon(Icons.restore_rounded, size: 16, color: color),
                label: Text(
                  l10n.serverEditorRevert,
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: color),
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
        borderRadius: BorderRadius.circular(ExpressiveShape.medium),
      ),
      child: Text(
        _error!,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: AppTheme.red(context)),
      ),
    );
  }

  /// Приводит JSON к читаемому виду с отступами.
  ///
  /// Готовый конфиг почти всегда приходит одной строкой — из подписки или из
  /// буфера обмена, — и править его в таком виде невозможно.
  void _formatRawJson() {
    final text = _rawCtrl.text.trim();
    try {
      final decoded = jsonDecode(text);
      final pretty = const JsonEncoder.withIndent('  ').convert(decoded);
      setState(() {
        _rawCtrl.value = TextEditingValue(
          text: pretty,
          selection: TextSelection.collapsed(offset: pretty.length),
        );
      });
    } on Object {
      // Кнопка гаснет на невалидном JSON, но состояние могло смениться между
      // кадром и нажатием — молча ничего не делаем, а не роняем экран.
    }
  }

  Widget _rawSection(AppLocalizations l10n) {
    final raw = _rawCtrl.text;
    // Готовый конфиг Xray — это JSON в сотни строк, и окно на 10 строк без
    // проверки синтаксиса делало правку формальной возможностью, а не рабочей.
    final isJson = CustomXrayConfig.looksLikeJson(raw);
    final problem = isJson ? CustomXrayConfig.describeProblem(raw) : null;
    final green = AppTheme.green(context);
    final red = AppTheme.red(context);

    return _section(
      l10n.serverEditorRawConfig,
      [
        TextField(
          controller: _rawCtrl,
          // JSON редактируется во весь доступный экран, share-ссылка — нет:
          // ей хватает пары строк.
          maxLines: isJson ? 26 : 10,
          minLines: isJson ? 14 : 4,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.text(context),
                fontFamily: 'monospace',
              ),
          onChanged: (_) => setState(() {}),
          decoration: _inputDecoration(),
        ),
        if (isJson) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                problem == null ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
                size: 16,
                color: problem == null ? green : red,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  problem ?? l10n.serverEditorJsonValid,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: problem == null ? green : red,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              // Форматирование доступно, пока JSON вообще разбирается: чинить
              // отступы полезно и в конфиге, который ещё не полон.
              TextButton.icon(
                onPressed: _rawJsonParses(raw) ? _formatRawJson : null,
                icon: const Icon(Icons.format_align_left_rounded, size: 16),
                label: Text(l10n.serverEditorJsonFormat),
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  static bool _rawJsonParses(String raw) {
    try {
      jsonDecode(raw.trim());
      return true;
    } on Object {
      return false;
    }
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
          _transportSection(l10n),
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
        // Vision предлагается только в рабочем сочетании: на xhttp и ws ядро
        // отвечает «XTLS only supports TLS and REALITY directly», то есть
        // сервер просто не подключается. Уже выставленное чужое значение
        // список сохраняет (см. _dropdown) — чтобы его было видно и можно было
        // убрать.
        if (_protocol == 'vless')
          _dropdown(
            'flow',
            'Flow',
            flowOptionsFor(
              protocol: _protocol,
              transport: _drop['type'] ?? 'tcp',
              security: _drop['security'] ?? 'none',
              encryption: _v('encryption'),
            ),
          ),
      ],
    );
  }

  Widget _vlessSecuritySection(AppLocalizations l10n) => _section(
        l10n.serverEditorSectionSecurity,
        _securityFields(l10n, reality: true),
      );

  /// Поля защиты — одни и те же у vless, trojan и vmess.
  ///
  /// [reality] — предлагать ли REALITY. У vmess его нет в самой ссылке
  /// (json-формат сложился до него), у остальных он зависит ещё и от
  /// транспорта: ws, httpupgrade и mkcp его не несут.
  List<Widget> _securityFields(
    AppLocalizations l10n, {
    required bool reality,
  }) {
    final transport = _drop['type'] ?? 'tcp';
    final security = _drop['security'] ?? 'none';
    final allowed =
        reality ? securityOptionsFor(transport) : const ['none', 'tls'];
    final options = [
      ...allowed,
      // Чужое значение не теряем: ссылка могла прийти из клиента, который
      // умеет то, чего здесь нельзя выбрать.
      if (!allowed.contains(security)) security,
    ];
    return [
      _segmented(
        'security',
        l10n.serverEditorSecurityMode,
        [for (final o in options) (o, o == 'none' ? '—' : o.toUpperCase())],
      ),
      if (security == 'tls' || security == 'reality') ...[
        _textField('sni', 'SNI'),
        _fpDropdown(l10n),
      ],
      if (security == 'tls') ...[
        _textField('alpn', l10n.serverEditorAlpn, hint: 'h2,http/1.1'),
        _textField('ech', 'ECH'),
        _textField('pcs', l10n.serverEditorPinnedCert),
        _textField('vcn', l10n.serverEditorVerifyCertName),
        _insecureToggle(l10n),
      ],
      if (security == 'reality') ...[
        _textField('pbk', l10n.serverEditorPbk),
        _textField('sid', l10n.serverEditorSid),
        _textField('spx', l10n.serverEditorSpx, hint: '/'),
        _textField('pqv', l10n.serverEditorPqv),
      ],
    ];
  }

  /// Trojan. Раньше секция была «всегда TLS», хотя ядро берёт у него и
  /// REALITY (матрица «протокол × защита» в документации транспорта), и такие
  /// ссылки существуют.
  Widget _tlsSection(AppLocalizations l10n) => _section(
        l10n.serverEditorSectionSecurity,
        _securityFields(l10n, reality: true),
      );

  /// Транспорт и его параметры.
  ///
  /// Список одинаков у vless, vmess и trojan: ядро собирает их одним и тем же
  /// сборщиком (`_buildStreamSettings`). Раньше половина транспортов здесь не
  /// показывалась — сервер на httpupgrade или mkcp редактировать было нечем,
  /// хотя приложение их исполняет.
  Widget _transportSection(AppLocalizations l10n) {
    final type = normalizeTransport(_drop['type'] ?? 'tcp');
    return _section(
      l10n.serverEditorSectionTransport,
      [
        _dropdown('type', l10n.serverEditorTransportType, kServerTransports),
        if (type == 'ws' || type == 'httpupgrade') ...[
          _textField('path', l10n.serverEditorPath, hint: '/'),
          _textField('host', 'Host'),
          _textField(
            'ed',
            l10n.serverEditorEarlyData,
            hint: '2048',
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
        ],
        if (type == 'xhttp') ...[
          _textField('path', l10n.serverEditorPath, hint: '/'),
          _textField('host', 'Host'),
          _dropdown(
            'mode',
            l10n.serverEditorMode,
            const ['', 'auto', 'packet-up', 'stream-up', 'stream-one'],
          ),
          _textField(
            'x_padding_bytes',
            l10n.serverEditorPadding,
            hint: '100-1000',
          ),
          _textField('extra', l10n.serverEditorExtra, hint: '{ }'),
        ],
        if (type == 'grpc') ...[
          _textField('serviceName', l10n.serverEditorServiceName),
          _segmented('mode', l10n.serverEditorMode, const [
            ('', 'gun'),
            ('multi', 'multi'),
          ]),
          _textField('authority', l10n.serverEditorAuthority),
        ],
        if (type == 'kcp') ...[
          // Имена заголовков — те, что знает mkcp-legacy; с любым другим ядро
          // роняет конфиг целиком (config_gen._mkcpHeaders).
          _dropdown(
            'headerType',
            l10n.serverEditorHeaderType,
            const [
              '',
              'none',
              'srtp',
              'utp',
              'wechat-video',
              'dtls',
              'wireguard',
              'dns',
            ],
          ),
          _textField('seed', l10n.serverEditorSeed),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _textField(
                  'mtu',
                  'MTU',
                  hint: '1350',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _textField(
                  'tti',
                  'TTI',
                  hint: '50',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
              ),
            ],
          ),
        ],
        if (type == 'tcp') ...[
          _segmented('headerType', l10n.serverEditorHeaderType, const [
            ('', '—'),
            ('http', 'http'),
          ]),
          if ((_drop['headerType'] ?? '') == 'http') ...[
            _textField('host', 'Host'),
            _textField('path', l10n.serverEditorPath, hint: '/'),
            _textField('method', l10n.serverEditorHttpMethod, hint: 'GET'),
          ],
        ],
      ],
    );
  }

  Widget _vmessSecuritySection(AppLocalizations l10n) => _section(
        l10n.serverEditorSectionSecurity,
        [
          _dropdown(
            'scy',
            l10n.serverEditorMethod,
            const [
              '',
              'auto',
              'none',
              'zero',
              'aes-128-gcm',
              'chacha20-poly1305',
            ],
          ),
          // REALITY в vmess-ссылке передать нечем: у json-формата нет для него
          // полей, и ядро получило бы вместо него обычный TLS.
          ..._securityFields(l10n, reality: false),
        ],
      );

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
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AppTheme.text(context)),
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
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: AppTheme.textLight(context),
                    ),
              ),
            ),
            IconButton(
              tooltip: l10n.serversCopyConfig,
              icon: Icon(Icons.copy_rounded, size: 16, color: AppTheme.textLight(context)),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: preview));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n.serversConfigCopied),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(ExpressiveShape.medium),
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

  /// Секция: заголовок над карточкой, как на остальных экранах настроек.
  ///
  /// Раньше это была своя карточка с рамкой и серой подписью внутри — вид из
  /// доэкспрессивных времён, единственный такой в приложении. Карточка теперь
  /// общая ([ExpressiveCard]) и заголовок общий ([ExpressiveSectionHeader]),
  /// поэтому редактор больше не выпадает из остального интерфейса.
  ///
  /// [ExpressiveCard] внутри — `Material`, и это важно: `SwitchListTile`
  /// (allowInsecure) рисует чернила на ближайшем Material-предке, а на крашеном
  /// `DecoratedBox` Flutter роняет ассерт про невидимые всплески.
  Widget _section(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExpressiveSectionHeader(title),
        ExpressiveCard(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }

  /// Поле ввода: заливка вместо рамки.
  ///
  /// Обводка на каждом поле поверх обведённой же карточки давала сетку из
  /// прямоугольников; в M3 заполненное поле отделяется от карточки тоном, а
  /// рамка остаётся только у поля в фокусе.
  InputDecoration _inputDecoration({String? label, String? hint}) {
    final scheme = Theme.of(context).colorScheme;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: Theme.of(context)
          .textTheme
          .bodySmall
          ?.copyWith(color: AppTheme.textLight(context)),
      hintStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppTheme.textLight(context).withValues(alpha: 0.4),
          ),
      isDense: true,
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: ExpressiveShape.radius(ExpressiveShape.medium),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: ExpressiveShape.radius(ExpressiveShape.medium),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: ExpressiveShape.radius(ExpressiveShape.medium),
        borderSide: BorderSide(color: AppTheme.accent(context), width: 2),
      ),
    );
  }

  /// Выбор из двух-трёх вариантов — связанной группой кнопок, а не списком:
  /// все варианты видны сразу, и выбор меняется одним касанием.
  Widget _segmented(
    String id,
    String label,
    List<(String value, String text)> options,
  ) {
    final current = _drop[id] ?? options.first.$1;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 6),
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppTheme.textLight(context)),
            ),
          ),
          ExpressiveConnectedButtons<String>(
            segments: [
              for (final (value, text) in options)
                ExpressiveSegment(value: value, label: text),
            ],
            // Чужое значение (ссылка из другого клиента) в группу не влезает —
            // тогда показываем первое, но в модели его не трогаем: сохранение
            // не должно молча переписывать то, чего мы не поняли.
            selected: options.any((o) => o.$1 == current)
                ? current
                : options.first.$1,
            onChanged: (v) => setState(() => _drop[id] = v),
          ),
        ],
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
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppTheme.text(context),
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

    // Строка пункта выпадающего списка. `DropdownButton` текущее значение никак
    // не помечает — просто прокручивает к нему, поэтому меню читалось как набор
    // подписей, по которым непонятно, что уже выбрано. Выбранный пункт берёт
    // secondaryContainer и галочку — как везде в приложении.
    Widget dropdownRow(BuildContext ctx, String text, {required bool selected}) {
      final scheme = Theme.of(ctx).colorScheme;
      final textTheme = Theme.of(ctx).textTheme;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: selected
            ? BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: ExpressiveShape.radius(ExpressiveShape.small),
              )
            : null,
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style:
                    (selected
                            ? textTheme.emphasized(textTheme.bodyMedium)
                            : textTheme.bodyMedium)
                        ?.copyWith(
                          color: selected
                              ? scheme.onSecondaryContainer
                              : AppTheme.text(ctx),
                        ),
              ),
            ),
            if (selected)
              Icon(Icons.check_rounded, size: 16, color: scheme.onSecondaryContainer),
          ],
        ),
      );
    }

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
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: AppTheme.text(context)),
        icon: Icon(
          Icons.expand_more_rounded,
          size: 18,
          color: AppTheme.textLight(context),
        ),
        decoration: _inputDecoration(label: label),
        // Закрытое поле — голый текст, без обёртки подсветки: её вертикальные
        // отступы не влезали в высоту, отведённую InputDecorator'ом, и строка
        // обрезалась снизу. Выделение живёт только в раскрытом списке.
        selectedItemBuilder: (context) => [
          for (final o in opts)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                o.isEmpty ? '—' : o,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
        ],
        items: [
          for (final o in opts)
            DropdownMenuItem(
              value: o,
              child: dropdownRow(
                context,
                o.isEmpty ? '—' : o,
                selected: o == current,
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
