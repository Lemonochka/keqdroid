/// Тетрис по Tetris Guideline — пасхалка в экране «О приложении».
///
/// Пакет намеренно ничего не знает про keqdroid: ни темы, ни провайдеров, ни
/// локализации, ни хранилища. Всё, что ему нужно от приложения, приходит
/// параметрами — включая лучший результат и обратный вызов на конец партии.
library;

export 'src/bag.dart';
export 'src/game.dart';
export 'src/playfield.dart';
export 'src/rules.dart';
export 'src/srs.dart';
export 'src/tetromino.dart';
export 'src/ui/board_painter.dart';
export 'src/ui/keqtris_screen.dart';
export 'src/ui/skin.dart';
