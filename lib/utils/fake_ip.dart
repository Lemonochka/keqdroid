library;

// у mihomo тот же диапазон записан с .1: оттуда он берёт адрес своего tun-интерфейса
const kFakeIpRange = '198.18.0.0/16';

// dns.FakeIPv6Pool ядра (RFC 5180), не попадает в fc00::/7 из direct-private
const kFakeIpv6Range = '2001:2::/48';

// проверки связности ОС: получив немой адрес, система рисует нет интернета поверх рабочего туннеля
const kFakeIpFilter = <String>[
  '*.lan',
  '*.local',
  '*.localdomain',
  '*.home.arpa',
  'localhost',
  'connectivitycheck.gstatic.com',
  '*.msftconnecttest.com',
  '*.msftncsi.com',
  'captive.apple.com',
  'time.*.com',
  '*.ntp.org',
];

List<String> fakeIpFilterAsRules() => [
  for (final pattern in kFakeIpFilter) _asRule(pattern),
];

String _asRule(String pattern) {
  if (!pattern.contains('*')) return 'full:$pattern';
  final rest = pattern.substring(2);
  if (pattern.startsWith('*.') && !rest.contains('*')) return 'domain:$rest';
  final labels = [
    for (final label in pattern.split('.'))
      label == '*' ? '[^.]+' : RegExp.escape(label),
  ];
  return 'regexp:^${labels.join(r'\.')}\$';
}
