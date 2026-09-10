import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/utils/config_gen.dart';
import 'package:keqdroid/utils/mihomo_config_gen.dart';
import 'package:keqdroid/utils/socks5_credentials.dart';

/// Перепись параметров ссылок: что ссылка несёт — то и обязано доехать до ядра.
///
/// Пять заходов «сделать генератор, который принимает всё» не сошлись потому,
/// что чинилось попадавшееся на глаза, а списка не было. Список — здесь.
///
/// Строка переписи — это протокол, контекст (многие параметры живут только в
/// связке: `pbk` без `security=reality` бессмыслен, `serviceName` без
/// `type=grpc` тоже) и сам параметр. Проверка одна на все строки и на оба
/// генератора: конфиг со строкой обязан отличаться от конфига без неё. Если не
/// отличается — параметр потерян по дороге, и строке место в одном из двух
/// списков ниже.
///
/// [_waivedXray] / [_waivedMihomo] — выброшено сознательно: у ядра нет такого
/// поля, либо мы отказались его писать (`insecure`). С причиной и адресом в
/// исходниках ядра.
///
/// [_gapsXray] / [_gapsMihomo] — известная дыра с номером задачи. Задача её
/// чинит и вычёркивает свои строки отсюда.
///
/// Список стареет в обе стороны, поэтому тест ругается и наоборот: строка
/// лежит в дырах, а параметр уже доезжает — убери её. Иначе перепись тихо
/// превратится в бумажку.
///
/// Откуда взяты сами параметры: все `query.Get(...)` в
/// `common/convert/converter.go` и `v.go` mihomo (ядро само переводит ссылки —
/// это готовый эталон), стандарт ссылок XTLS/Xray-core #716, поля vmess-json
/// v2rayN и наши алиасы из `lib/utils/hysteria_uri.dart`.
///
/// Чего здесь намеренно нет: SOCKS и HTTP как серверы, Hysteria v1 — решено
/// не поддерживать.

const _uuid = '00000000-0000-4000-8000-000000000000';
const _host = '198.51.100.10:443';

/// Синтетика: настоящих ключей и паролей ниже быть не должно.
const _pcs = 'YWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWE=';
const _ech = 'AEX+DQBBzQAgACD0RY0ZGF9nQqPMhTPT8xzDLoyPTgUYNGyLGUqPXGEXCg==';
const _pqv = 'bWxkc2E2NXZlcmlmeWtleQ';
const _encryption = 'mlkem768x25519plus.native.600s.dGVzdGtleQ';

const _settings = AppSettings();

/// Одна строка переписи.
final class _Row {
  const _Row(this.protocol, this.context, this.param, this.base, this.link);

  final String protocol;
  final String context;
  final String param;

  /// Ссылка без параметра и она же с ним — всё остальное совпадает.
  final String base;
  final String link;

  String get id => '$protocol/$context/$param';
}

/// Строка на обычной ссылке: параметр дописывается в конец запроса.
///
/// Фрагмента (`#имя`) в базах нет намеренно: дописывать `&x=y` после него
/// нельзя, а генераторам имя из ссылки и не нужно — тег прокси у обоих свой.
_Row _row(
  String protocol,
  String context,
  String base,
  String param,
  String value,
) =>
    _Row(protocol, context, param, base, '$base&$param=$value');

String _vmessLink(Map<String, String> fields) =>
    'vmess://${base64.encode(utf8.encode(jsonEncode(fields)))}';

/// Строка на vmess-ссылке: параметры там не в запросе, а полями base64-json.
_Row _vmessRow(
  String context,
  Map<String, String> base,
  String field,
  String value,
) =>
    _Row(
      'vmess',
      context,
      field,
      _vmessLink(base),
      _vmessLink({...base, field: value}),
    );

const _vmessBase = <String, String>{
  'v': '2',
  'ps': 'n',
  'add': '198.51.100.10',
  'port': '443',
  'id': _uuid,
  'aid': '0',
  'net': 'tcp',
  'type': 'none',
};

final _vmessTls = <String, String>{..._vmessBase, 'tls': 'tls'};

/// База под транспорты: `sni` задан явно, иначе `host` подменял бы собой имя
/// сертификата и строка про `host` проходила бы, ничего о транспорте не сказав.
Map<String, String> _vmessNet(String net) =>
    {..._vmessTls, 'sni': 'vmess.example', 'net': net};

