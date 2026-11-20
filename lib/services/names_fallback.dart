import '../models/server_item.dart';
import '../tunnel/local_proxy_probe.dart';

enum NamesVerdict { fine, namesBroken, unreachable }

// Узел, у которого соединения по имени висят, а по адресу идут: так вёл себя выход провайдера в белых
// списках (жалоба 20.11.2026). Тогда адрес ищет наше ядро (targetStrategy у выхода) и шлёт узлу адрес
abstract final class NamesFallback {
  static const ttl = Duration(hours: 24);
  static const checkEvery = Duration(minutes: 1);
  static const firstCheckAfter = Duration(seconds: 5);
  static const confirmAfter = Duration(seconds: 3);
  // подряд: разовый сбой узла режим не включает
  static const missesToSwitch = 2;
  static const probeTimeout = Duration(seconds: 8);

  static final byNameUrl = Uri.parse(
    'http://connectivitycheck.gstatic.com/generate_204',
  );
  static final byAddressUrl = Uri.parse('http://1.1.1.1/cdn-cgi/trace');

  static bool active(ServerItem server, DateTime now) {
    final at = server.namesFallbackAt;
    return at != null && now.difference(at) < ttl;
  }

  static NamesVerdict verdict({
    required bool byName,
    required bool byAddress,
  }) => byName
      ? NamesVerdict.fine
      : (byAddress ? NamesVerdict.namesBroken : NamesVerdict.unreachable);

  // любой ответ дальнего конца годится; 502 и 503 отдаёт сам вход ядра, когда выход не довёз запрос
  static bool deliveredByAddress(({int? status, Object? error}) result) {
    final status = result.status;
    return status != null && status < 500;
  }

  static Future<NamesVerdict> probe(int httpPort) async {
    final byName = probeWentThrough(
      await probeLocalHttpProxy(
        httpPort,
        url: byNameUrl,
        timeout: probeTimeout,
      ),
    );
    if (byName) return NamesVerdict.fine;
    final byAddress = deliveredByAddress(
      await probeLocalHttpProxy(
        httpPort,
        url: byAddressUrl,
        timeout: probeTimeout,
      ),
    );
    return verdict(byName: false, byAddress: byAddress);
  }
}
