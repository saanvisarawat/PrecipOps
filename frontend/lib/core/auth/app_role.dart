import '../../api/models/auth_models.dart';

/// PS 26071's 3-tier role model — PREDICTOR / RESPONDER / CITIZEN — used
/// purely to decide which dashboard a signed-in user lands on.
///
/// The backend's user table and JWT still carry the original 3-value
/// [UserRole] (citizen/volunteer/official) — there is no PREDICTOR/
/// RESPONDER/CITIZEN column anywhere server-side. `auth.py`'s
/// `_normalize_role` maps one onto the other at request-authorization time
/// (official/admin/predictor -> PREDICTOR, volunteer/responder ->
/// RESPONDER, else -> CITIZEN); [fromLegacy] mirrors that exact mapping
/// client-side so dashboard routing agrees with what the backend will
/// actually authorize.
enum AppRole { predictor, responder, citizen }

extension AppRoleX on AppRole {
  static AppRole fromLegacy(UserRole role) => switch (role) {
        UserRole.official => AppRole.predictor,
        UserRole.volunteer => AppRole.responder,
        UserRole.citizen => AppRole.citizen,
      };

  String get label => switch (this) {
        AppRole.predictor => 'Predictor',
        AppRole.responder => 'Responder',
        AppRole.citizen => 'Citizen',
      };

  String get subtitle => switch (this) {
        AppRole.predictor => 'IMD Meteorologist / MoES',
        AppRole.responder => 'District Magistrate / NDMA / NDRF',
        AppRole.citizen => 'General Public / Field Volunteer',
      };
}
