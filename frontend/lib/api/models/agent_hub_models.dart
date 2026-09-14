enum AlertLevel { green, yellow, orange, red }

extension AlertLevelX on AlertLevel {
  String get wire => switch (this) {
        AlertLevel.green => 'green',
        AlertLevel.yellow => 'yellow',
        AlertLevel.orange => 'orange',
        AlertLevel.red => 'red',
      };

  String get label => switch (this) {
        AlertLevel.green => 'Normal',
        AlertLevel.yellow => 'Watch',
        AlertLevel.orange => 'Warning',
        AlertLevel.red => 'Critical',
      };

  static AlertLevel fromWire(String value) => switch (value) {
        'yellow' => AlertLevel.yellow,
        'orange' => AlertLevel.orange,
        'red' => AlertLevel.red,
        _ => AlertLevel.green,
      };
}

class AgentExecutionStep {
  final String agentName;
  final String action;
  final String finding;
  final DateTime timestamp;

  const AgentExecutionStep({
    required this.agentName,
    required this.action,
    required this.finding,
    required this.timestamp,
  });

  factory AgentExecutionStep.fromJson(Map<String, dynamic> json) => AgentExecutionStep(
        agentName: json['agent_name'] as String,
        action: json['action'] as String,
        finding: json['finding'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
      );
}

class AgentHubResponse {
  final String district;
  final List<AgentExecutionStep> executionChain;
  final String coordinatorSummary;
  final AlertLevel alertLevel;

  const AgentHubResponse({
    required this.district,
    required this.executionChain,
    required this.coordinatorSummary,
    required this.alertLevel,
  });

  factory AgentHubResponse.fromJson(Map<String, dynamic> json) => AgentHubResponse(
        district: json['district'] as String,
        coordinatorSummary: json['coordinator_summary'] as String,
        alertLevel: AlertLevelX.fromWire(json['alert_level'] as String),
        executionChain: (json['execution_chain'] as List)
            .map((e) => AgentExecutionStep.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
