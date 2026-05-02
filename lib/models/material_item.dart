class MaterialItem {
  final String id;
  String name;
  String category;
  String unitType;
  double price;
  double? width; // largeur/laize en cm (pour tissus)
  String color;
  String supplier;
  String notes;
  DateTime createdAt;
  DateTime updatedAt;

  MaterialItem({
    required this.id,
    required this.name,
    required this.category,
    required this.unitType,
    required this.price,
    this.width,
    this.color = '',
    this.supplier = '',
    this.notes = '',
    required this.createdAt,
    required this.updatedAt,
  });

  factory MaterialItem.fromJson(Map<String, dynamic> json) => MaterialItem(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        category: json['category']?.toString() ?? '',
        unitType: json['unitType']?.toString() ?? 'metre',
        price: (json['price'] as num? ?? 0).toDouble(),
        width: json['width'] != null ? (json['width'] as num).toDouble() : null,
        color: json['color']?.toString() ?? '',
        supplier: json['supplier']?.toString() ?? '',
        notes: json['notes']?.toString() ?? '',
        createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'unitType': unitType,
        'price': price,
        'width': width,
        'color': color,
        'supplier': supplier,
        'notes': notes,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  static const List<String> categories = [
    'Tissu', 'Fil', 'Bouton', 'Fermeture éclair', 'Élastique',
    'Ruban', 'Biais', 'Dentelle', 'Doublure', 'Entoilage',
    'Patron', 'Accessoire', 'Autre',
  ];

  static const Map<String, String> unitLabels = {
    'metre': '€ / m',
    'metre3': '€ / 3m',
    'unite': '€ / unité',
    'lot': '€ / lot',
    'rouleau': '€ / rouleau',
    'kg': '€ / kg',
  };

  String get unitLabel => unitLabels[unitType] ?? unitType;
}
