import 'package:flutter/material.dart';

/// Turns an OSRM `maneuver` object into the icon + human instruction shown
/// in [NavigationInstructionCard] and the expanded directions list. OSRM's
/// `type`/`modifier` vocabulary is fixed (see the OSRM API docs) — this is
/// an exhaustive mapping, not a guess.
class OsrmManeuver {
  final IconData icon;
  final String instruction;

  const OsrmManeuver({required this.icon, required this.instruction});

  factory OsrmManeuver.from({
    required String type,
    String? modifier,
    String? roadName,
  }) {
    final name = (roadName != null && roadName.isNotEmpty) ? ' onto $roadName' : '';

    switch (type) {
      case 'depart':
        return OsrmManeuver(icon: Icons.trip_origin_rounded, instruction: 'Head out$name');
      case 'arrive':
        return const OsrmManeuver(icon: Icons.flag_rounded, instruction: 'Arrive at destination');
      case 'roundabout':
      case 'rotary':
      case 'roundabout turn':
        return OsrmManeuver(icon: Icons.roundabout_left_rounded, instruction: 'Take the roundabout$name');
      case 'exit roundabout':
      case 'exit rotary':
        return OsrmManeuver(icon: Icons.roundabout_right_rounded, instruction: 'Exit the roundabout$name');
      case 'merge':
        return OsrmManeuver(icon: Icons.merge_rounded, instruction: 'Merge$name');
      case 'fork':
        return OsrmManeuver(icon: _iconForModifier(modifier), instruction: 'Keep ${_sideFor(modifier)}$name');
      case 'end of road':
        return OsrmManeuver(icon: _iconForModifier(modifier), instruction: 'Turn ${_sideFor(modifier)}$name');
      case 'continue':
      case 'new name':
        return OsrmManeuver(icon: Icons.straight_rounded, instruction: 'Continue$name');
      case 'turn':
        return OsrmManeuver(icon: _iconForModifier(modifier), instruction: 'Turn ${_sideFor(modifier)}$name');
      case 'notification':
        return OsrmManeuver(icon: Icons.straight_rounded, instruction: 'Continue straight$name');
      default:
        return OsrmManeuver(icon: Icons.straight_rounded, instruction: 'Continue$name');
    }
  }

  static String _sideFor(String? modifier) {
    switch (modifier) {
      case 'left':
        return 'left';
      case 'right':
        return 'right';
      case 'sharp left':
        return 'sharp left';
      case 'sharp right':
        return 'sharp right';
      case 'slight left':
        return 'slightly left';
      case 'slight right':
        return 'slightly right';
      case 'uturn':
        return 'around';
      case 'straight':
      default:
        return 'straight';
    }
  }

  static IconData _iconForModifier(String? modifier) {
    switch (modifier) {
      case 'left':
      case 'sharp left':
        return Icons.turn_left_rounded;
      case 'right':
      case 'sharp right':
        return Icons.turn_right_rounded;
      case 'slight left':
        return Icons.turn_slight_left_rounded;
      case 'slight right':
        return Icons.turn_slight_right_rounded;
      case 'uturn':
        return Icons.u_turn_left_rounded;
      case 'straight':
      default:
        return Icons.straight_rounded;
    }
  }
}
