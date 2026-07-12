import 'package:flutter_test/flutter_test.dart';
import 'package:nakul_app/shell/shell_input_state.dart';

void main() {
  late ShellInputController controller;

  setUp(() {
    controller = ShellInputController();
  });

  tearDown(() {
    controller.dispose();
  });

  test('starts in the idle voice dock', () {
    expect(controller.state.mode, ShellInputMode.voice);
    expect(controller.state.phase, ShellInputPhase.idle);
    expect(controller.state.showVoiceFocus, isFalse);
  });

  test('typing follows focused, filled, sending, and complete states', () {
    controller.openTyping();
    expect(controller.state.phase, ShellInputPhase.focused);
    expect(controller.state.canSubmit, isFalse);

    controller.updateText('What is the weather?');
    expect(controller.state.phase, ShellInputPhase.filled);
    expect(controller.state.canSubmit, isTrue);

    expect(controller.beginSending(), isTrue);
    expect(controller.state.phase, ShellInputPhase.sending);
    expect(controller.state.canSubmit, isFalse);

    // TextEditingController.clear() fires while the request is being sent.
    controller.updateText('');
    expect(controller.state.phase, ShellInputPhase.sending);

    controller.completeSending();
    expect(controller.state.mode, ShellInputMode.voice);
    expect(controller.state.phase, ShellInputPhase.idle);
  });

  test('empty typing input cannot be submitted', () {
    controller.openTyping();
    controller.updateText('   ');

    expect(controller.beginSending(), isFalse);
    expect(controller.state.phase, ShellInputPhase.focused);

    controller.updateFocus(false);
    expect(controller.state.phase, ShellInputPhase.empty);
  });

  test('voice follows listening, transcribing, slow, and cancel states', () {
    controller.startListening();
    expect(controller.state.isListening, isTrue);
    expect(controller.state.showVoiceFocus, isTrue);

    controller.beginTranscribing();
    expect(controller.state.isTranscribing, isTrue);
    expect(controller.state.phase, ShellInputPhase.transcribing);

    controller.markTranscriptionSlow();
    expect(controller.state.phase, ShellInputPhase.transcriptionSlow);
    expect(controller.state.announcement, contains('longer'));

    controller.cancelVoice();
    expect(controller.state.phase, ShellInputPhase.idle);
    expect(controller.state.showVoiceFocus, isFalse);
  });

  test('voice failures map to distinct review states and remain retryable', () {
    const cases = {
      ShellInputIssue.permissionDenied: ShellInputPhase.permissionDenied,
      ShellInputIssue.noSpeech: ShellInputPhase.noSpeech,
      ShellInputIssue.timeout: ShellInputPhase.timeout,
      ShellInputIssue.network: ShellInputPhase.error,
      ShellInputIssue.unknown: ShellInputPhase.error,
    };

    for (final entry in cases.entries) {
      controller.failVoice(entry.key);
      expect(controller.state.phase, entry.value);
      expect(controller.state.issue, entry.key);
      expect(controller.state.isFailure, isTrue);
      expect(controller.state.showVoiceFocus, isTrue);

      // The UI's retry action starts a fresh recording attempt.
      controller.startListening();
      expect(controller.state.phase, ShellInputPhase.listening);
      expect(controller.state.issue, ShellInputIssue.none);
    }
  });

  test('slow status cannot overwrite a newer failure', () {
    controller.beginTranscribing();
    controller.failVoice(ShellInputIssue.network);
    controller.markTranscriptionSlow();

    expect(controller.state.phase, ShellInputPhase.error);
    expect(controller.state.issue, ShellInputIssue.network);
  });

  test('typed send failure preserves the question for retry', () {
    controller.openTyping();
    controller.updateText('Try this again');
    controller.beginSending();
    controller.failTyping();

    expect(controller.state.mode, ShellInputMode.typing);
    expect(controller.state.phase, ShellInputPhase.typingError);
    expect(controller.state.text, 'Try this again');
    expect(controller.state.canSubmit, isTrue);
    expect(controller.state.announcement, 'Question could not be sent');
  });
}
