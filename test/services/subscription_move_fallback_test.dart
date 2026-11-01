import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/app_settings.dart';
import 'package:keqdroid/models/server_item.dart';
import 'package:keqdroid/models/subscription.dart';
import 'package:keqdroid/services/storage_service.dart';
import 'package:keqdroid/services/subscription_service.dart';
import 'package:mocktail/mocktail.dart';

class _MockStorageService extends Mock implements StorageService {}

const _oldServers = 'vless://00000000-0000-4000-8000-000000000000@198.51.100.10:443'
    '?security=reality&type=tcp#Old';
const _newServers = 'vless://00000000-0000-4000-8000-000000000000@198.51.100.20:443'
    '?security=reality&type=tcp#New';

// хост без ответа: dio отдаёт connectionError, сервис повторяет его один раз через 2 с
const _down = 'down';

void main() {
  late _MockStorageService storage;
  late List<Subscription> stored;
  late List<String> requested;

  setUpAll(() {
    registerFallbackValue(const Subscription(id: '', name: '', url: ''));
    registerFallbackValue(<ServerItem>[]);
  });

  setUp(() {
    stored = const [];
    requested = [];
    storage = _MockStorageService();
    when(() => storage.getSettings()).thenAnswer((_) async => const AppSettings());
    when(() => storage.getHwid()).thenReturn(null);
    when(() => storage.setHwid(any())).thenAnswer((_) async {});
    when(() => storage.getServers()).thenAnswer((_) async => const []);
    when(() => storage.getActiveServerId()).thenReturn(null);
    when(() => storage.replaceServersBySubscription(any(), any()))
        .thenAnswer((_) async {});
    when(() => storage.upsertSubscription(any())).thenAnswer((_) async {});
    when(() => storage.getSubscriptions()).thenAnswer((_) async => stored);
  });

  Future<UpdateResult> update(
    Subscription sub,
    Map<String, (String, Map<String, String>)> hosts,
  ) =>
      SubscriptionService(
        storage,
        dio: Dio()..httpClientAdapter = _Hosts(hosts, requested),
      ).updateSubscription(sub);

  const sub = Subscription(
    id: 's1',
    name: 'Моя подписка',
    url: 'https://old.example/sub/abc',
    cardThemeId: 'my-picture.png',
    nameIsAuto: false,
  );

  test('new-url переносит ту же подписку: id, имя и картинка на месте', () async {
    final result = await update(sub, {
      'old.example': (_oldServers, {'new-url': 'https://new.example/sub/abc'}),
      'new.example': (_newServers, {}),
    });
    expect(result.success, isTrue);
    final moved = result.subscription;
    expect(moved.url, 'https://new.example/sub/abc');
    expect(moved.id, 's1');
    expect(moved.name, 'Моя подписка');
    expect(moved.cardThemeId, 'my-picture.png');
    final saved = verify(
      () => storage.replaceServersBySubscription('s1', captureAny()),
    ).captured.single as List<ServerItem>;
    expect(saved.single.config, _newServers);
  });

  test('new-domain меняет только хост', () async {
    final result = await update(sub, {
      'old.example': (_oldServers, {'new-domain': 'mirror.example'}),
      'mirror.example': (_newServers, {}),
    });
    expect(result.subscription.url, 'https://mirror.example/sub/abc');
  });

  test('новый адрес не отвечает: подписка остаётся на старом и обновляется', () async {
    final result = await update(sub, {
      'old.example': (_oldServers, {'new-url': 'https://$_down.example/s'}),
    });
    expect(result.success, isTrue);
    expect(result.subscription.url, sub.url);
    expect(result.serverCount, 1);
  });

  test('новый адрес отвечает без серверов: подписка остаётся на старом', () async {
    final result = await update(sub, {
      'old.example': (_oldServers, {'new-url': 'https://empty.example/s'}),
      'empty.example': ('nothing here', {}),
    });
    expect(requested, contains('empty.example'));
    expect(result.success, isTrue);
    expect(result.subscription.url, sub.url);
    expect(result.serverCount, 1);
  });

  test('на адрес другой своей подписки не переезжаем', () async {
    stored = const [
      Subscription(id: 's2', name: 'Другая', url: 'https://new.example/sub/abc'),
    ];
    final result = await update(sub, {
      'old.example': (_oldServers, {'new-url': 'https://new.example/sub/abc'}),
      'new.example': (_newServers, {}),
    });
    expect(result.subscription.url, sub.url);
    expect(requested, isNot(contains('new.example')));
  });

  test('основной не отвечает: серверы берутся с запасного, адрес прежний', () async {
    final withFallback = sub.copyWith(
      url: 'https://$_down.example/sub',
      fallbackUrl: 'https://backup.example/sub',
    );
    final result = await update(withFallback, {
      'backup.example': (_newServers, {}),
    });
    expect(result.success, isTrue);
    expect(result.subscription.url, 'https://$_down.example/sub');
    expect(result.subscription.fallbackUrl, 'https://backup.example/sub');
    expect(result.serverCount, 1);
  });

  test('не отвечают оба: обновление неудачное', () async {
    final withFallback = sub.copyWith(
      url: 'https://$_down.example/sub',
      fallbackUrl: 'https://$_down.example/backup',
    );
    final result = await update(withFallback, {});
    expect(result.success, isFalse);
  });

  test('Fallback-Url и напоминание сохраняются в подписке', () async {
    final result = await update(sub, {
      'old.example': (
        _oldServers,
        {
          'fallback-url': 'https://backup.example/sub',
          'notification-subs-expire': '1',
        },
      ),
    });
    expect(result.subscription.fallbackUrl, 'https://backup.example/sub');
    expect(result.subscription.remindExpiry, isTrue);
  });
}

class _Hosts implements HttpClientAdapter {
  _Hosts(this.hosts, this.requested);

  final Map<String, (String, Map<String, String>)> hosts;
  final List<String> requested;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requested.add(options.uri.host);
    final answer = hosts[options.uri.host];
    if (answer == null) {
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        message: 'no route to ${options.uri.host}',
      );
    }
    final (body, headers) = answer;
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        'content-type': ['text/plain; charset=utf-8'],
        for (final e in headers.entries) e.key: [e.value],
      },
    );
  }
}
