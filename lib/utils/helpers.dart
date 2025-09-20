

String formatNumber(int number, {bool arabic = true}) {
  if (arabic) {
    if (number >= 1000000000) {
      return '${(number / 1000000000).toStringAsFixed(1)} مليار';
    } else if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)} مليون';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)} ألف';
    }
  } else {
    if (number >= 1000000000) {
      return '${(number / 1000000000).toStringAsFixed(1)}B';
    } else if (number >= 1000000) {
      return '${(number / 1000000).toStringAsFixed(1)}M';
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}K';
    }
  }
  return number.toString();
}
