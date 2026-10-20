class Alert {
  const Alert({required this.message, required this.severity});

  final String message;
  final String severity;

  factory Alert.fromJson(Map<String, dynamic> json) => Alert(
    message: (json['message'] as String?) ?? '',
    severity: (json['severity'] as String?) ?? 'warning',
  );
}