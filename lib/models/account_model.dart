class AccountEntry {
  static const typeIn = 'in';
  static const typeOut = 'out';

  final String id;
  String type;
  String date;
  String label;
  String party;
  double amount;
  String notes;
  String invoiceKey;
  String invoiceName;
  DateTime createdAt;
  DateTime updatedAt;

  AccountEntry({
    required this.id,
    required this.type,
    required this.date,
    required this.label,
    this.party = '',
    required this.amount,
    this.notes = '',
    this.invoiceKey = '',
    this.invoiceName = '',
    required this.createdAt,
    required this.updatedAt,
  });

  bool get isIn => type == typeIn;

  factory AccountEntry.fromJson(Map<String, dynamic> json) => AccountEntry(
        id: json['id'] as String,
        type: json['type'] as String? ?? typeOut,
        date: json['date'] as String? ?? '',
        label: json['label'] as String? ?? '',
        party: json['party'] as String? ?? '',
        amount: (json['amount'] as num? ?? 0).toDouble(),
        notes: json['notes'] as String? ?? '',
        invoiceKey: json['invoiceKey'] as String? ?? '',
        invoiceName: json['invoiceName'] as String? ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'date': date,
        'label': label,
        'party': party,
        'amount': amount,
        'notes': notes,
        'invoiceKey': invoiceKey,
        'invoiceName': invoiceName,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };
}
