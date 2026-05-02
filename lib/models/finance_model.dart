class FinanceOrder {
  final String id;
  String date;
  String supplier;
  String description;
  double amount;
  String invoiceKey;
  String invoiceName;
  DateTime createdAt;
  DateTime updatedAt;

  FinanceOrder({
    required this.id,
    required this.date,
    this.supplier = '',
    this.description = '',
    required this.amount,
    this.invoiceKey = '',
    this.invoiceName = '',
    required this.createdAt,
    required this.updatedAt,
  });

  factory FinanceOrder.fromJson(Map<String, dynamic> json) => FinanceOrder(
        id: json['id'] as String,
        date: json['date'] as String,
        supplier: json['supplier'] as String? ?? '',
        description: json['description'] as String? ?? '',
        amount: (json['amount'] as num? ?? 0).toDouble(),
        invoiceKey: json['invoiceKey'] as String? ?? '',
        invoiceName: json['invoiceName'] as String? ?? '',
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'supplier': supplier,
        'description': description,
        'amount': amount,
        'invoiceKey': invoiceKey,
        'invoiceName': invoiceName,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };
}

class FinanceSale {
  final String id;
  String date;
  String? productId;
  String productName;
  double qty;
  double unitPrice;
  double total;
  DateTime createdAt;
  DateTime updatedAt;

  FinanceSale({
    required this.id,
    required this.date,
    this.productId,
    required this.productName,
    required this.qty,
    required this.unitPrice,
    required this.total,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FinanceSale.fromJson(Map<String, dynamic> json) => FinanceSale(
        id: json['id'] as String,
        date: json['date'] as String,
        productId: json['productId'] as String?,
        productName: json['productName'] as String? ?? '',
        qty: (json['qty'] as num? ?? 1).toDouble(),
        unitPrice: (json['unitPrice'] as num? ?? 0).toDouble(),
        total: (json['total'] as num? ?? 0).toDouble(),
        createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'date': date,
        'productId': productId,
        'productName': productName,
        'qty': qty,
        'unitPrice': unitPrice,
        'total': total,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };
}
