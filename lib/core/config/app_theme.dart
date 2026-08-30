import 'package:flutter/material.dart';

class AppTheme {
  static final ValueNotifier<Color> seedColor = ValueNotifier(const Color(0xFF9AC53B));

  static void setSeedColor(Color color) => seedColor.value = color;
}
