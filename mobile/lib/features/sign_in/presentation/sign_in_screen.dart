import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_providers.dart';
import '../../../core/auth/authenticator.dart';

/// The only screen until the owner signs in with their Microsoft account. The router leaves it by itself once
/// the status is signed in.
class SignInScreen extends ConsumerWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(authProvider);
    final theme = Theme.of(context);
    final error = status.hasError && !status.isLoading ? status.error : null;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.account_balance_wallet_outlined, size: 64, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text('Finances Hub', style: theme.textTheme.headlineMedium),
                const SizedBox(height: 8),
                const Text('Inicia sesión con tu cuenta de Microsoft para ver tus finanzas.', textAlign: TextAlign.center),
                const SizedBox(height: 32),
                if (status.isLoading)
                  const CircularProgressIndicator()
                else ...[
                  if (error != null) ...[
                    Text(
                      error is SignInException
                          ? error.message
                          : 'No se ha podido comprobar la sesión. Comprueba la conexión.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    const SizedBox(height: 16),
                  ],
                  FilledButton.icon(
                    onPressed: () => ref.read(authProvider.notifier).signIn(),
                    icon: const Icon(Icons.login),
                    label: const Text('Iniciar sesión con Microsoft'),
                  ),
                  if (error != null && error is! SignInException) ...[
                    const SizedBox(height: 8),
                    TextButton(onPressed: () => ref.invalidate(authProvider), child: const Text('Reintentar')),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
