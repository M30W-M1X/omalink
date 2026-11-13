enum WizardMood {
  idle,
  listening,
  casting,
  awaitingApproval,
  celebrating,
  error,
}

extension WizardMoodX on WizardMood {
  String get badgeLabel {
    switch (this) {
      case WizardMood.idle:
        return 'Meditating';
      case WizardMood.listening:
        return 'Ready to Cast';
      case WizardMood.casting:
        return 'Casting Spell';
      case WizardMood.awaitingApproval:
        return 'Needs Scroll Sign-Off';
      case WizardMood.celebrating:
        return 'Spell Complete!';
      case WizardMood.error:
        return 'Fizzled!';
    }
  }

  String get defaultQuip {
    switch (this) {
      case WizardMood.idle:
        return 'Arcane Agy is standing by on Omarchy ✨';
      case WizardMood.listening:
        return 'Whisper your task — I\'ll weave the code!';
      case WizardMood.casting:
        return 'Channeling runes through the terminal...';
      case WizardMood.awaitingApproval:
        return 'Scroll ready for your review, Archmage!';
      case WizardMood.celebrating:
        return 'Ta-da! Task completed cleanly! 🌟';
      case WizardMood.error:
        return 'Oops, a wild syntax gremlin appeared!';
    }
  }
}
