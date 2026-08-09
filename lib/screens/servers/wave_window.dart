/// Геометрия видимого отрезка волны-индикатора — в долях ширины (0…1).
///
/// Считаем именно в долях, а не в пикселях: точку, где бегущий сегмент застало
/// подключение, нужно запомнить и развернуть из неё, а ширина к этому моменту
/// уже могла поменяться (поворот экрана, окно трея).
library;

/// Доля ширины под бегущий сегмент состояния «подключается».
const double kWaveRunningWindowFraction = 0.4;

/// Бегущий сегмент: ездит от левого края к правому и обратно.
///
/// [progress] — свободно растущая фаза волны; период пробега равен двум её
/// оборотам, поэтому сегмент не дёргается при зацикливании контроллера.
(double, double) waveRunningWindow(double progress) {
  final travel = (progress * 2) % 2;
  // Треугольная волна: 0→1→0, отсюда движение туда-обратно.
  final position = travel <= 1 ? travel : 2 - travel;
  final start =
      (1 + kWaveRunningWindowFraction) * position - kWaveRunningWindowFraction;
  return (
    start.clamp(0.0, 1.0),
    (start + kWaveRunningWindowFraction).clamp(0.0, 1.0),
  );
}

/// Разворот сегмента к полной ширине: левый край едет к нулю, правый к единице.
///
/// [t] может перелетать за единицу — это пружина, поэтому края зажимаем.
(double, double) waveExpandedWindow((double, double) from, double t) {
  double lerp(double a, double b) => a + (b - a) * t;
  return (
    lerp(from.$1, 0).clamp(0.0, 1.0),
    lerp(from.$2, 1).clamp(0.0, 1.0),
  );
}
