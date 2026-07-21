import 'package:flutter/foundation.dart';
import 'package:swar_desktop/insights/domain/insights_repository.dart';
import 'package:swar_desktop/insights/domain/insights_snapshot.dart';

final class InsightsViewModel extends ChangeNotifier {
  InsightsViewModel({required InsightsRepository repository})
    : _repository = repository;

  final InsightsRepository _repository;
  SwarInsightsSnapshot _snapshot = const SwarInsightsSnapshot();
  bool _isLoading = false;
  String? _errorMessage;

  SwarInsightsSnapshot get snapshot => _snapshot;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _snapshot = await _repository.loadSnapshot();
    } catch (_) {
      _errorMessage = 'Swar could not load your local insights.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Reloads without announcing a loading state.
  ///
  /// Used when a dictation finishes while Insights is already on screen: the
  /// numbers should change in place. Going through [load] would blank the page
  /// the person is reading, and a failed background reload keeps the figures
  /// already shown rather than replacing them with an error.
  Future<void> refresh() async {
    final SwarInsightsSnapshot snapshot;
    try {
      snapshot = await _repository.loadSnapshot();
    } catch (_) {
      return;
    }
    _snapshot = snapshot;
    _errorMessage = null;
    notifyListeners();
  }
}
