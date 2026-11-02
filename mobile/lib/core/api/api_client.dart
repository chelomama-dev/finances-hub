import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config.dart';
import 'api_exception.dart';

/// Gives the access token for the API, or `null` when there is none. Local development has no auth; Microsoft
/// Entra ID will plug in here.
abstract interface class TokenProvider {
  Future<String?> getToken();
}

class NoTokenProvider implements TokenProvider {
  const NoTokenProvider();

  @override
  Future<String?> getToken() async => null;
}

final tokenProvider = Provider<TokenProvider>((ref) => const NoTokenProvider());

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
        final token = await tokens.getToken();
        if (token != null) options.headers['Authorization'] = 'Bearer $token';
        handler.next(options);
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
