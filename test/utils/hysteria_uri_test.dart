import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/utils/hysteria_uri.dart';

void main() {
  test('parses obfs and builds finalmask', () {
    const uri =
        'hysteria2://pwd@host:443?obfs=salamander&obfs-password=abc&sni=host';
    final p = HysteriaLinkParams.fromConfig(uri);
    expect(p.hasSalamanderObfs, isTrue);
    expect(p.buildFinalmask(), isNotNull);
  });

  test('formatBandwidth adds mbps suffix for plain numbers', () {
    expect(HysteriaLinkParams.formatBandwidth('100'), '100mbps');
    expect(HysteriaLinkParams.formatBandwidth('50 Mbps'), '50 Mbps');
  });
}