final _rows = <_Row>[
  // ───────────────────────────── VLESS ─────────────────────────────
  _row('vless', 'tcp', 'vless://$_uuid@$_host?type=tcp&security=none',
      'packetEncoding', 'xudp'),
  _row('vless', 'tcp', 'vless://$_uuid@$_host?type=tcp&security=none',
      'encryption', _encryption),
  _row('vless', 'tcp', 'vless://$_uuid@$_host?type=tcp&security=none',
      'headerType', 'http'),

  _row('vless', 'tls', 'vless://$_uuid@$_host?type=tcp&security=tls', 'sni',
      'tls.example'),
  _row('vless', 'tls',
      'vless://$_uuid@$_host?type=tcp&security=tls&sni=tls.example', 'alpn',
      'h2,http%2F1.1'),
  _row('vless', 'tls',
      'vless://$_uuid@$_host?type=tcp&security=tls&sni=tls.example', 'fp',
      'chrome'),
  _row('vless', 'tls',
      'vless://$_uuid@$_host?type=tcp&security=tls&sni=tls.example', 'pcs',
      _pcs),
  _row('vless', 'tls',
      'vless://$_uuid@$_host?type=tcp&security=tls&sni=tls.example', 'vcn',
      'verify.example'),
  _row('vless', 'tls',
      'vless://$_uuid@$_host?type=tcp&security=tls&sni=tls.example', 'ech',
      _ech),

  _row('vless', 'reality',
      'vless://$_uuid@$_host?type=tcp&security=reality&sni=decoy.example',
      'pbk', 'publickey'),
  _row(
      'vless',
      'reality',
      'vless://$_uuid@$_host?type=tcp&security=reality&sni=decoy.example'
          '&pbk=publickey',
      'sid',
      'aabb'),
  _row(
      'vless',
      'reality',
      'vless://$_uuid@$_host?type=tcp&security=reality&sni=decoy.example'
          '&pbk=publickey',
      'spx',
      '%2Fspider'),
  _row(
      'vless',
      'reality',
      'vless://$_uuid@$_host?type=tcp&security=reality&sni=decoy.example'
          '&pbk=publickey',
      'pqv',
      _pqv),
  _row(
      'vless',
      'reality',
      'vless://$_uuid@$_host?type=tcp&security=reality&sni=decoy.example'
          '&pbk=publickey',
      'fp',
      'chrome'),
  _row(
      'vless',
      'reality',
      'vless://$_uuid@$_host?type=tcp&security=reality&sni=decoy.example'
          '&pbk=publickey',
      'flow',
      'xtls-rprx-vision'),

  _row('vless', 'ws',
      'vless://$_uuid@$_host?type=ws&security=tls&sni=ws.example', 'path',
      '%2Fws'),
  _row('vless', 'ws',
      'vless://$_uuid@$_host?type=ws&security=tls&sni=ws.example', 'host',
      'wshost.example'),
  _row('vless', 'ws',
      'vless://$_uuid@$_host?type=ws&security=tls&sni=ws.example', 'ed', '2048'),
  _row('vless', 'ws',
      'vless://$_uuid@$_host?type=ws&security=tls&sni=ws.example', 'eh',
      'X-Early-Data'),

  _row('vless', 'grpc',
      'vless://$_uuid@$_host?type=grpc&security=tls&sni=grpc.example',
      'serviceName', 'grpcsvc'),
  _row('vless', 'grpc',
      'vless://$_uuid@$_host?type=grpc&security=tls&sni=grpc.example', 'mode',
      'multi'),
  _row('vless', 'grpc',
      'vless://$_uuid@$_host?type=grpc&security=tls&sni=grpc.example',
      'authority', 'auth.example'),

  _row('vless', 'xhttp',
      'vless://$_uuid@$_host?type=xhttp&security=tls&sni=xh.example', 'path',
      '%2Fxh'),
  _row('vless', 'xhttp',
      'vless://$_uuid@$_host?type=xhttp&security=tls&sni=xh.example', 'host',
      'xhost.example'),
  _row('vless', 'xhttp',
      'vless://$_uuid@$_host?type=xhttp&security=tls&sni=xh.example', 'mode',
      'stream-one'),
  _row('vless', 'xhttp',
      'vless://$_uuid@$_host?type=xhttp&security=tls&sni=xh.example', 'extra',
      '%7B%22xPaddingBytes%22%3A%22100-1000%22%7D'),

  _row(
      'vless',
      'httpupgrade',
      'vless://$_uuid@$_host?type=httpupgrade&security=tls&sni=hu.example',
      'path',
      '%2Fhu'),
  _row(
      'vless',
      'httpupgrade',
      'vless://$_uuid@$_host?type=httpupgrade&security=tls&sni=hu.example',
      'host',
      'huhost.example'),
  _row(
      'vless',
      'httpupgrade',
      'vless://$_uuid@$_host?type=httpupgrade&security=tls&sni=hu.example',
      'ed',
      '2048'),

  _row('vless', 'kcp', 'vless://$_uuid@$_host?type=kcp&security=none', 'seed',
      'kcpseed'),
  _row('vless', 'kcp', 'vless://$_uuid@$_host?type=kcp&security=none',
      'headerType', 'srtp'),

  _row('vless', 'h2',
      'vless://$_uuid@$_host?type=http&security=tls&sni=h2.example', 'path',
      '%2Fh2'),
  _row('vless', 'h2',
      'vless://$_uuid@$_host?type=http&security=tls&sni=h2.example', 'host',
      'h2host.example'),

  _row('vless', 'tcp-http',
      'vless://$_uuid@$_host?type=tcp&security=none&headerType=http', 'host',
      'masq.example'),
  _row('vless', 'tcp-http',
      'vless://$_uuid@$_host?type=tcp&security=none&headerType=http', 'path',
      '%2Fmasq'),
  _row('vless', 'tcp-http',
      'vless://$_uuid@$_host?type=tcp&security=none&headerType=http', 'method',
      'POST'),

  // ───────────────────────────── VMess ─────────────────────────────
  _vmessRow('tcp', _vmessBase, 'aid', '1'),
  _vmessRow('tcp', _vmessBase, 'scy', 'zero'),
  _vmessRow('tcp', _vmessBase, 'tls', 'tls'),
  _vmessRow('tls', _vmessTls, 'sni', 'vmess.example'),
  _vmessRow('tls', _vmessTls, 'alpn', 'h2,http/1.1'),
  _vmessRow('tls', _vmessTls, 'fp', 'chrome'),
  _vmessRow('tls', _vmessTls, 'ech', _ech),
  _vmessRow('ws', _vmessNet('ws'), 'path', '/vmessws'),
  _vmessRow('ws', _vmessNet('ws'), 'host', 'wsvmess.example'),
  _vmessRow('grpc', _vmessNet('grpc'), 'path', 'grpcsvc'),
  _vmessRow('h2', _vmessNet('h2'), 'path', '/h2vmess'),
  _vmessRow('h2', _vmessNet('h2'), 'host', 'h2vmess.example'),
  _vmessRow('httpupgrade', _vmessNet('httpupgrade'), 'path', '/huvmess'),
  _vmessRow('xhttp', _vmessNet('xhttp'), 'path', '/xhvmess'),
  _vmessRow('tcp-http', {..._vmessBase, 'type': 'http'}, 'host',
      'masqvmess.example'),
  _vmessRow('tcp-http', {..._vmessBase, 'type': 'http'}, 'path', '/masqvmess'),

  // vmess-ссылка стандарта #716: по строению это vless-ссылка, а не base64-json.
  _row('vmess', 'aead', 'vmess://$_uuid@$_host?type=tcp&security=none',
      'encryption', 'zero'),
  _row('vmess', 'aead', 'vmess://$_uuid@$_host?type=tcp&security=tls', 'sni',
      'aead.example'),
  _row('vmess', 'aead',
      'vmess://$_uuid@$_host?type=tcp&security=tls&sni=aead.example', 'fp',
      'chrome'),
  _row('vmess', 'aead',
      'vmess://$_uuid@$_host?type=ws&security=tls&sni=aead.example', 'path',
      '%2Faead'),
  _row('vmess', 'aead',
      'vmess://$_uuid@$_host?type=ws&security=tls&sni=aead.example', 'host',
      'aeadhost.example'),
  _row('vmess', 'aead',
      'vmess://$_uuid@$_host?type=tcp&security=reality&sni=decoy.example',
      'pbk', 'publickey'),
  _row('vmess', 'aead',
      'vmess://$_uuid@$_host?type=tcp&security=tls&sni=aead.example', 'ech',
      _ech),

  // ───────────────────────────── Trojan ────────────────────────────
  _row('trojan', 'tls', 'trojan://password@$_host?type=tcp&security=tls', 'sni',
      'tj.example'),
  _row('trojan', 'tls',
      'trojan://password@$_host?type=tcp&security=tls&sni=tj.example', 'alpn',
      'h2,http%2F1.1'),
  _row('trojan', 'tls',
      'trojan://password@$_host?type=tcp&security=tls&sni=tj.example', 'fp',
      'chrome'),
  _row('trojan', 'tls',
      'trojan://password@$_host?type=tcp&security=tls&sni=tj.example', 'pcs',
      _pcs),
  _row('trojan', 'tls',
      'trojan://password@$_host?type=tcp&security=tls&sni=tj.example', 'vcn',
      'verify.example'),
  _row('trojan', 'tls',
      'trojan://password@$_host?type=tcp&security=tls&sni=tj.example', 'ech',
      _ech),
  _row('trojan', 'tls',
      'trojan://password@$_host?type=tcp&security=tls&sni=tj.example',
      'allowInsecure', '1'),

  _row('trojan', 'reality',
      'trojan://password@$_host?type=tcp&security=reality&sni=decoy.example',
      'pbk', 'publickey'),
  _row(
      'trojan',
      'reality',
      'trojan://password@$_host?type=tcp&security=reality&sni=decoy.example'
          '&pbk=publickey',
      'sid',
      'aabb'),

  _row('trojan', 'ws',
      'trojan://password@$_host?type=ws&security=tls&sni=tjws.example', 'path',
      '%2Ftjws'),
  _row('trojan', 'ws',
      'trojan://password@$_host?type=ws&security=tls&sni=tjws.example', 'host',
      'tjwshost.example'),
  _row('trojan', 'grpc',
      'trojan://password@$_host?type=grpc&security=tls&sni=tjg.example',
      'serviceName', 'tjgrpcsvc'),
  _row('trojan', 'grpc',
      'trojan://password@$_host?type=grpc&security=tls&sni=tjg.example',
      'authority', 'tjauth.example'),
  _row('trojan', 'xhttp',
      'trojan://password@$_host?type=xhttp&security=tls&sni=tjx.example',
      'path', '%2Ftjx'),
  _row('trojan', 'xhttp',
      'trojan://password@$_host?type=xhttp&security=tls&sni=tjx.example',
      'mode', 'stream-one'),
  _row(
      'trojan',
      'httpupgrade',
      'trojan://password@$_host?type=httpupgrade&security=tls&sni=tjh.example',
      'path',
      '%2Ftjh'),
  // На mihomo эта строка зелёная не потому, что маскировка собирается, а
  // потому что генератор на неё честно отказывается: `http-opts` у
  // `TrojanOption` нет вовсе, и ссылку разводит правило выбора ядра.
  _row('trojan', 'tcp-http',
      'trojan://password@$_host?type=tcp&security=tls&sni=tjm.example',
      'headerType', 'http'),

  // ────────────────────────── Shadowsocks ──────────────────────────
  _row('ss', 'obfs', 'ss://$_ssUser@198.51.100.10:8388?x=1', 'plugin',
      'obfs-local%3Bobfs%3Dhttp%3Bobfs-host%3Dobfs.example'),
  _row('ss', 'v2ray-plugin', 'ss://$_ssUser@198.51.100.10:8388?x=1', 'plugin',
      'v2ray-plugin%3Bmode%3Dwebsocket%3Bhost%3Dv2ray.example%3Bpath%3D%2Fv2'),
  _row('ss', 'sip002', 'ss://$_ssUser@198.51.100.10:8388?x=1', 'uot', '1'),
  _row('ss', 'sip002', 'ss://$_ssUser@198.51.100.10:8388?x=1', 'udp-over-tcp',
      'true'),

  // ─────────────────────────── Hysteria2 ───────────────────────────
  _row('hysteria2', 'base', 'hysteria2://password@$_host?x=1', 'sni',
      'hy2.example'),
  _row('hysteria2', 'base',
      'hysteria2://password@$_host?sni=hy2.example&obfs-password=obfspass',
      'obfs', 'salamander'),
  _row('hysteria2', 'base',
      'hysteria2://password@$_host?sni=hy2.example&obfs=salamander',
      'obfs-password', 'obfspass'),
  // Значение не `h3`: у xray это и есть подставляемое по умолчанию, и такая
  // строка проверяла бы не чтение параметра, а совпадение с дефолтом.
  _row('hysteria2', 'base', 'hysteria2://password@$_host?sni=hy2.example',
      'alpn', 'hq-interop'),
  _row('hysteria2', 'base', 'hysteria2://password@$_host?sni=hy2.example',
      'pinSHA256', _pcs),
  _row('hysteria2', 'base', 'hysteria2://password@$_host?sni=hy2.example', 'up',
      '100'),
  _row('hysteria2', 'base', 'hysteria2://password@$_host?sni=hy2.example',
      'down', '200'),
  _row('hysteria2', 'base', 'hysteria2://password@$_host?sni=hy2.example',
      'mport', '20000-20050'),
  // Интервал без списка портов и в ссылке бессмыслен, и у обоих ядер: перебирать
  // нечего. Поэтому контекст строки — уже включённый перебор.
  _row(
      'hysteria2',
      'base',
      'hysteria2://password@$_host?sni=hy2.example&mport=20000-20050',
      'hop-interval',
      '30'),
  _row('hysteria2', 'base', 'hysteria2://password@$_host?sni=hy2.example',
      'insecure', '1'),
  // Список портов пишут и прямо в адресе — такую ссылку `Uri.parse` не берёт,
  // и раньше она разваливалась целиком. Поэтому строка тут не про параметр
  // запроса, а про вид адреса.
  _Row(
      'hysteria2',
      'ports-in-address',
      'адрес со списком портов',
      'hysteria2://password@198.51.100.10:443?sni=hy2.example',
      'hysteria2://password@198.51.100.10:20000-20050,443?sni=hy2.example'),
];

