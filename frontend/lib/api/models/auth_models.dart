enum UserRole { citizen, volunteer, official }

extension UserRoleX on UserRole {
  String get wire => switch (this) {
        UserRole.citizen => 'citizen',
        UserRole.volunteer => 'volunteer',
        UserRole.official => 'official',
      };

  String get label => switch (this) {
        UserRole.citizen => 'Citizen',
        UserRole.volunteer => 'Volunteer',
        UserRole.official => 'Official',
      };

  static UserRole fromWire(String value) => switch (value) {
        'volunteer' => UserRole.volunteer,
        'official' => UserRole.official,
        _ => UserRole.citizen,
      };
}

class RegisterRequest {
  final String fullName;
  final String email;
  final String password;
  final UserRole role;

  const RegisterRequest({
    required this.fullName,
    required this.email,
    required this.password,
    required this.role,
  });

  Map<String, dynamic> toJson() => {
        'full_name': fullName,
        'email': email,
        'password': password,
        'role': role.wire,
      };
}

class LoginRequest {
  final String email;
  final String password;

  const LoginRequest({required this.email, required this.password});

  Map<String, dynamic> toJson() => {'email': email, 'password': password};
}

class UserProfile {
  final String id;
  final String fullName;
  final String email;
  final UserRole role;

  const UserProfile({
    required this.id,
    required this.fullName,
    required this.email,
    required this.role,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'] as String,
        fullName: json['full_name'] as String,
        email: json['email'] as String,
        role: UserRoleX.fromWire(json['role'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'full_name': fullName,
        'email': email,
        'role': role.wire,
      };
}

class AuthResponse {
  final String token;
  final UserProfile user;

  const AuthResponse({required this.token, required this.user});

  factory AuthResponse.fromJson(Map<String, dynamic> json) => AuthResponse(
        token: json['token'] as String,
        user: UserProfile.fromJson(json['user'] as Map<String, dynamic>),
      );
}
