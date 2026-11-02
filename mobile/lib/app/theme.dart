import 'package:flutter/material.dart';

/// Material 3, light and dark from one seed colour; the app follows the system setting.
ThemeData buildTheme(Brightness brightness) => ThemeData(
  colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B5E91), brightness: brightness),
  useMaterial3: true,
);