final _ssUser = base64Url.encode(utf8.encode('aes-256-gcm:password'));

/// Выброшено сознательно на xray: поля в ядре нет либо мы отказались его писать.
const _waivedXray = <String, String>{
  'vless/tcp/packetEncoding':
      'у VLESS-аутбаунда xray такого поля нет (infra/conf/vless.go), XUDP '
          'включает мультиплексор, а не ссылка',
  'vless/ws/eh': 'имя заголовка ранних данных у xray жёстко '
      'Sec-WebSocket-Protocol (transport/internet/websocket/dialer.go), '
      'задать своё нечем',
  'vmess/tcp/aid': 'xray 26 знает только VMess AEAD, поля alterId в конфиге '
      'нет вовсе (infra/conf/vmess.go)',
  'trojan/tls/allowInsecure': 'политика: allowInsecure не эмитим никогда, '
      'см. removed_tls_fields.dart',
  'hysteria2/base/insecure': 'то же, что allowInsecure',
  'ss/obfs/plugin': 'у shadowsocks в xray плагинов нет вовсе '
      '(infra/conf/shadowsocks.go — только method и password)',
  'ss/v2ray-plugin/plugin': 'там же: плагинов нет',
  'ss/sip002/uot': 'полей uot и UoTVersion у xray 26 нет вовсе — мы их писали, '
      'а ядро молча выбрасывало; ссылку разводит правило выбора ядра',
  'ss/sip002/udp-over-tcp': 'там же',
};

