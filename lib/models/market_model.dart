/// Represents a single sale line during a market session.
class MarketSaleLine {
  final String productId;
  final String productName;
  final int quantity;
  final double unitPrice;

  MarketSaleLine({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
  });

  double get total => quantity * unitPrice;

  factory MarketSaleLine.fromJson(Map<String, dynamic> json) => MarketSaleLine(
        productId: json['productId'] as String,
        productName: json['productName']?.toString() ?? '',
        quantity: (json['quantity'] as num? ?? 0).toInt(),
        unitPrice: (json['unitPrice'] as num? ?? 0).toDouble(),
      );

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'productName': productName,
        'quantity': quantity,
        'unitPrice': unitPrice,
      };
}

/// A market session — can be active (ongoing) or finished.
class MarketModel {
  final String id;
  String name;
  String? location;
  DateTime startedAt;
  DateTime? endedAt;
  bool isActive;
  List<MarketSaleLine> sales;
  /// Snapshot of stock at the beginning of the market
  Map<String, int> initialStock;
  String notes;

  MarketModel({
    required this.id,
    required this.name,
    this.location,
    required this.startedAt,
    this.endedAt,
    this.isActive = true,
    required this.sales,
    required this.initialStock,
    this.notes = '',
  });

  int get totalArticlesSold => sales.fold(0, (s, l) => s + l.quantity);
  double get totalRevenue => sales.fold(0.0, (s, l) => s + l.total);
  int get uniqueProductsSold => sales.map((l) => l.productId).toSet().length;

  Duration get duration {
    final end = endedAt ?? DateTime.now();
    return end.difference(startedAt);
  }

  factory MarketModel.fromJson(Map<String, dynamic> json) => MarketModel(
        id: json['id'] as String,
        name: json['name']?.toString() ?? 'Marché',
        location: json['location']?.toString(),
        startedAt: DateTime.tryParse(json['startedAt']?.toString() ?? '') ?? DateTime.now(),
        endedAt: json['endedAt'] != null ? DateTime.tryParse(json['endedAt'].toString()) : null,
        isActive: json['isActive'] as bool? ?? false,
        sales: (json['sales'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map((e) => MarketSaleLine.fromJson(e))
            .toList(),
        initialStock: (json['initialStock'] as Map<String, dynamic>? ?? {})
            .map((k, v) => MapEntry(k, (v as num).toInt())),
        notes: json['notes']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'location': location,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt?.toIso8601String(),
        'isActive': isActive,
        'sales': sales.map((s) => s.toJson()).toList(),
        'initialStock': initialStock,
        'notes': notes,
      };
}
