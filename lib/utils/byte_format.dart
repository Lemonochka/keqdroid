/// Размер файла для показа.
///
/// Приставки двоичные (KiB/MiB), потому что сверять их будут с проводником и
/// `ls -l`, а те считают так же: 61 360 128 байт keqrnel.exe — это 58,5 MiB,
/// а не 61,4 MB. Сотые доли не показываем: точность тут нужна не больше той,
/// что позволяет заметить «ядро подменилось».
String formatBytes(int bytes) {
  const units = ['B', 'KiB', 'MiB', 'GiB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  // Байты — всегда целые; у трёхзначных значений дробная часть уже шум.
  final digits = unit == 0 || value >= 100 ? 0 : 1;
  return '${value.toStringAsFixed(digits)} ${units[unit]}';
}

/// Дата файла — только день: час правки бинаря ни о чём не говорит, а строку
/// в панели удлиняет вдвое. Локальная зона, ISO-порядок.
String formatFileDate(DateTime date) {
  final local = date.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$month-$day';
}