/// Известные дыры xray-пути. Задача блока чинит и вычёркивает свои строки.
const _gapsXray = <String, String>{
  'vless/h2/path': 'G-03: транспорт h2 xray 26 снёс целиком '
      '(TransportProtocol.Build → PrintRemovedFeatureError), такая ссылка '
      'только для mihomo',
  'vless/h2/host': 'G-03: там же',
  'vmess/h2/path': 'G-03: там же',
  'vmess/h2/host': 'G-03: там же',
  'vless/ws/ed': 'G-24: ядро читает ed из пути (WebSocketConfig.Build), а мы '
      'оставляем его в параметрах ссылки',
  'vless/httpupgrade/ed': 'G-24: то же у HttpUpgradeConfig.Build',
  'vless/kcp/seed': 'G-12: kcpSettings не собираются вовсе',
  'vless/kcp/headerType': 'G-12: там же',
};

/// Выброшено сознательно на mihomo.
const _waivedMihomo = <String, String>{
  'vless/reality/spx':
      'у RealityOptions нет spiderX (adapter/outbound/reality.go)',
  'vless/reality/pqv': 'там же нет поля постквантовой подписи',
  'vless/grpc/mode': 'GrpcOptions это только grpc-service-name и '
      'grpc-user-agent (adapter/outbound/vmess.go)',
  'vless/grpc/authority': 'там же: authority у GrpcOptions нет',
  'trojan/grpc/authority': 'там же',
  'vless/kcp/seed': 'у VlessOption нет mkcp-opts — ссылка целиком не для '
      'mihomo, это разводит G-03',
  'vless/kcp/headerType': 'там же',
  'vmess/xhttp/path': 'xhttp-opts есть только у VlessOption; с G-03 генератор '
      'на такую ссылку честно отказывается, а не пишет ключи в пустоту',
  'trojan/xhttp/path': 'там же',
  'trojan/xhttp/mode': 'там же',
  'trojan/tls/allowInsecure': 'политика, см. removed_tls_fields.dart',
  'hysteria2/base/insecure': 'то же',
};

