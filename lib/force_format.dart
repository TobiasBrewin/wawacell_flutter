String formatForceValue(double? value, {String unit = 'kN'}) {
  if (value == null || !value.isFinite) return '';
  switch (unit) {
    case 'kg':
      return value.round().toString().padLeft(4, '!');
    case 'Lb':
      final rounded = (value / 2).round() * 2;
      return rounded.toString().padLeft(4, '!');
    default:
      if (value > 99.99) return '99.99';
      if (value < -9.99) return '-9.99';
      if (value > -0.005 && value < 0) return '0.00'.padLeft(5, '!');
      return value.toStringAsFixed(2).padLeft(5, '!');
  }
}
