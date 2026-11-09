import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/services/geo_base_downloader.dart';

/// Где загрузчик полной geo-базы берёт хеш.
///
/// Только из подписанного SHA256SUMS: свой `geoip.dat.sha256` лежит в релизе
/// ради версий 0.15–0.18, но подписи на нём нет.
Map<String, dynamic> _asset(String name) =>
    {'name': name, 'browser_download_url': 'https://example.invalid/$name'};

void main() {
  test('хеш из подписанного SHA256SUMS', () {
    expect(
      GeoBaseDownloader.urlsFromAssets([
        _asset('keqdroid-0.36.0-android.apk'),
        _asset('geoip.dat'),
        _asset('geoip.dat.sha256'),
        _asset('SHA256SUMS'),
        _asset('SHA256SUMS.sig'),
      ]),
      (
        'https://example.invalid/geoip.dat',
        'https://example.invalid/SHA256SUMS',
        'https://example.invalid/SHA256SUMS.sig',
      ),
    );
  });

  test('свой .sha256 без подписи больше не годится', () {
    expect(
      GeoBaseDownloader.urlsFromAssets([
        _asset('geoip.dat'),
        _asset('geoip.dat.sha256'),
        _asset('SHA256SUMS'),
      ]),
      isNull,
    );
  });

  test('без хеша вовсе ставить нечего', () {
    expect(GeoBaseDownloader.urlsFromAssets([_asset('geoip.dat')]), isNull);
  });

  test('без самой базы тоже', () {
    expect(
      GeoBaseDownloader.urlsFromAssets([
        _asset('SHA256SUMS'),
        _asset('SHA256SUMS.sig'),
      ]),
      isNull,
    );
  });
}
