import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';
import 'theme.dart';

class FinancesHubApp extends ConsumerWidget {
  const FinancesHubApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'Finances Hub',
    theme: buildTheme(Brightness.light),
    darkTheme: buildTheme(Brightness.dark),
    locale: const Locale('es', 'ES'),
    supportedLocales: const [Locale('es', 'ES')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    routerConfig: ref.watch(routerProvider),
  );
}
