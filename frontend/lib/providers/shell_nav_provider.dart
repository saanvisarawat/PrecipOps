import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Which ShellScreen bottom-nav tab is active. Shared so other screens
/// (the Feature Hub, the Home dashboard's own shortcuts) can jump to an
/// existing tab in place, instead of pushing a duplicate stacked copy of
/// a screen that has no AppBar/back button of its own.
final shellTabIndexProvider = StateProvider<int>((ref) => 0);
