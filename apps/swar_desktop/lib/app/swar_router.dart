// apps/swar_desktop/lib/app/swar_router.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:swar_desktop/app/swar_routes.dart';
import 'package:swar_desktop/app/swar_shell.dart';
import 'package:swar_desktop/diagnostics/domain/core_diagnostics_gateway.dart';
import 'package:swar_desktop/dictation/domain/dictation_history_repository.dart';
import 'package:swar_desktop/dictation/presentation/dictation_page.dart';
import 'package:swar_desktop/insights/presentation/insights_page.dart';
import 'package:swar_desktop/settings/presentation/settings_page.dart';
import 'package:swar_desktop/settings/presentation/settings_view_model.dart';

/// Router Composition. Application Layer.
GoRouter createSwarRouter({
  required DictationHistoryRepository dictationRepository,
  required SettingsViewModel settingsViewModel,
  required CoreDiagnosticsGateway diagnosticsGateway,
}) {
  return GoRouter(
    initialLocation: SwarRoutes.dictation,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return SwarShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: SwarRoutes.dictation,
                builder: (context, state) {
                  return DictationPage(repository: dictationRepository);
                },
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: SwarRoutes.insights,
                builder: (context, state) => const InsightsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: SwarRoutes.generalSettings,
                builder: (context, state) {
                  return SettingsPage(
                    section: SettingsSection.general,
                    viewModel: settingsViewModel,
                    diagnosticsGateway: diagnosticsGateway,
                  );
                },
              ),
              GoRoute(
                path: SwarRoutes.systemSettings,
                builder: (context, state) {
                  return SettingsPage(
                    section: SettingsSection.system,
                    viewModel: settingsViewModel,
                    diagnosticsGateway: diagnosticsGateway,
                  );
                },
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) {
      return Scaffold(
        body: Center(
          child: Text(
            'Swar could not open this page.',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      );
    },
  );
}
