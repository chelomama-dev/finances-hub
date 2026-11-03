import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import '../auth/authenticator.dart';
import '../config.dart';
import 'api_exception.dart';

/// Gives the access token for the API, or `null` when there is none.
abstract interface class TokenProvider {
  Future<String?> getToken();
}

/// The local API and demo mode have no auth.
class NoTokenProvider implements TokenProvider {
  const NoTokenProvider();

  @override
  Future<String?> getToken() async => null;
}

/// Microsoft Entra ID's token for the API. When there is none, [onSignedOut] sends the app back to the sign-in
/// screen.
class AuthenticatorTokenProvider implements TokenProvider {
  const AuthenticatorTokenProvider(this._authenticator, {required this.onSignedOut});

  final Authenticator _authenticator;
  final void Function() onSignedOut;

  @override
  Future<String?> getToken() async {
    final token = await _authenticator.tokenSilently();
    if (token == null) onSignedOut();
    return token;
  }
}

final tokenProvider = Provider<TokenProvider>((ref) {
  final authenticator = ref.watch(authenticatorProvider);
  if (authenticator == null) return const NoTokenProvider();
  return AuthenticatorTokenProvider(
    authenticator,
    onSignedOut: () => ref.read(authProvider.notifier).sessionExpired(),
  );
});

final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      baseUrl: ref.watch(appConfigProvider).apiBaseUrl,
      connectTimeout: const Duration(seconds: 10),
      // Generous: the API scales to zero in Azure, and the first request wakes it up
      receiveTimeout: const Duration(seconds: 30),
    ),
  );
  final tokens = ref.watch(tokenProvider);

  // The single place where the token is added to every request
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        try {
          final token = await tokens.getToken();
          if (token != null) options.headers['Authorization'] = 'Bearer $token';
          handler.next(options);
        } catch (e) {
          // Refreshing the token failed (usually no network): the request fails like any request that can't connect
          handler.reject(DioException(requestOptions: options, error: e));
        }
      },
    ),
  );
  return dio;
});

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient(ref.watch(dioProvider)));

/// JSON over HTTP to the Finances Hub API. Every failure becomes an [ApiException].
class ApiClient {
  ApiClient(this._dio);

  final Dio _dio;

  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => _dio.get<Map<String, dynamic>>(path, queryParameters: query));

  Future<Map<String, dynamic>> post(String path, {Object? body}) =>
      _send(() => _dio.post<Map<String, dynamic>>(path, data: body));

  Future<Map<String, dynamic>> _send(Future<Response<Map<String, dynamic>>> Function() request) async {
    try {
      final response = await request();
      return response.data ?? const {};
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  static ApiException _toApiException(DioException e) {
    final response = e.response;
    if (response == null) {
      return const ApiException('No se puede conectar con el servidor. Comprueba la conexión.');
    }

    // ProblemDetails (RFC 9457): show its detail if there is one
    final data = response.data;
    final detail = data is Map && data['detail'] is String ? data['detail'] as String : null;
    return ApiException(
      detail ?? switch (response.statusCode) {
        404 => 'No se ha encontrado.',
        401 || 403 => 'No tienes acceso.',
        _ => 'Algo ha fallado en el servidor. Inténtalo de nuevo.',
      },
      statusCode: response.statusCode,
    );
  }
}
