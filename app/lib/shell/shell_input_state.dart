import 'package:flutter/foundation.dart';

/// The two input surfaces in the Nakul shell.
enum ShellInputMode { voice, typing }

/// Mutually exclusive phases used by the dock and the full-screen voice UI.
enum ShellInputPhase {
  idle,
  empty,
  focused,
  filled,
  sending,
  listening,
  transcribing,
  transcriptionSlow,
  permissionDenied,
  noSpeech,
  timeout,
  typingError,
  error,
}

/// Failure detail stays separate from [ShellInputPhase] so the UI can offer
/// one consistent retry path while still announcing a useful reason.
enum ShellInputIssue {
  none,
  permissionDenied,
  noSpeech,
  timeout,
  network,
  unknown,
}

@immutable
class ShellInputState {
  const ShellInputState({
    this.mode = ShellInputMode.voice,
    this.phase = ShellInputPhase.idle,
    this.issue = ShellInputIssue.none,
    this.text = '',
    this.hasFocus = false,
  });

  final ShellInputMode mode;
  final ShellInputPhase phase;
  final ShellInputIssue issue;
  final String text;
  final bool hasFocus;

  bool get isTyping => mode == ShellInputMode.typing;
  bool get isListening => phase == ShellInputPhase.listening;
  bool get isTranscribing =>
      phase == ShellInputPhase.transcribing ||
      phase == ShellInputPhase.transcriptionSlow;
  bool get isSending => phase == ShellInputPhase.sending;
  bool get isTypingError =>
      mode == ShellInputMode.typing && phase == ShellInputPhase.typingError;
  bool get isFailure => switch (phase) {
    ShellInputPhase.permissionDenied ||
    ShellInputPhase.noSpeech ||
    ShellInputPhase.timeout ||
    ShellInputPhase.typingError ||
    ShellInputPhase.error => true,
    _ => false,
  };

  bool get showVoiceFocus =>
      mode == ShellInputMode.voice && phase != ShellInputPhase.idle;

  bool get canSubmit =>
      isTyping && text.trim().isNotEmpty && phase != ShellInputPhase.sending;

  String get announcement => switch (phase) {
    ShellInputPhase.sending => 'Sending question',
    ShellInputPhase.listening => 'Listening',
    ShellInputPhase.transcribing => 'Transcribing your question',
    ShellInputPhase.transcriptionSlow =>
      'Transcription is taking longer than usual',
    ShellInputPhase.permissionDenied => 'Microphone permission is required',
    ShellInputPhase.noSpeech => 'No speech was detected',
    ShellInputPhase.timeout => 'Listening timed out',
    ShellInputPhase.typingError => 'Question could not be sent',
    ShellInputPhase.error => 'Voice input failed',
    _ => '',
  };

  ShellInputState copyWith({
    ShellInputMode? mode,
    ShellInputPhase? phase,
    ShellInputIssue? issue,
    String? text,
    bool? hasFocus,
  }) {
    return ShellInputState(
      mode: mode ?? this.mode,
      phase: phase ?? this.phase,
      issue: issue ?? this.issue,
      text: text ?? this.text,
      hasFocus: hasFocus ?? this.hasFocus,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShellInputState &&
          mode == other.mode &&
          phase == other.phase &&
          issue == other.issue &&
          text == other.text &&
          hasFocus == other.hasFocus;

  @override
  int get hashCode => Object.hash(mode, phase, issue, text, hasFocus);
}

/// Owns the shell transition rules independently from recording/network code.
/// This keeps impossible combinations (for example listening + typing) out of
/// the widget tree and makes every Figma state directly testable.
class ShellInputController extends ChangeNotifier {
  ShellInputState _state = const ShellInputState();

  ShellInputState get state => _state;

  void openTyping() {
    _set(
      _state.copyWith(
        mode: ShellInputMode.typing,
        phase: _state.text.trim().isEmpty
            ? ShellInputPhase.focused
            : ShellInputPhase.filled,
        issue: ShellInputIssue.none,
        hasFocus: true,
      ),
    );
  }

  void updateText(String text) {
    if (_state.phase == ShellInputPhase.sending) {
      _set(_state.copyWith(text: text));
      return;
    }
    if (!_state.isTyping) {
      _set(_state.copyWith(text: text));
      return;
    }
    _set(
      _state.copyWith(
        text: text,
        phase: text.trim().isNotEmpty
            ? ShellInputPhase.filled
            : _state.hasFocus
            ? ShellInputPhase.focused
            : ShellInputPhase.empty,
        issue: ShellInputIssue.none,
      ),
    );
  }

  void updateFocus(bool hasFocus) {
    if (!_state.isTyping || _state.phase == ShellInputPhase.sending) return;
    _set(
      _state.copyWith(
        hasFocus: hasFocus,
        phase: _state.text.trim().isNotEmpty
            ? ShellInputPhase.filled
            : hasFocus
            ? ShellInputPhase.focused
            : ShellInputPhase.empty,
      ),
    );
  }

  bool beginSending() {
    if (!_state.canSubmit) return false;
    _set(
      _state.copyWith(
        phase: ShellInputPhase.sending,
        issue: ShellInputIssue.none,
        hasFocus: false,
      ),
    );
    return true;
  }

  void completeSending() {
    _set(
      _state.copyWith(
        mode: ShellInputMode.voice,
        phase: ShellInputPhase.idle,
        issue: ShellInputIssue.none,
        hasFocus: false,
      ),
    );
  }

  void failTyping() {
    _set(
      _state.copyWith(
        mode: ShellInputMode.typing,
        phase: ShellInputPhase.typingError,
        issue: ShellInputIssue.network,
        hasFocus: false,
      ),
    );
  }

  void startListening() {
    _set(
      _state.copyWith(
        mode: ShellInputMode.voice,
        phase: ShellInputPhase.listening,
        issue: ShellInputIssue.none,
        hasFocus: false,
      ),
    );
  }

  void beginTranscribing() {
    _set(
      _state.copyWith(
        mode: ShellInputMode.voice,
        phase: ShellInputPhase.transcribing,
        issue: ShellInputIssue.none,
        hasFocus: false,
      ),
    );
  }

  void markTranscriptionSlow() {
    if (_state.phase != ShellInputPhase.transcribing) return;
    _set(_state.copyWith(phase: ShellInputPhase.transcriptionSlow));
  }

  void failVoice(ShellInputIssue issue) {
    assert(issue != ShellInputIssue.none);
    final phase = switch (issue) {
      ShellInputIssue.permissionDenied => ShellInputPhase.permissionDenied,
      ShellInputIssue.noSpeech => ShellInputPhase.noSpeech,
      ShellInputIssue.timeout => ShellInputPhase.timeout,
      ShellInputIssue.network ||
      ShellInputIssue.unknown => ShellInputPhase.error,
      ShellInputIssue.none => ShellInputPhase.error,
    };
    _set(
      _state.copyWith(
        mode: ShellInputMode.voice,
        phase: phase,
        issue: issue,
        hasFocus: false,
      ),
    );
  }

  void cancelVoice() {
    _set(
      _state.copyWith(
        mode: ShellInputMode.voice,
        phase: ShellInputPhase.idle,
        issue: ShellInputIssue.none,
        hasFocus: false,
      ),
    );
  }

  void _set(ShellInputState next) {
    if (next == _state) return;
    _state = next;
    notifyListeners();
  }
}
