import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shreeram_crm/app/router.dart';
import 'package:shreeram_crm/core/theme/app_theme.dart';

class ShreeRamApp extends ConsumerWidget {
  const ShreeRamApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'ShreeRam CRM',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: router,
    );
  }
}
