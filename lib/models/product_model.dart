class ProductMaterialLine {
  String materialId;
  String name;
  double quantity;
  String unitType;
  double costPerUnit;
  double lineCost;
  String qtyMode;
  String dimW;
  String dimH;
  String lenCm;
  String countPieces;

  ProductMaterialLine({
    required this.materialId,
    required this.name,
    required this.quantity,
    required this.unitType,
    required this.costPerUnit,
    required this.lineCost,
    this.qtyMode = 'normal',
    this.dimW = '',
    this.dimH = '',
    this.lenCm = '',
    this.countPieces = '1',
  });

  factory ProductMaterialLine.fromJson(Map<String, dynamic> json) {
    final dimW = json['dimW']?.toString() ?? '';
    final dimH = json['dimH']?.toString() ?? '';
    final lenCm = json['lenCm']?.toString() ?? '';
    final savedQtyMode = json['qtyMode']?.toString() ?? '';
    final qtyMode = savedQtyMode.isNotEmpty
        ? savedQtyMode
        : (dimW.isNotEmpty && dimH.isNotEmpty
            ? 'dim'
            : lenCm.isNotEmpty
                ? 'len'
                : 'normal');
    return ProductMaterialLine(
      materialId: json['materialId'] as String,
      name: json['name']?.toString() ?? '',
      quantity: _toDouble(json['quantity']),
      unitType: json['unitType'] as String? ?? 'metre',
      costPerUnit: _toDouble(json['costPerUnit']),
      lineCost: _toDouble(json['lineCost']),
      qtyMode: qtyMode,
      dimW: dimW,
      dimH: dimH,
      lenCm: lenCm,
      countPieces: json['countPieces']?.toString() ?? '1',
    );
  }

  Map<String, dynamic> toJson() => {
    'materialId': materialId,
    'name': name,
    'quantity': quantity,
    'unitType': unitType,
    'costPerUnit': costPerUnit,
    'lineCost': lineCost,
    'qtyMode': qtyMode,
    'dimW': dimW,
    'dimH': dimH,
    'lenCm': lenCm,
    'countPieces': countPieces,
  };
}

double _toDouble(dynamic value, {double defaultValue = 0.0}) {
  if (value == null) return defaultValue;

  if (value is num) return value.toDouble();

  final str = value.toString().trim();
  if (str.isEmpty || str.toLowerCase() == 'null') return defaultValue;

  return double.parse(str.replaceAll(',', '.'));
}

class ProductModel {
  final String id;
  String name;
  String? collectionId;
  List<ProductMaterialLine> materials;
  double totalCost;
  double? sellingPrice;
  double? laborHours;
  String notes;
  DateTime createdAt;
  DateTime updatedAt;

  ProductModel({
    required this.id,
    required this.name,
    this.collectionId,
    required this.materials,
    required this.totalCost,
    this.sellingPrice,
    this.laborHours,
    this.notes = '',
    required this.createdAt,
    required this.updatedAt,
  });

  factory ProductModel.fromJson(Map<String, dynamic> json) => ProductModel(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? 'Sans nom',
    collectionId:
        json['collectionId'] is String &&
            (json['collectionId'] as String).isNotEmpty
        ? json['collectionId'] as String
        : null,
    materials: _parseMaterials(json),
    totalCost: (json['totalCost'] as num? ?? 0).toDouble(),
    sellingPrice: json['sellingPrice'] != null
        ? (json['sellingPrice'] as num).toDouble()
        : null,
    laborHours: json['laborHours'] != null
        ? (json['laborHours'] as num).toDouble()
        : null,
    notes: json['notes']?.toString() ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
        DateTime.now(),
    updatedAt:
        DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
        DateTime.now(),
  );

  // Handles both Flutter format ('materials' key with full data)
  // and React format ('materials' key with materialId+quantity only)
  static List<ProductMaterialLine> _parseMaterials(Map<String, dynamic> json) {
    final mats = json['materials'] as List<dynamic>?;
    print('Parsing materials for product ${json['id']}: $mats');
    if (mats != null && mats.isNotEmpty) {
      return mats
          .whereType<Map<String, dynamic>>()
          .map((m) => ProductMaterialLine.fromJson(m))
          .toList();
    }
    // React-saved format: materials with only materialId + quantity + optional dimensions
    final comps = json['materials'] as List<dynamic>?;
    if (comps != null) {
      return comps
          .whereType<Map<String, dynamic>>()
          .where((comp) => (comp['materialId']?.toString() ?? '').isNotEmpty)
          .map((comp) {
            final dimW = comp['dimW']?.toString() ?? '';
            final dimH = comp['dimH']?.toString() ?? '';
            final lenCm = comp['lenCm']?.toString() ?? '';
            final countPieces = comp['countPieces']?.toString() ?? '1';
            final qtyMode = dimW.isNotEmpty && dimH.isNotEmpty
                ? 'dim'
                : lenCm.isNotEmpty
                ? 'len'
                : 'normal';
            return ProductMaterialLine(
              materialId: comp['materialId'] as String,
              name: '', // resolved in _resolveProductMaterials()
              quantity:
                  double.tryParse(comp['quantity']?.toString() ?? '0') ?? 0,
              unitType: 'metre',
              costPerUnit: 0,
              lineCost: 0,
              qtyMode: qtyMode,
              dimW: dimW,
              dimH: dimH,
              lenCm: lenCm,
              countPieces: countPieces,
            );
          })
          .toList();
    }
    return [];
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'collectionId': collectionId,
    'materials': materials.map((m) => m.toJson()).toList(),
    'totalCost': totalCost,
    'sellingPrice': sellingPrice,
    'laborHours': laborHours,
    'notes': notes,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}
