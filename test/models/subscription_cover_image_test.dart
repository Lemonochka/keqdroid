import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/models/subscription_card_theme.dart';

Future<String> _png(Directory dir, int width, int height) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF3366CC),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  picture.dispose();
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final file = File('${dir.path}${Platform.pathSeparator}${width}x$height.png');
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  return file.path;
}

Future<ui.Size> _decoded(String path) async {
  final done = Completer<ui.Size>();
  final stream = SubscriptionCardTheme.coverImage(path).resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      done.complete(ui.Size(info.image.width.toDouble(), info.image.height.toDouble()));
      stream.removeListener(listener);
    },
    onError: (e, _) => done.completeError(e),
  );
  stream.addListener(listener);
  return done.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('cover'));
  tearDown(() {
    PaintingBinding.instance.imageCache.clear();
    dir.deleteSync(recursive: true);
  });

  testWidgets('фото с телефона декодируется не крупнее 2048 и с теми же пропорциями', (tester) async {
    final size = await tester.runAsync(() async => _decoded(await _png(dir, 4000, 2000)));
    expect(size, const ui.Size(2048, 1024));
  });

  testWidgets('фон карточки держит фото с телефона не крупнее 2048', (tester) async {
    final path = await tester.runAsync(() => _png(dir, 4000, 2000));
    final name = path!.split(Platform.pathSeparator).last;
    final theme = SubscriptionCardTheme.file(name, dir.path);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => SizedBox(
          width: 400,
          height: 160,
          child: theme.background(context, veil: CardVeil.none),
        ),
      ),
    ));
    final raw = find.byType(RawImage);
    for (var i = 0; i < 50 && tester.widget<RawImage>(raw).image == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(tester.widget<RawImage>(raw).image!.width, lessThanOrEqualTo(2048));
  });

  testWidgets('обложка меньше предела остаётся в своём размере', (tester) async {
    final size = await tester.runAsync(() async => _decoded(await _png(dir, 1200, 675)));
    expect(size, const ui.Size(1200, 675));
  });
}
