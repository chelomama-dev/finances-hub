import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:finances_hub/core/api/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Pumps [screen] as the app does (Spanish locale, a router, a ProviderScope without retries).
Future<void> pumpScreen(WidgetTester tester, Widget screen, {List<dynamic> overrides = const []}) async {
  await initializeDateFormatting('es_ES');
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => screen),
      GoRoute(path: '/:rest(.*)', builder: (_, state) => Scaffold(body: Text('route ${state.uri}'))),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: overrides.cast(),
      child: MaterialApp.router(
        locale: const Locale('es', 'ES'),
        supportedLocales: const [Locale('es', 'ES')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        routerConfig: router,
      ),
    ),
  );
}

/// An [ApiClient] whose HTTP calls are answered by [respond], recording each request.
ApiClient fakeApi(FakeAdapter adapter) =>
    ApiClient(Dio(BaseOptions(baseUrl: 'http://api.test'))..httpClientAdapter = adapter);

class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.respond);

  final (int, Object?) Function(RequestOptions request) respond;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    final (status, body) = respond(options);
    return ResponseBody.fromString(
      body == null ? '' : jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [status >= 400 ? 'application/problem+json' : Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
