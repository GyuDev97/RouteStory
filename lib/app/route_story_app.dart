import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../features/shell/presentation/app_shell.dart';

class RouteStoryApp extends StatelessWidget {
  const RouteStoryApp({super.key, this.overrides = const []});
  final List<dynamic> overrides;
  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: overrides.cast(),
    child: MaterialApp(
      title: 'RouteStory',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const AppShell(),
    ),
  );
}
