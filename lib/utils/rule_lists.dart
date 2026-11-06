library;

import '../models/app_settings.dart';

// пробел тоже: в домене и адресе его не бывает, а записи через пробел склеивались в одну мёртвую
final _separators = RegExp(r'[\s,]+');

List<String> routingEntries(String field) => field
    .split(_separators)
    .map((e) => e.trim())
    .where((e) => e.isNotEmpty)
    .toList();

bool isRuleListUrl(String entry) {
  final lower = entry.trim().toLowerCase();
  return lower.startsWith('https://') || lower.startsWith('http://');
}

List<String> ruleListUrls(String field) =>
    {for (final e in routingEntries(field)) if (isRuleListUrl(e)) e}.toList();

// без ссылок поле возвращается байт в байт, и конфиг у тех, кто ими не пользуется, не меняется
String withoutRuleListUrls(String field) {
  if (!field.contains('://')) return field;
  return routingEntries(field).where((e) => !isRuleListUrl(e)).join('\n');
}

class RuleListDomains {
  const RuleListDomains({
    this.direct = const [],
    this.proxy = const [],
    this.blocked = const [],
  });

  static const none = RuleListDomains();

  final List<String> direct;
  final List<String> proxy;
  final List<String> blocked;

  bool get isEmpty => direct.isEmpty && proxy.isEmpty && blocked.isEmpty;

  AppSettings expand(AppSettings settings) {
    if (isEmpty) return settings;
    String add(String field, List<String> domains) =>
        domains.isEmpty ? field : '$field\n${domains.join('\n')}';
    return settings.copyWith(
      directRules: add(settings.directRules, direct),
      proxyRules: add(settings.proxyRules, proxy),
      blockedRules: add(settings.blockedRules, blocked),
    );
  }
}

// замер 09.10.2026 на AdGuard DNS (178 тысяч): xray прибавил 80 МБ, mihomo 30
const int ruleListPhoneDomainBudget = 150000;

final _domainRe = RegExp(
  r'^(?=.{1,253}$)(?:[a-z0-9_](?:[a-z0-9_-]{0,61}[a-z0-9_])?\.)+'
  r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$',
);
final _ipv4Re = RegExp(r'^\d{1,3}(?:\.\d{1,3}){3}$');

const _sinkholes = {'0.0.0.0', '127.0.0.1', '::', '::1', '::0', '0'};

const _hostsSelf = {
  'localhost',
  'localhost.localdomain',
  'local',
  'broadcasthost',
  'ip6-localhost',
  'ip6-loopback',
  'ip6-localnet',
  'ip6-mcastprefix',
  'ip6-allnodes',
  'ip6-allrouters',
  'ip6-allhosts',
  '0.0.0.0',
};

const _wholeDomainOptions = {'important', 'all', 'document', 'doc'};

// VPN решает судьбу соединения, а не элемента страницы: берём только правила на весь домен
Set<String> parseFilterList(String body) {
  final blocked = <String>{};
  final allowed = <String>{};
  for (final raw in body.split('\n')) {
    var line = raw.trim();
    if (line.isEmpty || line.startsWith('!') || line.startsWith('[')) continue;
    if (RegExp(r'#[@?$%]?#').hasMatch(line)) continue;
    if (line.startsWith('#')) continue;

    if (line.startsWith('@@')) {
      final domain = _adblockDomain(line.substring(2));
      if (domain != null) allowed.add(domain);
      continue;
    }
    if (line.startsWith('||')) {
      final cancel = RegExp(r'\$(.*,)?badfilter(,|$)').hasMatch(line);
      final domain = _adblockDomain(
        cancel ? line.replaceFirst(RegExp(r',?badfilter'), '') : line,
      );
      if (domain != null) (cancel ? allowed : blocked).add(domain);
      continue;
    }

    final hash = line.indexOf('#');
    if (hash >= 0) line = line.substring(0, hash).trim();
    final parts = line.split(RegExp(r'\s+'));
    if (parts.length >= 2 && _sinkholes.contains(parts.first)) {
      for (final name in parts.skip(1)) {
        final domain = _domain(name);
        if (domain != null && !_hostsSelf.contains(domain)) blocked.add(domain);
      }
    } else if (parts.length == 1) {
      final domain = _domain(parts.single);
      if (domain != null) blocked.add(domain);
    }
  }
  return blocked.difference(allowed);
}

String? _adblockDomain(String rule) {
  if (!rule.startsWith('||')) return null;
  var body = rule.substring(2);
  final dollar = body.indexOf(r'$');
  if (dollar >= 0) {
    final options = body
        .substring(dollar + 1)
        .split(',')
        .map((o) => o.trim())
        .where((o) => o.isNotEmpty);
    if (!options.every(_wholeDomainOptions.contains)) return null;
    body = body.substring(0, dollar);
  }
  if (body.endsWith('^|')) {
    body = body.substring(0, body.length - 2);
  } else if (body.endsWith('^')) {
    body = body.substring(0, body.length - 1);
  } else if (body.endsWith('.')) {
    // ||ads.example. это начало имени, а не домен
    return null;
  }
  // ||*.example^ это только поддомены, правило на весь домен блокировало бы больше
  if (body.contains('*')) return null;
  return _domain(body);
}

String? _domain(String raw) {
  var s = raw.trim().toLowerCase();
  if (s.startsWith('*.')) s = s.substring(2);
  if (s.startsWith('.')) s = s.substring(1);
  if (s.endsWith('.')) s = s.substring(0, s.length - 1);
  if (s.isEmpty || _ipv4Re.hasMatch(s) || !_domainRe.hasMatch(s)) return null;
  return s;
}
