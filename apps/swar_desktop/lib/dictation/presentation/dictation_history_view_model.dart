import 'package:flutter/foundation.dart';
import 'package:swar_desktop/dictation/domain/dictation_history_repository.dart';
import 'package:swar_desktop/dictation/domain/dictation_record.dart';

final class DictationHistoryViewModel extends ChangeNotifier {
  DictationHistoryViewModel({required DictationHistoryRepository repository})
    : _repository = repository;

  static const pageSize = 50;
  final DictationHistoryRepository _repository;
  DictationQuery _query = const DictationQuery();
  List<DictationRecord> _records = const [];
  int _totalCount = 0;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _errorMessage;
  int _loadGeneration = 0;

  DictationQuery get query => _query;
  List<DictationRecord> get records => _records;
  int get totalCount => _totalCount;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _records.length < _totalCount;
  String? get errorMessage => _errorMessage;

  Future<void> load() => _reload(showLoading: true);

  /// Refreshes the first page after a completed dictation without replacing
  /// the current feed with a full-page loading state.
  Future<void> refresh() => _reload(showLoading: false);

  Future<void> _reload({required bool showLoading}) async {
    final generation = ++_loadGeneration;
    if (showLoading) _isLoading = true;
    _errorMessage = null;
    if (showLoading) notifyListeners();
    try {
      final page = await _repository.loadPage(
        _query,
        offset: 0,
        limit: pageSize,
      );
      if (generation != _loadGeneration) return;
      _records = page.records;
      _totalCount = page.totalCount;
    } catch (_) {
      if (generation != _loadGeneration) return;
      if (showLoading) {
        _records = const [];
        _totalCount = 0;
      }
      _errorMessage = 'Swar could not load your local dictation history.';
    } finally {
      if (generation == _loadGeneration) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> search(String value) async {
    _query = _query.copyWith(searchText: value);
    await load();
  }

  Future<void> loadMore() async {
    if (_isLoading || _isLoadingMore || !hasMore) return;
    _isLoadingMore = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final page = await _repository.loadPage(
        _query,
        offset: _records.length,
        limit: pageSize,
      );
      _records = [..._records, ...page.records];
      _totalCount = page.totalCount;
    } catch (_) {
      _errorMessage = 'Swar could not load more local activity.';
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }
}
