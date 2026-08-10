import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shreeram_crm/core/network/api_client.dart';

class AuthUser {
  AuthUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.permissions,
  });

  final int id;
  final String name;
  final String email;
  final String role;
  final List<String> permissions;

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as int,
      name: json['name'] as String,
      email: json['email'] as String,
      role: json['role'] as String,
      permissions: (json['permissions'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }

  bool get isStaffAdmin => role == 'OWNER' || role == 'ADMIN';
}

class AuthState {
  const AuthState({this.user, this.loading = false, this.error});

  final AuthUser? user;
  final bool loading;
  final String? error;

  AuthState copyWith({
    AuthUser? user,
    bool? loading,
    String? error,
    bool clearUser = false,
  }) {
    return AuthState(
      user: clearUser ? null : (user ?? this.user),
      loading: loading ?? this.loading,
      error: error,
    );
  }
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthState();

  Future<void> bootstrap() async {
    final storage = ref.read(secureStorageProvider);
    final token = await storage.read(key: 'auth_token');
    if (token == null) return;
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.get('/auth/me');
      state = AuthState(user: AuthUser.fromJson(res.data as Map<String, dynamic>));
    } catch (_) {
      await storage.delete(key: 'auth_token');
      state = const AuthState();
    }
  }

  Future<bool> login(String email, String password) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final dio = ref.read(dioProvider);
      final res = await dio.post('/auth/login', data: {
        'email': email,
        'password': password,
      });
      final token = res.data['token'] as String;
      await ref.read(secureStorageProvider).write(key: 'auth_token', value: token);
      state = AuthState(user: AuthUser.fromJson(res.data['user'] as Map<String, dynamic>));
      return true;
    } catch (_) {
      state = state.copyWith(loading: false, error: 'Login failed. Check credentials.');
      return false;
    }
  }

  Future<void> logout() async {
    try {
      await ref.read(dioProvider).post('/auth/logout');
    } catch (_) {}
    await ref.read(secureStorageProvider).delete(key: 'auth_token');
    state = const AuthState();
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);
