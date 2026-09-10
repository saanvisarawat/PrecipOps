import 'dart:math';
import '../../core/constants/national_metros.dart';
import '../models/shelter_models.dart';

/// Hand-shaped, pan-India fake data used by [MockPreciopsApi].
/// Coordinates are jittered around real metro centers so pins land inside
/// the correct city without claiming to be surveyed data.
class NationalMockData {
  NationalMockData._();

  static final Random _rng = Random(42);

  static const List<String> _shelterKinds = [
    'Govt. Higher Secondary School',
    'Community Hall',
    'Municipal Relief Camp',
    'Govt. Primary School',
    'Community Center',
    'Ward Office Auditorium',
  ];

  static double _jitter(double base, double spread) =>
      base + (_rng.nextDouble() * 2 - 1) * spread;

  static List<ShelterFeature> generateShelters() {
    final shelters = <ShelterFeature>[];
    var idCounter = 1;
    for (final metro in NationalMetros.all) {
      final count = 2 + _rng.nextInt(2); // 2-3 shelters per metro
      for (var i = 0; i < count; i++) {
        final capacity = 80 + _rng.nextInt(320);
        final occupancy = (_rng.nextDouble() * capacity * 1.05).round();
        final kind = _shelterKinds[_rng.nextInt(_shelterKinds.length)];
        shelters.add(ShelterFeature(
          id: 'shelter-${idCounter.toString().padLeft(3, '0')}',
          name: '$kind, ${metro.name}',
          district: metro.name,
          latitude: _jitter(metro.center.latitude, 0.09),
          longitude: _jitter(metro.center.longitude, 0.09),
          capacity: capacity,
          currentOccupancy: occupancy.clamp(0, capacity + 40),
          address: '$kind Rd, ${metro.name}',
        ));
        idCounter++;
      }
    }
    return shelters;
  }

  static const List<String> sosDescriptions = [
    'Water entering ground floor, family of 4 stranded, need boat rescue',
    'Elderly couple trapped on terrace, rising water on street',
    'Vehicle stuck in waterlogged road, unable to move',
    'Landslide debris blocking only access road, house at risk',
    'Child and two adults stranded on rooftop, need immediate evacuation',
    'Storm drain overflow reported nearby, homes flooding fast',
    'No drinking water, house surrounded by floodwater for 2 days',
    'Diabetic patient needs medication, road submerged',
  ];

  static const List<String> reporterAliases = [
    'Anand K.', 'Devika S.', 'Rahul M.', 'Fathima N.', 'Sujith P.',
    'Meera R.', 'Arjun V.', 'Lakshmi T.', 'Nizam A.', 'Priya C.',
  ];

  static const List<String> chatOnlineReplies = [
    'Move to higher ground immediately. Avoid walking or driving through '
        'flowing water — 15cm can knock you off your feet. Keep emergency '
        'contacts and a torch handy.',
    'If your area has an active flood warning, pack essential medicines, '
        'documents in a waterproof bag, and move to the nearest relief camp. '
        'You can find nearby shelters on the Evacuation Map tab.',
    'For snake bites during flooding: keep the person still, immobilize the '
        'limb below heart level, and get to the nearest PHC. Do not apply a '
        'tourniquet or attempt to suck out venom.',
    'Boil or chemically treat all drinking water during flood conditions to '
        'avoid waterborne diseases like cholera and leptospirosis.',
    'If trapped by rising water, go to the highest point of the building, '
        'signal for help with a bright cloth or light, and call for rescue '
        'using the SOS button.',
  ];

  static const List<String> chatOfflineReplies = [
    '[Offline protocol] Standard flood advisory: avoid contact with '
        'floodwater, move to higher ground, and conserve phone battery for '
        'emergency calls only.',
    '[Offline protocol] Local cached guidance: keep away from electrical '
        'lines near standing water. Switch off mains power if it is safe to '
        'reach the switchboard.',
    '[Offline protocol] Cached first-aid note: for hypothermia symptoms '
        '(shivering, confusion), remove wet clothing and wrap in dry, warm '
        'layers as soon as possible.',
  ];

  static const List<String> agentNames = [
    'Hydrology Agent',
    'Infrastructure Agent',
    'Population Density Agent',
    'Historical Pattern Agent',
    'Coordinator Agent',
  ];

  static const List<VolunteerTaskTemplate> taskTemplates = [
    VolunteerTaskTemplate('Family of 5 stranded near river embankment, boat needed'),
    VolunteerTaskTemplate('Elderly resident requires medical evacuation'),
    VolunteerTaskTemplate('Deliver drinking water and food packets to relief camp'),
    VolunteerTaskTemplate('Assist shelter intake and headcount at relief camp'),
    VolunteerTaskTemplate('Check on reported structural damage, possible trapped residents'),
  ];
}

class VolunteerTaskTemplate {
  final String description;
  const VolunteerTaskTemplate(this.description);
}
