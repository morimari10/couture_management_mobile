class DepotSale {
  final String id;
  String date;
  String? productId;
  String productName;
  double qty;
  double unitPrice;
  double unitCost;
  DateTime createdAt;
  DateTime updatedAt;

  DepotSale({
    required this.id,
    required this.date,
    this.productId,
    required this.productName,
    required this.qty,
    required this.unitPrice,
    required this.unitCost,
    required this.createdAt,
    required this.updatedAt,
  });

  double get total => qty * unitPrice;
  double get totalCost => qty * unitCost;
  String get monthKey => date.length >= 7 ? date.substring(0, 7) : date;

  factory DepotSale.fromJson(Map<String, dynamic> json) => DepotSale(
        id: json['id'] as String,
        date: json['date'] as String? ?? '',
        productId: (json['productId'] as String?)?.isNotEmpty == true ? json['productId'] as String : null,
        productName: json['productName'] as String? ?? '',
        qty: (json['qty'] as num? ?? 1).toDouble(),
        unitPrice: (json['unitPrice'] as num? ?? 0).toDouble(),
        unitCost: (json['unitCost'] as num? ?? 0).toDouble(),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'productId': productId ?? '',
        'productName': productName,
        'qty': qty,
        'unitPrice': unitPrice,
        'unitCost': unitCost,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };
}

/// Paramètres du dépôt-vente (identiques à la version web).
class DepotConfig {
  static const shopName = 'Le Comptoir des Créateurs';
  static const startMonth = '2026-11';
  static const monthlyRent = 108.0;
  static const commissionRate = 20.0;
}

/// CA → commission boutique → impôts sur le reste → loyer → prix de revient matière
class DepotMonthSummary {
  final double revenue;
  final double commission;
  final double afterCommission;
  final double taxes;
  final double rent;
  final double materialCost;
  final double profit;
  final double itemsSold;

  DepotMonthSummary._(this.revenue, this.commission, this.afterCommission, this.taxes, this.rent,
      this.materialCost, this.profit, this.itemsSold);

  factory DepotMonthSummary.compute(List<DepotSale> sales, double taxRate, {double rent = DepotConfig.monthlyRent}) {
    final revenue = sales.fold<double>(0, (s, v) => s + v.total);
    final commission = revenue * DepotConfig.commissionRate / 100;
    final afterCommission = revenue - commission;
    final taxes = afterCommission * taxRate / 100;
    final materialCost = sales.fold<double>(0, (s, v) => s + v.totalCost);
    final itemsSold = sales.fold<double>(0, (s, v) => s + v.qty);
    return DepotMonthSummary._(revenue, commission, afterCommission, taxes, rent, materialCost,
        afterCommission - taxes - rent - materialCost, itemsSold);
  }
}
