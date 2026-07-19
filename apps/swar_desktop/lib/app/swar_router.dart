// apps/swar_desktop/lib/app/swar_router.dart

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:swar_desktop/app/swar_routes.dart';
import 'package:swar_desktop/app/swar_shell.dart';
import 'package:swar_desktop/diagnostics/domain/core_diagnostics_gateway.dart';
import 'package:swar_desktop/dictation/domain/dictation_history_repository.dart';
import 'package:swar_desktop/dictation/presentation/dictation_page.dart';
import 'package:swar_desktop/dictation/presentation/dictation_session_view_model.dart';
import 'package:swar_desktop/insights/presentation/insights_page.dart';
import 'package:swar_desktop/insights/domain/insights_repository.dart';
import 'package:swar_desktop/settings/presentation/settings_page.dart';
import 'package:swar_desktop/settings/presentation/settings_view_model.dart';
import 'package:swar_desktop/settings/presentation/personalization_view_model.dart';

/// Router Composition. Application Layer.
///
/// Branch order is fixed: 0 Insights, 1 Activity (dictation), 2 Settings. The
/// shell's nav pill maps those indices to the spec's visual order.
GoRouter createSwarRouter({
  required DictationHistoryRepository dictationRepository,
  required InsightsRepository insightsRepository,
  required SettingsViewModel settingsViewModel,
  required CoreDiagnosticsGateway diagnosticsGateway,
  required DictationSessionViewModel dictationSessionViewModel,
  required PersonalizationViewModel personalizationViewModel,
}) {
  return GoRouter(
    initialLocation: SwarRoutes.insights,
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return SwarShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: SwarRoutes.insights,
                builder: (context, state) =>
                    InsightsPage(repository: insightsRepository),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: SwarRoutes.dictation,
                builder: (context, state) {
                  return DictationPage(
                    repository: dictationRepository,
                    sessionViewModel: dictationSessionViewModel,
                    settingsViewModel: settingsViewModel,
                  );
                },
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: SwarRoutes.settings,
                builder: (context, state) {
                  return SwarSettingsPage(
                    viewModel: settingsViewModel,
                    diagnosticsGateway: diagnosticsGateway,
                    dictationSessionViewModel: dictationSessionViewModel,
                    personalizationViewModel: personalizationViewModel,
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
