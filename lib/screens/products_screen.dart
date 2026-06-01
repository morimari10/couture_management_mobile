import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/product_model.dart';
import '../models/material_item.dart';
import '../models/collection_model.dart';
import '../services/s3_service.dart';
import '../theme/app_theme.dart';

class ProductsScreen extends StatefulWidget {
  final void Function(int)? onNavigateTo;
  final VoidCallback? onProductsChanged;
  const ProductsScreen({super.key, this.onNavigateTo, this.onProductsChanged});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  List<ProductModel> _products = [];
  List<MaterialItem> _materials = [];
  List<CollectionModel> _collections = [];
  Map<String, dynamic> _settings = {
    'wastePct': 15,
    'machineCostPerH': 0.40,
    'urssafRate': 12,
    'incomeTaxRate': 30,
  };
  String _search = '';
  String? _filterCollectionId; // null = all
  bool _loading = true;
  String? _loadError;
  final _searchCtrl = TextEditingController();
  final Map<String, TextEditingController> _priceControllers = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    for (final c in _priceControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _loadError = null; });
    try {
      final s3 = S3Service();
      final results = await Future.wait([
        s3.loadData('couture_products'),
        s3.loadData('couture_materials'),
        s3.loadData('couture_collections'),
        s3.loadJson('couture_settings'),
      ]);
      if (!mounted) return;
      final settingsRaw = results[3];
      final rawProducts = (results[0] as List<dynamic>? ?? []);
      final rawMaterials = (results[1] as List<dynamic>? ?? []);
      final rawCollections = (results[2] as List<dynamic>? ?? []);
      setState(() {
        _products = rawProducts
            .whereType<Map<String, dynamic>>()
            .map((e) {
              try { return ProductModel.fromJson(e); }
              catch (err) { debugPrint('Product parse error: $err\n$e'); return null; }
            })
            .whereType<ProductModel>()
            .toList();
        _materials = rawMaterials
            .whereType<Map<String, dynamic>>()
            .map((e) {
              try { return MaterialItem.fromJson(e); }
              catch (err) { debugPrint('Material parse error: $err\n$e'); return null; }
            })
            .whereType<MaterialItem>()
            .toList();
        _collections = rawCollections
            .whereType<Map<String, dynamic>>()
            .map((e) {
              try { return CollectionModel.fromJson(e); }
              catch (err) { debugPrint('Collection parse error: $err\n$e'); return null; }
            })
            .whereType<CollectionModel>()
            .toList();
        if (settingsRaw is Map<String, dynamic>) {
          _settings = {..._settings, ...settingsRaw};
        }
        // Rebuild price controllers for new product IDs
        final currentIds = _products.map((p) => p.id).toSet();
        _priceControllers.removeWhere((id, ctrl) {
          if (!currentIds.contains(id)) { ctrl.dispose(); return true; }
          return false;
        });
        for (final p in _products) {
          if (!_priceControllers.containsKey(p.id)) {
            _priceControllers[p.id] = TextEditingController(
              text: p.sellingPrice != null && p.sellingPrice! > 0
                  ? p.sellingPrice!.toStringAsFixed(2)
                  : '');
          }
        }
        _resolveProductMaterials();
        _loading = false;
      });
    } catch (e, stack) {
      debugPrint('ProductsScreen._load error: $e\n$stack');
      if (mounted) setState(() { _loading = false; _loadError = e.toString(); });
    }
  }

  // Resolves React-format products (components with materialId only) into full MaterialLines
  void _resolveProductMaterials() {
    final matMap = {for (final m in _materials) m.id: m};
    for (final prod in _products) {
      if (prod.materials.isEmpty) continue;
      final needsResolution = prod.materials.any((m) => m.name.isEmpty);
      if (!needsResolution) continue;
      prod.materials = prod.materials.map((ml) {
        final mat = matMap[ml.materialId];
        if (mat == null) return null;
        final pricePerUnit = mat.unitType == 'metre3' ? mat.price / 3 : mat.price;
        return ProductMaterialLine(
          materialId: ml.materialId,
          name: mat.name,
          quantity: ml.quantity,
          unitType: mat.unitType,
          costPerUnit: pricePerUnit,
          lineCost: pricePerUnit * ml.quantity,
          qtyMode: ml.qtyMode,
          dimW: ml.dimW,
          dimH: ml.dimH,
          lenCm: ml.lenCm,
          countPieces: ml.countPieces,
        );
      }).whereType<ProductMaterialLine>().toList();
    }
  }

  Future<void> _duplicate(ProductModel prod) async {
    final copy = ProductModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: '${prod.name} (copie)',
      collectionId: prod.collectionId,
      materials: prod.materials.map((m) => ProductMaterialLine(
        materialId: m.materialId,
        name: m.name,
        quantity: m.quantity,
        unitType: m.unitType,
        costPerUnit: m.costPerUnit,
        lineCost: m.lineCost,
        qtyMode: m.qtyMode,
        dimW: m.dimW,
        dimH: m.dimH,
        lenCm: m.lenCm,
        countPieces: m.countPieces,
      )).toList(),
      totalCost: prod.totalCost,
      sellingPrice: prod.sellingPrice,
      laborHours: prod.laborHours,
      notes: prod.notes,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    setState(() {
      _priceControllers[copy.id] = TextEditingController(
        text: copy.sellingPrice != null && copy.sellingPrice! > 0
            ? copy.sellingPrice!.toStringAsFixed(2) : '');
      _products.insert(0, copy);
    });
    await _save();
    // Ouvre directement le formulaire pour modifier la copie
    _openForm(editing: copy);
  }

  Future<void> _save() async {
    await S3Service().saveData(
      'couture_products',
      _products.map((p) => p.toJson()).toList(),
    );
    widget.onProductsChanged?.call();
  }

  List<ProductModel> get _filtered {
    var list = _products.where((p) {
      if (_filterCollectionId != null && p.collectionId != _filterCollectionId) return false;
      if (_search.isNotEmpty && !p.name.toLowerCase().contains(_search.toLowerCase())) return false;
      return true;
    }).toList();
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  void _openForm({ProductModel? editing}) async {
    final result = await showModalBottomSheet<ProductModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _ProductForm(
        editing: editing,
        materials: _materials,
        collections: _collections,
      ),
    );
    if (result != null) {
      setState(() {
        if (editing != null) {
          final idx = _products.indexWhere((p) => p.id == editing.id);
          if (idx >= 0) _products[idx] = result;
          // Refresh the price controller to reflect edited price
          final newPrice = result.sellingPrice;
          _priceControllers[result.id]?.text = newPrice != null && newPrice > 0
              ? newPrice.toStringAsFixed(2) : '';
        } else {
          _products.insert(0, result);
          _priceControllers[result.id] = TextEditingController(
            text: result.sellingPrice != null && result.sellingPrice! > 0
                ? result.sellingPrice!.toStringAsFixed(2) : '');
        }
      });
      await _save();
    }
  }

  Future<void> _delete(ProductModel prod) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer ?'),
        content: Text('Supprimer "${prod.name}" ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() {
      _products.removeWhere((p) => p.id == prod.id);
      _priceControllers.remove(prod.id)?.dispose();
    });
    await _save();
  }

  Future<void> _updateSellingPrice(ProductModel prod, double price) async {
    final idx = _products.indexWhere((p) => p.id == prod.id);
    if (idx < 0) return;
    setState(() {
      _products[idx].sellingPrice = price;
      // Keep controller in sync so it doesn't reset on next rebuild
      _priceControllers[prod.id]?.text = price.toStringAsFixed(2);
    });
    await _save();
  }

  CollectionModel? _getCollection(String? id) =>
      id == null ? null : _collections.cast<CollectionModel?>().firstWhere((c) => c?.id == id, orElse: () => null);

  double get _wastePct => (_settings['wastePct'] as num? ?? 15).toDouble();
  double get _machCost => (_settings['machineCostPerH'] as num? ?? 0.40).toDouble();
  double get _urssaf => (_settings['urssafRate'] as num? ?? 12).toDouble();
  double get _ir => (_settings['incomeTaxRate'] as num? ?? 30).toDouble();
  double get _chargesRate => (_urssaf + _ir) / 100;

  double _costBase(ProductModel p) =>
      p.totalCost * (1 + _wastePct / 100) + (p.laborHours ?? 0) * _machCost;

  double _minPriceWithCharges(ProductModel p) {
    final base = _costBase(p);
    return _chargesRate >= 1 ? base : base / (1 - _chargesRate);
  }

  double? _profit(ProductModel p) {
    if (p.sellingPrice == null || p.sellingPrice! <= 0) return null;
    return p.sellingPrice! * (1 - _chargesRate) - _costBase(p);
  }

  double? _profitNaked(ProductModel p) {
    if (p.sellingPrice == null || p.sellingPrice! <= 0) return null;
    return p.sellingPrice! - _costBase(p);
  }

  String _unitLabel(String unitType) {
    switch (unitType) {
      case 'metre': return 'm';
      case 'metre3': return '× 3m';
      case 'unite': return 'u';
      case 'lot': return 'lot';
      case 'rouleau': return 'roul.';
      case 'kg': return 'kg';
      default: return unitType;
    }
  }

  String _formatQuantity(ProductMaterialLine ml) {
    if (ml.dimW.isNotEmpty && ml.dimH.isNotEmpty) {
      final prefix = (int.tryParse(ml.countPieces) ?? 1) > 1 ? '${ml.countPieces}× ' : '';
      return '$prefix${ml.dimW}×${ml.dimH}cm';
    }
    if (ml.lenCm.isNotEmpty) {
      final prefix = (int.tryParse(ml.countPieces) ?? 1) > 1 ? '${ml.countPieces}× ' : '';
      return '$prefix${ml.lenCm}cm';
    }
    return '${ml.quantity} ${_unitLabel(ml.unitType)}';
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      body: Column(
        children: [
          // Quick access — Collections & Stocks
          if (widget.onNavigateTo != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Expanded(child: _quickLink(Icons.folder_outlined, 'Collections', () => widget.onNavigateTo!(2))),
                  const SizedBox(width: 8),
                  Expanded(child: _quickLink(Icons.inventory_2_outlined, 'Stocks', () => widget.onNavigateTo!(4))),
                ],
              ),
            ),
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Rechercher un produit...',
                prefixIcon: const Icon(Icons.search, color: AppTheme.textLight),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () { _searchCtrl.clear(); setState(() => _search = ''); })
                    : null,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          // Collection filter chips
          if (_collections.isNotEmpty)
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                children: [
                  _filterChip('Toutes', null),
                  ..._collections.map((c) => _filterChip('${c.emoji} ${c.name}', c.id)),
                ],
              ),
            ),
          // List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
                : _loadError != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.cloud_off_outlined, size: 48, color: AppTheme.textLight),
                              const SizedBox(height: 12),
                              const Text('Impossible de charger les produits',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
                              const SizedBox(height: 16),
                              OutlinedButton.icon(
                                onPressed: _load,
                                icon: const Icon(Icons.refresh),
                                label: const Text('Réessayer'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : filtered.isEmpty
                        ? _emptyState()
                        : RefreshIndicator(
                            onRefresh: _load,
                            color: AppTheme.accent,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: filtered.length,
                              itemBuilder: (_, i) => _productCard(filtered[i]),
                            ),
                          ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Nouveau produit'),
      ),
    );
  }

  Widget _quickLink(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: AppTheme.primaryFaded,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.borderLight),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: AppTheme.primary),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.primaryDark)),
            const Spacer(),
            const Icon(Icons.arrow_forward_ios, size: 12, color: AppTheme.textLight),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String label, String? id) {
    final active = _filterCollectionId == id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label, style: TextStyle(fontSize: 12, color: active ? Colors.white : AppTheme.textSecondary)),
        selected: active,
        selectedColor: AppTheme.primary,
        backgroundColor: AppTheme.surface,
        side: BorderSide(color: active ? AppTheme.primary : AppTheme.borderLight),
        onSelected: (_) => setState(() => _filterCollectionId = id),
        showCheckmark: false,
      ),
    );
  }

  Widget _productCard(ProductModel prod) {
    final col = _getCollection(prod.collectionId);
    // Use the managed controller (never recreated on rebuild)
    final priceCtrl = _priceControllers[prod.id];
    final base = _costBase(prod);
    final matWaste = prod.totalCost * (1 + _wastePct / 100);
    final machineCost = (prod.laborHours ?? 0) * _machCost;
    final minWith = _minPriceWithCharges(prod);
    final minNaked = base; // prix min sans déclaration = costBase
    final profit = _profit(prod);
    final profitNaked = _profitNaked(prod);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(prod.name,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: AppTheme.primaryDark)),
                      if (col != null)
                        Text('${col.emoji} ${col.name}',
                            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${prod.totalCost.toStringAsFixed(2)} €',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: AppTheme.primary)),
                    const Text('coût mat.', style: TextStyle(fontSize: 10, color: AppTheme.textLight)),
                  ],
                ),
              ],
            ),
            // Materials list — tableau avec entête
            if (prod.materials.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.primaryFaded,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      child: Row(children: const [
                        Expanded(flex: 3, child: Text('MATIÈRE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.textSecondary, letterSpacing: 0.5))),
                        Expanded(flex: 2, child: Text('QTÉ', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.textSecondary, letterSpacing: 0.5))),
                        Expanded(flex: 1, child: Text('COÛT', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.textSecondary, letterSpacing: 0.5))),
                      ]),
                    ),
                    ...prod.materials.asMap().entries.map((e) {
                      final ml = e.value;
                      return Container(
                        decoration: BoxDecoration(
                          color: e.key.isEven ? Colors.transparent : AppTheme.surface.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        child: Row(children: [
                          Expanded(flex: 3, child: Text(ml.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textColor))),
                          Expanded(flex: 2, child: Text(_formatQuantity(ml), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary))),
                          Expanded(flex: 1, child: Text('${ml.lineCost.toStringAsFixed(2)} €', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primary))),
                        ]),
                      );
                    }),
                  ],
                ),
              ),
            ],
            // Price breakdown
            if (prod.totalCost > 0) ...[
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.borderLight, width: 1.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    _bdRow('🧵 Matières + pertes (${_wastePct.toInt()}%)', '${matWaste.toStringAsFixed(2)} €'),
                    if (machineCost > 0)
                      _bdRow('⚡ Machine (${prod.laborHours}h × $_machCost€)', '${machineCost.toStringAsFixed(2)} €'),
                    _bdRowTotal('Sous-total coûts', '${base.toStringAsFixed(2)} €'),
                    _bdRowHighlight('Prix min. avec charges (URSSAF ${_urssaf.toInt()}% + IR ${_ir.toInt()}%)', '${minWith.toStringAsFixed(2)} €', color: AppTheme.primaryDark),
                    _bdRowHighlight('Prix min. sans déclaration', '${minNaked.toStringAsFixed(2)} €', color: AppTheme.success),
                    // Suggestions ×2 / ×2.5 / ×3
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
                      child: Row(children: [
                        const Text('×', style: TextStyle(fontSize: 11, color: AppTheme.textLight)),
                        const SizedBox(width: 4),
                        ...[2.0, 2.5, 3.0].map((mult) {
                          final hi = mult == 2.5;
                          return Expanded(
                            child: Container(
                              margin: const EdgeInsets.only(left: 4),
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              decoration: BoxDecoration(
                                border: Border.all(color: hi ? AppTheme.primary : AppTheme.borderLight, width: 1.5),
                                borderRadius: BorderRadius.circular(6),
                                color: hi ? AppTheme.primaryFaded : Colors.transparent,
                              ),
                              child: Column(children: [
                                Text('×$mult', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: hi ? AppTheme.primary : AppTheme.textLight)),
                                Text('${(minWith * mult).toStringAsFixed(0)} €', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: hi ? AppTheme.primary : AppTheme.textColor)),
                              ]),
                            ),
                          );
                        }),
                      ]),
                    ),
                    // Prix de vente éditable
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: const BoxDecoration(
                        border: Border(top: BorderSide(color: AppTheme.borderLight)),
                      ),
                      child: Row(children: [
                        const Text('💰 Prix de vente', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
                        const Spacer(),
                        SizedBox(
                          width: 90,
                          child: priceCtrl == null
                              ? const SizedBox()
                              : Focus(
                            onFocusChange: (hasFocus) {
                              if (!hasFocus) {
                                final price = double.tryParse(priceCtrl.text);
                                if (price != null) _updateSellingPrice(prod, price);
                              }
                            },
                            child: TextField(
                            controller: priceCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primaryDark),
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              suffixText: ' €',
                            ),
                            onSubmitted: (v) {
                              final price = double.tryParse(v);
                              if (price != null) _updateSellingPrice(prod, price);
                            },
                          ),
                          ),
                        ),
                      ]),
                    ),
                    // Lignes bénéfice
                    if (profit != null) ...[
                      _profitRow('Bénéfice avec charges', profit),
                      _profitRow('Bénéfice sans déclaration', profitNaked!),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openForm(editing: prod),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Modifier'),
                    style: OutlinedButton.styleFrom(foregroundColor: AppTheme.primary, side: const BorderSide(color: AppTheme.borderLight)),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _duplicate(prod),
                    icon: const Icon(Icons.copy_outlined, size: 16),
                    label: const Text('Dupliquer'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.success,
                      side: const BorderSide(color: Color(0xFFDDEEDD)),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _delete(prod),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: const Text('Supprimer'),
                    style: OutlinedButton.styleFrom(foregroundColor: AppTheme.danger, side: const BorderSide(color: Color(0xFFFDE8E8))),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _bdRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary))),
          Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textColor)),
        ]),
      );

  Widget _bdRowTotal(String label, String value) => Container(
        color: AppTheme.primaryFaded,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppTheme.textSecondary))),
          Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primaryDark)),
        ]),
      );

  Widget _bdRowHighlight(String label, String value, {required Color color}) => Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [color.withValues(alpha: 0.10), color.withValues(alpha: 0.04)]),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color))),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        ]),
      );

  Widget _profitRow(String label, double value) => Container(
        decoration: BoxDecoration(
          color: value >= 0 ? const Color(0x1A27AE60) : const Color(0x14C0392B),
          border: Border(top: BorderSide(color: value >= 0 ? const Color(0x4D27AE60) : const Color(0x40C0392B))),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(children: [
          Expanded(child: Text(
            value >= 0 ? '✅ $label' : '⚠️ $label',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: value >= 0 ? AppTheme.success : AppTheme.danger),
          )),
          Text(
            '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)} €',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: value >= 0 ? AppTheme.success : AppTheme.danger),
          ),
        ]),
      );

  Widget _emptyState() => ListView(
        children: const [
          SizedBox(height: 80),
          Icon(Icons.shopping_bag_outlined, size: 72, color: AppTheme.borderLight),
          SizedBox(height: 16),
          Text('Aucun produit', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
          SizedBox(height: 8),
          Text('Créez votre premier produit en ajoutant des matières.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppTheme.textLight)),
        ],
      );
}

// ─── Product Form ───

class _ProductForm extends StatefulWidget {
  final ProductModel? editing;
  final List<MaterialItem> materials;
  final List<CollectionModel> collections;

  const _ProductForm({this.editing, required this.materials, required this.collections});

  @override
  State<_ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<_ProductForm> {
  final _formKey = GlobalKey<FormState>();
  late String _name;
  late final TextEditingController _nameCtrl;
  String? _collectionId;
  double? _laborHours;
  String _notes = '';
  List<_MatLine> _lines = [];

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _name = e?.name ?? '';
    _nameCtrl = TextEditingController(text: _name);
    _collectionId = e?.collectionId;
    _laborHours = e?.laborHours;
    _notes = e?.notes ?? '';
    _lines = e?.materials.map((ml) => _MatLine(
          materialId: ml.materialId,
          quantity: ml.quantity.toString(),
          qtyMode: ml.qtyMode,
          dimW: ml.dimW,
          dimH: ml.dimH,
          lenCm: ml.lenCm,
          countPieces: ml.countPieces,
        )).toList() ?? [];
    if (_lines.isEmpty) _lines.add(_MatLine());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    for (final line in _lines) {
      line.disposeControllers();
    }
    super.dispose();
  }

  double get _totalCost {
    double total = 0;
    for (final line in _lines) {
      final mat = widget.materials.firstWhere(
        (m) => m.id == line.materialId,
        orElse: () => MaterialItem(id: '', name: '', category: '', unitType: 'unite', price: 0, createdAt: DateTime.now(), updatedAt: DateTime.now()),
      );
      final qty = double.tryParse(line.quantity) ?? 0;
      final pricePerUnit = mat.unitType == 'metre3' ? mat.price / 3 : mat.price;
      total += pricePerUnit * qty;
    }
    return total;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    // Read name directly from controller to ensure we get the typed value
    _name = _nameCtrl.text.trim();

    final matLines = <ProductMaterialLine>[];
    for (final line in _lines) {
      if (line.materialId == null) continue;
      final mat = widget.materials.firstWhere((m) => m.id == line.materialId, orElse: () => MaterialItem(id: '', name: '', category: '', unitType: 'unite', price: 0, createdAt: DateTime.now(), updatedAt: DateTime.now()));
      if (mat.id.isEmpty) continue;
      final qty = double.tryParse(line.quantity) ?? 0;
      final pricePerUnit = mat.unitType == 'metre3' ? mat.price / 3 : mat.price;
      matLines.add(ProductMaterialLine(
        materialId: mat.id,
        name: mat.name,
        quantity: qty,
        unitType: mat.unitType,
        costPerUnit: pricePerUnit,
        lineCost: pricePerUnit * qty,
        qtyMode: line.qtyMode,
        dimW: line.dimW,
        dimH: line.dimH,
        lenCm: line.lenCm,
        countPieces: line.countPieces,
      ));
    }

    final now = DateTime.now();
    final product = ProductModel(
      id: widget.editing?.id ?? const Uuid().v4(),
      name: _name.trim(),
      collectionId: _collectionId,
      materials: matLines,
      totalCost: matLines.fold(0.0, (s, m) => s + m.lineCost),
      sellingPrice: widget.editing?.sellingPrice,
      laborHours: _laborHours,
      notes: _notes.trim(),
      createdAt: widget.editing?.createdAt ?? now,
      updatedAt: now,
    );
    Navigator.pop(context, product);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      maxChildSize: 0.95,
      builder: (_, ctrl) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Form(
          key: _formKey,
          child: ListView(
            controller: ctrl,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            children: [
              Text(
                widget.editing != null ? 'Modifier le produit' : 'Nouveau produit',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.primaryDark),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(labelText: 'Nom du produit *'),
                validator: (v) => v == null || v.trim().isEmpty ? 'Requis' : null,
                onSaved: (v) => _name = v ?? '',
              ),
              const SizedBox(height: 12),
              // Collection picker
              DropdownButtonFormField<String?>(
                initialValue: _collectionId,
                decoration: const InputDecoration(labelText: 'Collection'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('— Aucune —')),
                  ...widget.collections.map((c) => DropdownMenuItem(value: c.id, child: Text('${c.emoji} ${c.name}'))),
                ],
                onChanged: (v) => setState(() => _collectionId = v),
              ),
              const SizedBox(height: 16),
              // Materials section
              Row(
                children: [
                  const Text('Matières utilisées', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primaryDark)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [AppTheme.primary, AppTheme.primaryLight]),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Total: ${_totalCost.toStringAsFixed(2)} €',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ..._lines.asMap().entries.map((entry) {
                final i = entry.key;
                final line = entry.value;
                return _buildMatLine(i, line);
              }),
              TextButton.icon(
                onPressed: () => setState(() => _lines.add(_MatLine())),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Ajouter une matière'),
                style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: _laborHours?.toString() ?? '',
                decoration: const InputDecoration(labelText: 'Heures de travail', suffixText: 'h'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onSaved: (v) => _laborHours = double.tryParse(v ?? ''),
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: _notes,
                decoration: const InputDecoration(labelText: 'Notes'),
                maxLines: 2,
                onSaved: (v) => _notes = v ?? '',
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler'))),
                  const SizedBox(width: 12),
                  Expanded(child: ElevatedButton(onPressed: _submit, child: Text(widget.editing != null ? 'Modifier' : 'Créer'))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMatLine(int i, _MatLine line) {
    final mat = line.materialId != null
        ? widget.materials.cast<MaterialItem?>().firstWhere((m) => m?.id == line.materialId, orElse: () => null)
        : null;
    final qty = double.tryParse(line.quantity) ?? 0;
    final pricePerUnit = mat != null ? (mat.unitType == 'metre3' ? mat.price / 3 : mat.price) : 0.0;
    final lineCost = pricePerUnit * qty;
    final canDim = mat != null && (mat.unitType == 'metre' || mat.unitType == 'metre3');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.primaryFaded,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderLight),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String?>(
                  initialValue: line.materialId,
                  decoration: const InputDecoration(labelText: 'Matière', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('— Choisir —')),
                    ...widget.materials.map((m) => DropdownMenuItem(value: m.id, child: Text(m.name, style: const TextStyle(fontSize: 13)))),
                  ],
                  onChanged: (v) {
                    setState(() {
                      line.materialId = v;
                      // Reset dim mode if material doesn't support it
                      if (v != null) {
                        final newMat = widget.materials.cast<MaterialItem?>().firstWhere((m) => m?.id == v, orElse: () => null);
                        if (newMat != null && newMat.unitType != 'metre' && newMat.unitType != 'metre3') {
                          line.qtyMode = 'normal';
                          line.dimW = '';
                          line.dimH = '';
                          line.lenCm = '';
                        }
                      }
                    });
                  },
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '${lineCost.toStringAsFixed(2)}€',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.primary),
              ),
              const SizedBox(width: 4),
              if (_lines.length > 1)
                GestureDetector(
                  onTap: () {
                    final removed = _lines[i];
                    setState(() => _lines.removeAt(i));
                    removed.disposeControllers();
                  },
                  child: const Icon(Icons.close, size: 18, color: AppTheme.danger),
                ),
            ],
          ),
          const SizedBox(height: 6),
          // Quantity mode selector for fabrics
          if (canDim)
            Row(
              children: [
                _qtyModeChip('Qté', 'normal', line),
                const SizedBox(width: 6),
                _qtyModeChip('📐 L×l', 'dim', line),
                const SizedBox(width: 6),
                _qtyModeChip('📏 Long.', 'len', line),
              ],
            ),
          if (canDim) const SizedBox(height: 6),
          // Quantity input based on mode
          if (line.qtyMode == 'dim') ...[
            Row(
              children: [
                SizedBox(
                  width: 44,
                  child: TextField(
                    controller: line.countPiecesCtrl,
                    decoration: const InputDecoration(labelText: 'Nb', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6)),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => _updateDimQuantity(line, countPieces: v),
                  ),
                ),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 2), child: Text('×', style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textSecondary))),
                Expanded(
                  child: TextField(
                    controller: line.dimWCtrl,
                    decoration: const InputDecoration(labelText: 'Larg. cm', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6)),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (v) => _updateDimQuantity(line, dimW: v),
                  ),
                ),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 2), child: Text('×', style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textSecondary))),
                Expanded(
                  child: TextField(
                    controller: line.dimHCtrl,
                    decoration: const InputDecoration(labelText: 'Long. cm', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6)),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (v) => _updateDimQuantity(line, dimH: v),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '= ${qty.toStringAsFixed(3)} m',
                style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
            ),
          ] else if (line.qtyMode == 'len') ...[
            Row(
              children: [
                SizedBox(
                  width: 44,
                  child: TextField(
                    controller: line.countPiecesCtrl,
                    decoration: const InputDecoration(labelText: 'Nb', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6)),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => _updateLenQuantity(line, countPieces: v),
                  ),
                ),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 2), child: Text('×', style: TextStyle(fontWeight: FontWeight.w700, color: AppTheme.textSecondary))),
                Expanded(
                  child: TextField(
                    controller: line.lenCmCtrl,
                    decoration: const InputDecoration(labelText: 'Longueur (cm)', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 6)),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (v) => _updateLenQuantity(line, lenCm: v),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '= ${qty.toStringAsFixed(3)} m',
                style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
            ),
          ] else ...[
            SizedBox(
              width: double.infinity,
              child: TextField(
                controller: line.quantityCtrl,
                decoration: const InputDecoration(labelText: 'Quantité', isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (v) => setState(() => line.quantity = v),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _qtyModeChip(String label, String mode, _MatLine line) {
    final active = line.qtyMode == mode;
    return GestureDetector(
      onTap: () {
        setState(() {
          line.qtyMode = mode;
          line.dimW = '';
          line.dimH = '';
          line.lenCm = '';
          line.countPieces = '1';
          if (mode != 'normal') line.quantity = '';
          // Keep controllers in sync with reset values
          line.dimWCtrl.text = '';
          line.dimHCtrl.text = '';
          line.lenCmCtrl.text = '';
          line.countPiecesCtrl.text = '1';
          if (mode != 'normal') line.quantityCtrl.text = '';
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: active ? AppTheme.primary : AppTheme.borderLight, width: 1.5),
          color: active ? AppTheme.primaryFaded : Colors.white,
        ),
        child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: active ? AppTheme.primary : AppTheme.textSecondary)),
      ),
    );
  }

  void _updateDimQuantity(_MatLine line, {String? dimW, String? dimH, String? countPieces}) {
    setState(() {
      if (dimW != null) line.dimW = dimW;
      if (dimH != null) line.dimH = dimH;
      if (countPieces != null) line.countPieces = countPieces;
      final w = double.tryParse(line.dimW) ?? 0;
      final h = double.tryParse(line.dimH) ?? 0;
      final n = double.tryParse(line.countPieces) ?? 1;
      // Get material width for proper calculation
      final mat = line.materialId != null
          ? widget.materials.cast<MaterialItem?>().firstWhere((m) => m?.id == line.materialId, orElse: () => null)
          : null;
      final materialWidth = mat?.width ?? 0;
      if (w > 0 && h > 0) {
        if (materialWidth > 0) {
          // Proper calculation: linear meters = (n * dimW * dimH) / (materialWidth * 100)
          line.quantity = (n * w * h / (materialWidth * 100)).toStringAsFixed(4);
        } else {
          // Fallback without width: assume dimH is the length needed
          line.quantity = (n * w * h / 10000).toStringAsFixed(4);
        }
      } else {
        line.quantity = '';
      }
    });
  }

  void _updateLenQuantity(_MatLine line, {String? lenCm, String? countPieces}) {
    setState(() {
      if (lenCm != null) line.lenCm = lenCm;
      if (countPieces != null) line.countPieces = countPieces;
      final cm = double.tryParse(line.lenCm) ?? 0;
      final n = double.tryParse(line.countPieces) ?? 1;
      line.quantity = cm > 0 ? (n * cm / 100).toStringAsFixed(4) : '';
    });
  }
}

class _MatLine {
  String? materialId;
  String quantity;
  String qtyMode; // 'normal', 'dim', 'len'
  String dimW;
  String dimH;
  String lenCm;
  String countPieces;

  // Explicit controllers — never created inline in build()
  late final TextEditingController quantityCtrl;
  late final TextEditingController dimWCtrl;
  late final TextEditingController dimHCtrl;
  late final TextEditingController lenCmCtrl;
  late final TextEditingController countPiecesCtrl;

  _MatLine({this.materialId, this.quantity = '1', this.qtyMode = 'normal', this.dimW = '', this.dimH = '', this.lenCm = '', this.countPieces = '1'}) {
    quantityCtrl    = TextEditingController(text: quantity);
    dimWCtrl        = TextEditingController(text: dimW);
    dimHCtrl        = TextEditingController(text: dimH);
    lenCmCtrl       = TextEditingController(text: lenCm);
    countPiecesCtrl = TextEditingController(text: countPieces);
  }

  void disposeControllers() {
    quantityCtrl.dispose();
    dimWCtrl.dispose();
    dimHCtrl.dispose();
    lenCmCtrl.dispose();
    countPiecesCtrl.dispose();
  }
}