/// Известные дыры mihomo-пути.
const _gapsMihomo = <String, String>{
  'vless/ws/ed': 'G-24: ws-opts.max-early-data',
  'vless/ws/eh': 'G-24: ws-opts.early-data-header-name',
  'vless/httpupgrade/ed': 'G-24: v2ray-http-upgrade-fast-open',
  // Двух задач ниже в QUEUE.md ещё нет — они найдены этой переписью и описаны
  // в PROGRESS.md, откуда советник заведёт их в очередь.
  'vless/h2/host': 'G-25: h2-opts.host берётся из sni, параметр host ссылки '
      'не читается',
  'vmess/h2/host': 'G-25: там же',
  'vless/tcp/packetEncoding': 'G-26: packet-encoding, xudp и packet-addr у '
      'VlessOption есть, ссылка их не доносит',
};

void main() {
  setUp(() => Socks5Credentials().init('u', 'p'));

  group('перепись параметров: xray', () {
    for (final row in _rows) {
      test(row.id, () => _check(row, _xrayProxy, _waivedXray, _gapsXray));
    }
  });

  group('перепись параметров: mihomo', () {
    for (final row in _rows) {
      test(row.id, () => _check(row, _mihomoProxy, _waivedMihomo, _gapsMihomo));
    }
  });

  test('в списках нет строк, которых нет в переписи', () {
    final ids = _rows.map((r) => r.id).toSet();
    for (final list in [_waivedXray, _gapsXray, _waivedMihomo, _gapsMihomo]) {
      expect(list.keys.where((k) => !ids.contains(k)), isEmpty,
          reason: 'строка исчезла из переписи — убери её и из списка');
    }
  });
}

