import 'package:flutter_test/flutter_test.dart';
import 'package:omarchy_wizard/models/agent_task.dart';
import 'package:omarchy_wizard/models/wizard_mood.dart';

void main() {
  test('AgentTask.fromJson parses bridge payload', () {
    final task = AgentTask.fromJson({
      'id': 'abc123',
      'prompt': 'Summarize git diff',
      'agent': 'agy',
      'mode': 'auto',
      'effort': 'high',
      'cwd': '/home/jgillman/Work',
      'status': 'completed',
      'created_at': '2026-11-13T16:00:00Z',
      'finished_at': '2026-11-13T16:00:05Z',
      'duration_seconds': 5.0,
      'exit_code': 0,
      'summary': 'All clean!',
      'conversation_id': 'conv-42',
      'events': [
        {
          'ts': '2026-11-13T16:00:02Z',
          'stream': 'stdout',
          'kind': 'assistant',
          'text': 'Checking git status...',
        }
      ],
    });

    expect(task.id, 'abc123');
    expect(task.status, TaskStatus.completed);
    expect(task.status.isTerminal, isTrue);
    expect(task.durationSeconds, 5.0);
    expect(task.conversationId, 'conv-42');
    expect(task.events.length, 1);
    expect(task.events.first.text, 'Checking git status...');
  });

  test('WizardMood exposes badge labels and quips', () {
    for (final mood in WizardMood.values) {
      expect(mood.badgeLabel, isNotEmpty);
      expect(mood.defaultQuip, isNotEmpty);
    }
  });
}
