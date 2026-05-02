class CalendarEvent {
  final String id;
  String name;
  String type; // 'marche' | 'rdv'
  String date; // YYYY-MM-DD
  String endDate;
  String location;
  String notes;
  DateTime createdAt;
  DateTime updatedAt;

  CalendarEvent({
    required this.id,
    required this.name,
    required this.type,
    required this.date,
    this.endDate = '',
    this.location = '',
    this.notes = '',
    required this.createdAt,
    required this.updatedAt,
  });

  factory CalendarEvent.fromJson(Map<String, dynamic> json) => CalendarEvent(
        id: json['id'] as String,
        name: json['name'] as String,
        type: json['type'] as String? ?? 'marche',
        date: json['date'] as String,
        endDate: json['endDate'] as String? ?? '',
        location: json['location'] as String? ?? '',
        notes: json['notes'] as String? ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'date': date,
        'endDate': endDate,
        'location': location,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  DateTime get dateTime => DateTime.tryParse(date) ?? DateTime.now();
  DateTime? get endDateTime => endDate.isNotEmpty ? DateTime.tryParse(endDate) : null;
  bool get isMarche => type == 'marche';
}
