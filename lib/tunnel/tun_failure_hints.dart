/// Разбор вывода ядра, когда TUN не поднялся.
///
/// Наружу такие падения выглядят одинаково — «TUN did not start (exit code 1)»
/// плюс хвост лога, в котором пользователю нечего опознать. Причин же ровно
/// десяток, и почти каждая чинится в одно действие: дать права, вернуть
/// снесённый антивирусом `wintun.dll`, подгрузить модуль `tun`, сменить порт.
/// Здесь они названы явно.
///
/// Правило про порядок: сначала САМЫЕ узкие признаки. «access is denied»
/// встречается в половине сообщений, поэтому идёт после того, что говорит о
/// причине конкретнее.
library;

/// Опознанная причина: [id] — для тестов и логов, [message] — текст человеку.
class TunFailureHint {
  final String id;
  final String message;

  const TunFailureHint(this.id, this.message);
}

/// Ищет в выводе ядра известную причину. `null` — ничего знакомого.
TunFailureHint? tunFailureHint(String coreOutput, {required bool windows}) {
  final text = coreOutput.toLowerCase();
  if (text.trim().isEmpty) return null;

  bool has(String needle) => text.contains(needle);
  bool hasAny(List<String> needles) => needles.any(has);

  // --- сборка ядра -------------------------------------------------------
  if (has('gvisor is not included')) {
    return const TunFailureHint(
      'gvisor-missing',
      'This core build has no gVisor network stack, and the TUN stack is set '
          'to gVisor/mixed. Set the TUN stack to "system" in Settings → Core '
          'and protocols, or reinstall the app (shipped cores are built with '
          'gVisor).',
    );
  }

  // --- wintun ------------------------------------------------------------
  // Отдельная ветка до общего «access is denied»: тут дело не в правах.
  if (windows &&
      (has('wintun') || has('tun.dll')) &&
      hasAny([
        'cannot find',
        'not found',
        'no such file',
        'could not be found',
        'не удается найти',
        'не удалось найти',
        'error 126',
        'errno 126',
      ])) {
    return const TunFailureHint(
      'wintun-missing',
      'The wintun driver could not be loaded: wintun.dll is missing or blocked '
          'next to the core. Antivirus quarantine and half-unpacked portable '
          'builds are the usual reasons — reinstall the app, restore the file '
          'from quarantine and add the app folder to the antivirus exclusions.',
    );
  }
  if (windows &&
      has('wintun') &&
      hasAny(['access is denied', 'отказано в доступе', 'access denied'])) {
    return const TunFailureHint(
      'wintun-access',
      'The wintun adapter could not be created: access denied. Run the app as '
          'Administrator; if it already is, a security product is blocking the '
          'driver — add the app folder to its exclusions.',
    );
  }

  // Адаптер/устройство от прошлой сессии ещё не снят.
  if (hasAny([
        'already exists',
        'file exists',
        'device or resource busy',
        'уже существует',
      ]) &&
      hasAny(['adapter', 'tun', 'interface'])) {
    return const TunFailureHint(
      'adapter-busy',
      'The TUN adapter from a previous session is still being removed by the '
          'system. Wait a few seconds and connect again; if it keeps '
          'happening, close every other VPN client (a second sing-box based '
          'client can hold the same adapter) and try once more.',
    );
  }

  // --- Linux: устройство и права ----------------------------------------
  if (hasAny(['/dev/net/tun', 'dev/net/tun']) &&
      hasAny([
        'no such file',
        'not exist',
        'cannot open',
        'нет такого файла',
      ])) {
    return const TunFailureHint(
      'devtun-missing',
      'The kernel TUN device /dev/net/tun does not exist: the `tun` module is '
          'not loaded (or the system runs inside a container without it). Run '
          '`sudo modprobe tun` and connect again; add "tun" to '
          '/etc/modules-load.d/ to make it permanent.',
    );
  }
  if (hasAny(['operation not permitted', 'permission denied', 'eperm']) &&
      hasAny(['tun', 'route', 'netlink', 'nftables', 'iptables'])) {
    return TunFailureHint(
      'no-privileges',
      windows
          ? 'The core was not allowed to create the network adapter or edit '
                'routes. Run the app as Administrator, or use Proxy mode.'
          : 'The core was not allowed to create the TUN device or edit routes. '
                'TUN mode needs root via pkexec (polkit) — approve the password '
                'prompt. Inside containers/sandboxes it also needs CAP_NET_ADMIN '
                'and access to /dev/net/tun.',
    );
  }

  // --- порты (локальные инбаунды внутри того же процесса) ----------------
  if (hasAny([
    'forbidden by its access permissions',
    'wsaeacces',
    'запрещенным его правами доступа',
  ])) {
    return const TunFailureHint(
      'port-reserved',
      'A local port could not be opened: the system forbids binding it. On '
          'Windows this is normally a range reserved for Hyper-V / WSL2 / '
          'Docker (nothing is listening there, so the port looks free) — check '
          '`netsh interface ipv4 show excludedportrange protocol=tcp` and set '
          'local ports outside those ranges in Settings.',
    );
  }
  if (hasAny([
    'address already in use',
    'only one usage of each socket address',
    'обычно разрешается только одно использование адреса сокета',
    'bind: address already in use',
  ])) {
    return const TunFailureHint(
      'port-busy',
      'A local port the core needs is already taken by another program '
          '(another VPN client, a leftover core, a local server). Close it, or '
          'change the local ports in Settings → Core and protocols.',
    );
  }

  // --- сеть ---------------------------------------------------------------
  if (hasAny([
    'missing default interface',
    'no route to internet',
    'default interface not found',
    'network is unreachable',
  ])) {
    return const TunFailureHint(
      'no-default-route',
      'The core could not find a working network interface: the machine has no '
          'default route right now (Wi-Fi/Ethernet down, another VPN taking '
          'over, a virtual adapter shadowing the default route). Reconnect the '
          'network and try again.',
    );
  }

  // --- IPv6 ---------------------------------------------------------------
  if (has('ipv6') &&
      hasAny([
        'access is denied',
        'отказано в доступе',
        'not supported',
        'cannot assign requested address',
      ])) {
    return const TunFailureHint(
      'ipv6-refused',
      'The system refused the IPv6 part of the TUN interface (IPv6 is disabled '
          'in the OS or by policy). Set TUN → IPv6 to "off" in Settings → Core '
          'and protocols.',
    );
  }

  // --- конфиг -------------------------------------------------------------
  if (hasAny([
    'decode config',
    'parse config',
    'unknown transport type',
    'unmarshal',
    'invalid config',
    'json: cannot unmarshal',
    'yaml:',
  ])) {
    return const TunFailureHint(
      'bad-config',
      'The core rejected the generated configuration, so nothing was started. '
          'This is usually an unsupported value in Settings (custom DNS, '
          'routing rules) — the core message above names the field. Reset that '
          'setting, or report the message.',
    );
  }

  // --- общий отказ в правах (последним: слишком широкий признак) ----------
  if (hasAny(['access is denied', 'отказано в доступе', 'access denied'])) {
    return TunFailureHint(
      'access-denied',
      windows
          ? 'Access denied while setting up the tunnel. TUN mode needs '
                'Administrator rights (the adapter, the route table and DNS); if '
                'the app is already elevated, a security product is blocking it.'
          : 'Access denied while setting up the tunnel. TUN mode needs root — '
                'approve the polkit prompt, or use Proxy mode.',
    );
  }

  return null;
}

/// Собирает готовый текст ошибки старта TUN: подсказка (если узнали причину),
/// затем базовый совет, затем хвост лога ядра.
///
/// Хвост обязателен: подсказка объясняет типовой случай, а разбирать всегда
/// приходится нетиповой.
String tunStartFailureMessage({
  required String fallback,
  required String coreOutput,
  required bool windows,
  String? tail,
}) {
  final hint = tunFailureHint(coreOutput, windows: windows);
  final body = hint == null ? fallback : '${hint.message}\n\n$fallback';
  final logTail = (tail ?? '').trim();
  return logTail.isEmpty ? body : '$body\n$logTail';
}
