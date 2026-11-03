import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app/app.dart';
import 'core/config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_ES');

  final config = AppConfig.fromEnvironment;
  if (!config.isValid) {
    runApp(const _MissingConfigApp());
    return;
  }

  // No automatic retries: a failed request shows its error and "Reintentar" right away
  runApp(ProviderScope(retry: (_, _) => null, child: const FinancesHubApp()));
}

class _MissingConfigApp extends StatelessWidget {
  const _MissingConfigApp();

  @override
  Widget build(BuildContext context) => const MaterialApp(
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Falta configuración. Arranca la app con --dart-define=API_BASE_URL=..., '
            'con --dart-define-from-file=config/azure.json para la API en Azure '
            'o con --dart-define=DEMO=true para usar datos de ejemplo.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
  );
}
