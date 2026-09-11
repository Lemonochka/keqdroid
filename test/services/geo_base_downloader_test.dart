import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/services/geo_base_downloader.dart';

/// Где загрузчик полной geo-базы берёт хеш.
///
/// С 0.19.0 релиз несёт один общий `SHA256SUMS`. Загрузчик, понимающий только
/// свой `.sha256`, отказал бы в установке, хотя хеш в релизе есть.
Map<String, dynamic> _asset(String name) =>
    {'name': name, 'browser_download_url': 'https://example.invalid/$name'};

void main() {
  test('хеш из общего SHA256SUMS, когда своего .sha256 нет', () {
    expect(
      GeoBaseDownloader.urlsFromAssets([
        _asset('keqdroid-0.19.0-android.apk'),
        _asset('geoip.dat'),
        _asset('SHA256SUMS'),
      ]),
      (
        'https://example.invalid/geoip.dat',
        'https://example.invalid/SHA256SUMS',
      ),
    );
  });

  test('свой .sha256 по-прежнему годится', () {
    expect(
      GeoBaseDownloader.urlsFromAssets([
        _asset('geoip.dat'),
        _asset('geoip.dat.sha256'),
      ]),
      (
        'https://example.invalid/geoip.dat',
        'https://example.invalid/geoip.dat.sha256',
      ),
    );
  });

  test('без хеша вовсе ставить нечего', () {
    expect(GeoBaseDownloader.urlsFromAssets([_asset('geoip.dat')]), isNull);
  });

  test('без самой базы тоже', () {
    expect(GeoBaseDownloader.urlsFromAssets([_asset('SHA256SUMS')]), isNull);
  });
}
