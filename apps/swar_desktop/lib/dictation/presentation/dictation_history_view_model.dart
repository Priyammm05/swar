import 'package:flutter/foundation.dart';
import 'package:swar_desktop/dictation/domain/dictation_history_repository.dart';
import 'package:swar_desktop/dictation/domain/dictation_record.dart';

final class DictationHistoryViewModel extends ChangeNotifier {
  DictationHistoryViewModel({required DictationHistoryRepository repository})
    : _repository = repository;

  /// How many records one fetch pulls out of the local database.
  static const pageSize = 50;

  /// How many of the newest day's records are shown before it asks.
  static const todayInitialCount = 50;

  /// How many of an earlier day's records are shown before it asks. Older days
  /// are usually being skimmed rather than read, so they start short.
  static const earlierDayInitialCount = 20;

  /// How many more a "show more" reveals, whichever day it belongs to.
  static const revealStep = 50;

  final DictationHistoryRepository _repository;
  DictationQuery _query = const DictationQuery();
  List<DictationRecord> _records = const [];

  /// How many records each day has been asked to show, keyed by day. Absent
  /// means the day is still at its initial count.
  final Map<String, int> _revealedByDay = <String, int>{};
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

  /// How many records the day identified by [dayKey] should show right now.
  ///
  /// [isNewest] selects the starting count: the day at the top of the feed is
  /// the one being read, so it starts at 50, while an earlier day starts at 20.
  int revealedCountFor(String dayKey, {required bool isNewest}) =>
      _revealedByDay[dayKey] ??
      (isNewest ? todayInitialCount : earlierDayInitialCount);

  /// Reveals another [revealStep] records within one day.
  ///
  /// Purely a display concern; it never touches the database. Fetching more
  /// rows is [loadMore]'s job, and the page calls both when a day runs past
  /// what has been loaded.
  void revealMoreInDay(String dayKey, {required bool isNewest}) {
    _revealedByDay[dayKey] =
        revealedCountFor(dayKey, isNewest: isNewest) + revealStep;
    notifyListeners();
  }

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
    // A new search is a new feed, so days start collapsed again. `refresh`
    // deliberately does not do this: it runs after every dictation, and
    // collapsing what someone had just expanded would be maddening.
    _revealedByDay.clear();
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

  Future<bool> correct(
    DictationRecord record,
    String correctedText, {
    required bool learningOptedIn,
  }) async {
    final changed = await _repository.correctDictation(
      id: record.id,
      correctedText: correctedText,
      learningOptedIn: learningOptedIn,
    );
    if (changed) await refresh();
    return changed;
  }
}
