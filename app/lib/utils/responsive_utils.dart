import 'package:flutter/material.dart';

class ResponsiveUtils {
  static double _designWidth = 375.0; // Base design width (e.g., iPhone X)
  static double _designHeight = 812.0; // Base design height

  static double screenWidth(BuildContext context) => MediaQuery.of(context).size.width;
  static double screenHeight(BuildContext context) => MediaQuery.of(context).size.height;

  static double scaleWidth(BuildContext context, double size) {
    double scale = screenWidth(context) / _designWidth;
    if (scale > 1.5) scale = 1.5; // Cap scaling
    return size * scale;
  }

  static double scaleHeight(BuildContext context, double size) {
    double scale = screenHeight(context) / _designHeight;
    if (scale > 1.5) scale = 1.5; // Cap scaling
    return size * scale;
  }

  static double scale(BuildContext context, double size) {
    double scaleW = screenWidth(context) / _designWidth;
    double scaleH = screenHeight(context) / _designHeight;
    double scale = scaleW < scaleH ? scaleW : scaleH;
    if (scale > 1.3) scale = 1.3; // Stricter cap
    return size * scale;
  }

  static double fontSize(BuildContext context, double size) {
    return scale(context, size);
  }
}
