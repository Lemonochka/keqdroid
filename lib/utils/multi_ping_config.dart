import 'dart:convert';

/// Один сервер внутри общего конфига замера: его одиночный конфиг и порт,
/// на котором проба будет ходить именно через него.
typedef PingProbe = ({String id, String configJson, int port});

/// Склеивает конфиги замера нескольких серверов в один.
///
/// Зачем: url-пинг поднимает ядро на каждый сервер, и на телефоне это упирается
/// не во время старта (оно копеечное), а в память — полсотни процессов с Go-
/// рантаймом там держать негде, поэтому замеров одновременно идёт шесть, а
/// остальные ждут очереди за мёртвыми, которые выкупают весь таймаут. Один
/// конфиг на весь батч снимает именно это: процесс один, а проб столько,
/// сколько серверов.
///
/// Почему склейка готовых конфигов, а не отдельный генератор: конфиг замера
/// несёт тонкости, которые видно не сразу, — фрагментацию, шум перед UDP,
/// direct-правила под адрес самого сервера, звенья цепочки. Второй генератор
/// разошёлся бы с первым молча и намерил бы не то, что потом подключается.
/// Здесь только механика: теги получают суффикс, каждое правило — свой
/// inboundTag, списки складываются.
abstract final class MultiPingConfig {
  /// Общий xray-конфиг: N инбаундов, N наборов аутбаундов, правила с привязкой
  /// «этот инбаунд — в этот прокси».
  ///
  /// Теги суффиксуются ВСЕ, включая `direct` и `block`: общие на весь конфиг
  /// они стоили бы разбора, чьё правило на них ссылается, а лишняя пара
  /// freedom/blackhole на сервер ядру ничего не стоит.
  static String mergeXray(List<PingProbe> probes) {
    if (probes.isEmpty) throw ArgumentError('no probes');

    final inbounds = <Map<String, dynamic>>[];
    final outbounds = <Map<String, dynamic>>[];
    final rules = <Map<String, dynamic>>[];
    Map<String, dynamic>? dns;
    String domainStrategy = 'AsIs';

    for (var i = 0; i < probes.length; i++) {
      final probe = probes[i];
      final config = jsonDecode(probe.configJson) as Map<String, dynamic>;
      final suffix = '-$i';

      dns ??= config['dns'] as Map<String, dynamic>?;
      final routing = config['routing'] as Map<String, dynamic>?;
      if (i == 0 && routing?['domainStrategy'] is String) {
        domainStrategy = routing!['domainStrategy'] as String;
      }

      final renamed = <String, String>{};
      final probeInbounds = <Map<String, dynamic>>[];
      for (final raw in (config['inbounds'] as List? ?? const [])) {
        final inbound = Map<String, dynamic>.from(raw as Map);
        final tag = inbound['tag']?.toString();
        if (tag != null) {
          renamed[tag] = '$tag$suffix';
          inbound['tag'] = '$tag$suffix';
        }
        // Порт назначает вызывающий: он же потом стучится на него пробой.
        inbound['port'] = probe.port;
        probeInbounds.add(inbound);
      }
      final probeOutbounds = <Map<String, dynamic>>[];
      for (final raw in (config['outbounds'] as List? ?? const [])) {
        final outbound = Map<String, dynamic>.from(raw as Map);
        final tag = outbound['tag']?.toString();
        if (tag != null) {
          renamed[tag] = '$tag$suffix';
          outbound['tag'] = '$tag$suffix';
        }
        probeOutbounds.add(outbound);
      }
      // Вторым проходом: dialerProxy ссылается на тег соседнего аутбаунда (так
      // подключены фрагментация и звенья цепочки), и к моменту замены карта
      // имён обязана быть полной. Лежит он в streamSettings.sockopt, но искать
      // его по известному пути нельзя — у цепочек он глубже.
      for (final outbound in probeOutbounds) {
        _renameDialerProxies(outbound, renamed);
      }
      outbounds.addAll(probeOutbounds);

      final inboundTags = [
        for (final inbound in probeInbounds) inbound['tag'].toString(),
      ];
      inbounds.addAll(probeInbounds);

      for (final raw in (routing?['rules'] as List? ?? const [])) {
        final rule = Map<String, dynamic>.from(raw as Map);
        final outboundTag = rule['outboundTag']?.toString();
        if (outboundTag != null && renamed.containsKey(outboundTag)) {
          rule['outboundTag'] = renamed[outboundTag];
        }
        final ruleInbounds = rule['inboundTag'];
        if (ruleInbounds is List) {
          rule['inboundTag'] = [
            for (final tag in ruleInbounds) renamed[tag.toString()] ?? tag,
          ];
        } else {
          // Правило без inboundTag действовало бы на все пробы разом: адрес
          // одного сервера уводил бы в direct чужую пробу, а её catch-all —
          // в чужой прокси.
          rule['inboundTag'] = inboundTags;
        }
        rules.add(rule);
      }
    }

    return jsonEncode({
      'log': {'loglevel': 'none'},
      'dns': ?dns,
      'inbounds': inbounds,
      'outbounds': outbounds,
      'routing': {'domainStrategy': domainStrategy, 'rules': rules},
    });
  }

