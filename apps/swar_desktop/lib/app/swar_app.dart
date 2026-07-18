// apps/swar_desktop/lib/app/swar_app.dart

import 'package:flutter/material.dart';
import 'package:swar_desktop/design_system/swar_theme.dart';
import 'package:swar_desktop/diagnostics/domain/core_diagnostics_gateway.dart';
import 'package:swar_desktop/diagnostics/presentation/core_diagnostics_page.dart';

/// Application root. Presentation Layer.
class SwarApp extends StatelessWidget {
  const SwarApp({required this.diagnosticsGateway, super.key});

  final CoreDiagnosticsGateway diagnosticsGateway;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'swar',
      theme: SwarTheme.light(),
      home: CoreDiagnosticsPage(gateway: diagnosticsGateway),
    );
  }
}
