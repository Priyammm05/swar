import 'package:flutter/foundation.dart';
import 'package:swar_desktop/settings/domain/personalization_repository.dart';

/// View model for local vocabulary and opt-in learning export actions.
final class PersonalizationViewModel extends ChangeNotifier {
  PersonalizationViewModel({required PersonalizationRepository repository})
    : _repository = repository;

  final PersonalizationRepository _repository;
  List<SwarVocabularyEntry> _entries = const [];
  bool _isLoading = false;
  String? _message;

  List<SwarVocabularyEntry> get entries => _entries;
  bool get isLoading => _isLoading;
  String? get message => _message;

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    try {
      _entries = await _repository.listVocabulary();
      _message = null;
    } catch (_) {
      _message = 'Swar could not load your local vocabulary.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> add(String spoken, String written) async {
    await _repository.addVocabulary(spoken.trim(), written.trim());
    await load();
  }

  Future<void> delete(String spoken) async {
    await _repository.deleteVocabulary(spoken);
    await load();
  }

  Future<void> export() async {
    try {
      final path = await _repository.exportLearningExamples();
      _message = 'Learning examples exported to $path';
    } catch (_) {
      _message = 'Swar could not export the learning examples.';
    }
    notifyListeners();
  }
}