  static void _renameDialerProxies(Object? node, Map<String, String> renamed) {
    if (node is Map) {
      for (final key in node.keys.toList()) {
        final value = node[key];
        if (key == 'dialerProxy' && value is String) {
          final next = renamed[value];
          if (next != null) node[key] = next;
          continue;
        }
        _renameDialerProxies(value, renamed);
      }
    } else if (node is List) {
      for (final item in node) {
        _renameDialerProxies(item, renamed);
      }
    }
  }

  /// Общий mihomo-конфиг: прокси на сервер, листенер на пробу и свой набор
  /// правил у каждого листенера.
  ///
  /// Привязка листенера к прокси идёт через `rule` + `sub-rules`: у листенера
  /// mihomo нет поля «ходи через этот прокси», зато есть имя набора правил, а
  /// в наборе уже `MATCH,<имя прокси>`. Тем же способом сделана LAN-раздача.
  static String mergeMihomo(
    List<PingProbe> probes, {
    required bool httpListeners,
  }) {
    if (probes.isEmpty) throw ArgumentError('no probes');

    final proxies = <Map<String, dynamic>>[];
    final listeners = <Map<String, dynamic>>[];
    final subRules = <String, List<String>>{};
    Map<String, dynamic>? base;

    for (var i = 0; i < probes.length; i++) {
      final probe = probes[i];
      final config = jsonDecode(probe.configJson) as Map<String, dynamic>;
      base ??= config;

      final renamed = <String, String>{};
      for (final raw in (config['proxies'] as List? ?? const [])) {
        final proxy = Map<String, dynamic>.from(raw as Map);
        final name = proxy['name']?.toString();
        if (name != null) {
          renamed[name] = '$name-$i';
          proxy['name'] = '$name-$i';
        }
        proxies.add(proxy);
      }

      final ruleSet = 'probe-$i';
      subRules[ruleSet] = [
        for (final raw in (config['rules'] as List? ?? const []))
          _renameProxyInRule(raw.toString(), renamed),
      ];
      listeners.add({
        'name': ruleSet,
        'type': httpListeners ? 'http' : 'socks',
        'listen': '127.0.0.1',
        // Порт у листенера — строка: mihomo читает его как диапазон портов.
        'port': '${probe.port}',
        if (!httpListeners) 'udp': false,
        'rule': ruleSet,
      });
    }

    final first = base!;
    return jsonEncode({
      'bind-address': '127.0.0.1',
      'allow-lan': false,
      'ipv6': first['ipv6'] ?? false,
      'mode': first['mode'] ?? 'rule',
      'log-level': 'silent',
      'find-process-mode': 'off',
      'geo-auto-update': false,
      if (first['dns'] != null) 'dns': first['dns'],
      'proxies': proxies,
      'listeners': listeners,
      'sub-rules': subRules,
      // Основной набор не используется ни одним листенером, но пустым его
      // оставлять нельзя: конфиг без `rules` mihomo считает неполным.
      'rules': const ['MATCH,DIRECT'],
    });
  }

  /// `MATCH,proxy` → `MATCH,proxy-3`. Имя прокси у правила mihomo — последнее
  /// поле, и только оно меняется.
  static String _renameProxyInRule(String rule, Map<String, String> renamed) {
    final comma = rule.lastIndexOf(',');
    if (comma < 0) return rule;
    final head = rule.substring(0, comma + 1);
    final target = rule.substring(comma + 1).trim();
    return '$head${renamed[target] ?? target}';
  }
}
