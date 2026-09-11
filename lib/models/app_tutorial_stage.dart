enum AppTutorialStage { profile, search, hotMusic, player }

// Nach der Gerätefreigabe des vollständigen Tutorials dauerhaft aktiviert.
// Ein normaler Erstlauf wird damit nach Abschluss oder globalem Überspringen
// nicht erneut automatisch gestartet. Eine manuelle Wiederholung ist davon
// getrennt und verändert den gespeicherten Abschlussstatus nicht.
const bool tutorialCompletionPersistenceEnabled = true;

extension AppTutorialStageStorage on AppTutorialStage {
  String get storageKey => name;

  static AppTutorialStage? fromStorageKey(Object? value) {
    if (value is! String) {
      return null;
    }
    for (final stage in AppTutorialStage.values) {
      if (stage.storageKey == value) {
        return stage;
      }
    }
    return null;
  }
}
