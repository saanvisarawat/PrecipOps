import 'package:flutter/widgets.dart';

/// Centralized corner radii — Apple-like, restrained. Not everything is
/// a pill; radius scales with the size/importance of the surface.
class AppRadius {
  AppRadius._();

  static const double small = 11;
  static const double button = 16;
  static const double card = 20;
  static const double panel = 26;
  static const double sheet = 30;

  static const BorderRadius smallR = BorderRadius.all(Radius.circular(small));
  static const BorderRadius buttonR = BorderRadius.all(Radius.circular(button));
  static const BorderRadius cardR = BorderRadius.all(Radius.circular(card));
  static const BorderRadius panelR = BorderRadius.all(Radius.circular(panel));
  static const BorderRadius sheetTopR = BorderRadius.vertical(top: Radius.circular(sheet));
}
