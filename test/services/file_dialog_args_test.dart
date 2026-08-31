import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keqdroid/services/file_dialog_service.dart';

/// Сам диалог не тестируется — он существует только на Linux и только рядом с
/// живой сессией. Тестируются аргументы запасных CLI-диалогов: у zenity и
/// kdialog они устроены по-разному, а ошибка в них выглядит как та же немая
/// неудача («нажал — ничего не произошло»), ради которой обёртку и писали.
void main() {
  group('zenity/qarma', () {
    test('открытие: режим выбора файла и заголовок', () {
      final args = AppFileDialogs.cliOpenArgs('zenity', title: 'Import');

      expect(args.first, '--file-selection');
      expect(args, contains('--title=Import'));
      // Без фильтра лишнего аргумента быть не должно.
      expect(args.any((a) => a.startsWith('--file-filter=')), isFalse);
    });

    test('открытие: расширения превращаются в маски', () {
      final args = AppFileDialogs.cliOpenArgs(
        'zenity',
        type: FileType.custom,
        allowedExtensions: const ['json', 'keqdis'],
      );

      expect(args, contains('--file-filter=*.json *.keqdis | *.json *.keqdis'));
    });

    test('сохранение: имя файла уезжает в --filename', () {
      final args = AppFileDialogs.cliSaveArgs(
        'zenity',
        fileName: 'keqdis-backup.json',
      );

      expect(args, containsAll(<String>['--file-selection', '--save']));
      expect(
        args.singleWhere((a) => a.startsWith('--filename=')),
        endsWith('keqdis-backup.json'),
      );
    });
  });

  group('kdialog', () {
    test('открытие: сначала каталог, потом фильтр', () {
      final args = AppFileDialogs.cliOpenArgs(
        'kdialog',
        type: FileType.image,
      );

      final mode = args.indexOf('--getopenfilename');
      expect(mode, isNonNegative);
      // Каталог позиционный и обязателен: без него kdialog примет за него
      // фильтр и молча не покажет ничего.
      expect(args.length, mode + 3);
      expect(args[mode + 1], isNotEmpty);
      expect(args[mode + 2], startsWith('*.png '));
      expect(args[mode + 2], endsWith('|Images'));
    });

    test('сохранение: путь с именем файла одним аргументом', () {
      final args = AppFileDialogs.cliSaveArgs(
        'kdialog',
        fileName: 'keqdis-backup.json',
      );

      final mode = args.indexOf('--getsavefilename');
      expect(mode, isNonNegative);
      expect(args[mode + 1], endsWith('keqdis-backup.json'));
    });
  });
}