void _check(
  _Row row,
  String Function(String) proxyOf,
  Map<String, String> waived,
  Map<String, String> gaps,
) {
  final carried = proxyOf(row.base) != proxyOf(row.link);
  final excuse = waived[row.id] ?? gaps[row.id];
  if (excuse == null) {
    expect(carried, isTrue,
        reason: '${row.param} из ссылки не доехал до ядра. Либо чинить, либо '
            'заносить строку в waived (с причиной по исходникам ядра) или в '
            'knownGaps (с номером задачи).\n  без: ${row.base}\n   c:  ${row.link}');
    return;
  }
  expect(carried, isFalse,
      reason: '${row.param} уже доезжает, а строка всё ещё числится '
          'выброшенной или дырой: $excuse. Убери её из списка.');
}

/// Аутбаунд `proxy` из конфига xray — без инбаундов, dns и правил: они от
/// параметра ссылки не зависят и только зашумили бы сравнение.
String _xrayProxy(String link) {
  try {
    final config =
        jsonDecode(ConfigGeneratorV2.generateConfig(link, _settings)) as Map;
    final outbounds = (config['outbounds'] as List).cast<Map<String, dynamic>>();
    return jsonEncode(outbounds.firstWhere((o) => o['tag'] == 'proxy'));
  } catch (e) {
    // Отказ собрать конфиг — тоже исход, и от исхода без параметра он обязан
    // отличаться. Текст ошибки в сравнение не берём: в нём бывает сама ссылка.
    return 'отказ: ${e.runtimeType}';
  }
}

String _mihomoProxy(String link) {
  try {
    final config = MihomoConfigGen.build(link, _settings, socksPort: 2080);
    return jsonEncode((config['proxies'] as List).first);
  } catch (e) {
    return 'отказ: ${e.runtimeType}';
  }
}
