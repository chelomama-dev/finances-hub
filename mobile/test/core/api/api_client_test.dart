import 'package:finances_hub/core/api/api_exception.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers.dart';

void main() {
  test('shows the detail of a ProblemDetails error', () async {
    final api = fakeApi(FakeAdapter((_) => (404, {'title': 'Not Found', 'status': 404, 'detail': 'La cuenta no existe.'})));

    expect(
      () => api.get('/api/x'),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', 'La cuenta no existe.').having((e) => e.statusCode, 'status', 404)),
    );
  });

  test('falls back to a Spanish message when there is no detail', () async {
    final api = fakeApi(FakeAdapter((_) => (500, {'title': 'Internal Server Error', 'status': 500})));

    expect(() => api.get('/api/x'), throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('servidor'))));
  });
}
