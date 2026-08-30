import 'dart:math';

class AxisScale {
  final double min;
  final double max;
  final double interval;

  const AxisScale({required this.min, required this.max, required this.interval});
}

AxisScale niceAxisScale(double dataMin, double dataMax, {int desiredTicks = 5}) {
  if (dataMin == dataMax) {
    if (dataMin == 0) {
      return const AxisScale(min: 0, max: 100, interval: 25);
    }
    final spread = dataMin.abs() * 0.2;
    return _computeNiceScale(dataMin - spread, dataMin + spread,
        desiredTicks: desiredTicks);
  }
  return _computeNiceScale(dataMin, dataMax, desiredTicks: desiredTicks);
}

AxisScale _computeNiceScale(double dataMin, double dataMax,
    {int desiredTicks = 5}) {
  final range = dataMax - dataMin;
  final roughStep = range / (desiredTicks - 1);
  final step = _niceNumber(roughStep);

  final niceMin = (dataMin / step).floorToDouble() * step;
  final niceMax = (dataMax / step).ceilToDouble() * step;

  return AxisScale(min: niceMin, max: niceMax, interval: step);
}

double _niceNumber(double value) {
  final exponent = (log(value) / ln10).floor();
  final fraction = value / pow(10, exponent).toDouble();

  double nice;
  if (fraction <= 1.0) {
    nice = 1.0;
  } else if (fraction <= 2.0) {
    nice = 2.0;
  } else if (fraction <= 5.0) {
    nice = 5.0;
  } else {
    nice = 10.0;
  }

  return nice * pow(10, exponent).toDouble();
}
