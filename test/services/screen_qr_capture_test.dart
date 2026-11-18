import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/services/screen_qr_capture.dart';

void main() {
  test('takes the gray frame the runner sent', () {
    final frame = ScreenQrCapture.frameFromMap({
      'width': 3,
      'height': 2,
      'gray': Uint8List.fromList([1, 2, 3, 4, 5, 6]),
    });
    expect(frame?.width, 3);
    expect(frame?.height, 2);
    expect(frame?.pixels, [1, 2, 3, 4, 5, 6]);
  });

  test('a frame whose size and bytes disagree is dropped, not read past the end', () {
    expect(
      ScreenQrCapture.frameFromMap({
        'width': 4,
        'height': 2,
        'gray': Uint8List(6),
      }),
      isNull,
    );
    expect(ScreenQrCapture.frameFromMap({'width': 0, 'height': 0, 'gray': Uint8List(0)}), isNull);
    expect(ScreenQrCapture.frameFromMap(null), isNull);
    expect(ScreenQrCapture.frameFromMap({'path': '/tmp/shot.png'}), isNull);
  });
}
