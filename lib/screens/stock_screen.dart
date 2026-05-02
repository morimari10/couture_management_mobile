import 'package:flutter/material.dart';
import '../models/product_model.dart';
import '../models/collection_model.dart';
import '../services/s3_service.dart';
import '../theme/app_theme.dart';

class StockScreen extends StatefulWidget {
  final ValueNotifier<int>? productsChanged;
  const StockScreen({super.key, this.productsChanged});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  List<ProductModel> _products = [];
  List<CollectionModel> _collections = [];
  Map<String, int> _stocks = {};
  Map<String, dynamic> _settings = {
    'urssafRate': 12,
    'incomeTaxRate': 30,
    'wastePct': 15,
    'machineCostPerH': 0.40,
  };
  String _search = '';
  String _filter = 'all'; // all | low | out
  String? _filterCollectionId; // null = toutes
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    widget.productsChanged?.addListener(_load);
  }

  @override
  void dispose() {
    widget.productsChanged?.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final s3 = S3Service();
    final results = await Future.wait([
      s3.loadData('couture_products'),
      s3.loadData('couture_collections'),
      s3.loadJson('couture_stocks'),
      s3.loadJson('couture_settings'),
    ]);
    if (!mounted) return;
    final stocksRaw = results[2];
    final settingsRaw = results[3];
    setState(() {
      _products = (results[0] as List).map((e) => ProductModel.fromJson(e as Map<String, dynamic>)).toList();
      _collections = (results[1] as List).map((e) => CollectionModel.fromJson(e as Map<String, dynamic>)).toList();
      _stocks = stocksRaw is Map
          ? stocksRaw.map((k, v) => MapEntry(k.toString(), (v as num).toInt()))
          : {};
      if (settingsRaw is Map) {
        _settings = {..._settings, ...settingsRaw};
      }
      _loading = false;
    });
  }

  Future<void> _saveStocks() async {
    await S3Service().saveData('couture_stocks', _stocks);
  }

  void _setQty(String productId, int qty) {
    setState(() => _stocks[productId] = qty.clamp(0, 9999));
    _saveStocks();
  }

  String _stockLevel(int qty) {
    if (qty == 0) return 'out';
    if (qty <= 3) return 'low';
    return 'ok';
  }

  CollectionModel? _getCol(String? id) =>
      id == null ? null : _collections.cast<CollectionModel?>().firstWhere((c) => c?.id == id, orElse: () => null);

  double? _calcNetPerUnit(ProductModel p) {
    if (p.sellingPrice == null) return null;
    final chargesRate = ((_settings['urssafRate'] as num? ?? 0) + (_settings['incomeTaxRate'] as num? ?? 0)) / 100;
    final wastePct = (_settings['wastePct'] as num? ?? 0) / 100;
    final machCost = (_settings['machineCostPerH'] as num? ?? 0).toDouble();
    final costBase = p.totalCost * (1 + wastePct) + (p.laborHours ?? 0) * machCost;
    return p.sellingPrice! * (1 - chargesRate) - costBase;
  }

  double? _calcNakedPerUnit(ProductModel p) {
    if (p.sellingPrice == null) return null;
    final wastePct = (_settings['wastePct'] as num? ?? 0) / 100;
    final machCost = (_settings['machineCostPerH'] as num? ?? 0).toDouble();
    final costBase = p.totalCost * (1 + wastePct) + (p.laborHours ?? 0) * machCost;
    return p.sellingPrice! - costBase;
  }

  List<ProductModel> get _filtered => _products.where((p) {
        if (_filterCollectionId != null && p.collectionId != _filterCollectionId) return false;
        final qty = _stocks[p.id] ?? 0;
        final level = _stockLevel(qty);
        if (_filter == 'low' && level != 'low') return false;
        if (_filter == 'out' && level != 'out') return false;
        if (_search.isNotEmpty && !p.name.toLowerCase().contains(_search.toLowerCase())) return false;
        return true;
      }).toList();

  @override
  Widget build(BuildContext context) {
    final totalItems = _products.fold<int>(0, (s, p) => s + (_stocks[p.id] ?? 0));
    final totalValue = _products.fold<double>(
        0, (s, p) => s + (_stocks[p.id] ?? 0) * (p.sellingPrice ?? 0));
    final potProfit = _products.fold<double>(0, (s, p) {
      final qty = _stocks[p.id] ?? 0;
      final net = _calcNetPerUnit(p);
      return s + qty * (net != null && net > 0 ? net : 0);
    });
    final potProfitNaked = _products.fold<double>(0, (s, p) {
      final qty = _stocks[p.id] ?? 0;
      final net = _calcNakedPerUnit(p);
      return s + qty * (net != null && net > 0 ? net : 0);
    });

    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : RefreshIndicator(
              onRefresh: _load,
              color: AppTheme.accent,
              child: Column(
                children: [
                  // Summary strip
                  Container(
                    color: AppTheme.primaryFaded,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            _sumCell('Articles', '$totalItems'),
                            _divider(),
                            _sumCell('Valeur stock', '${totalValue.toStringAsFixed(0)} €'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Divider(height: 1, color: AppTheme.borderLight),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _sumCell('Profit déclaré', '${potProfit.toStringAsFixed(0)} €',
                                sub: 'URSSAF ${_settings['urssafRate']}% + IR ${_settings['incomeTaxRate']}%'),
                            _divider(),
                            _sumCell('Bénéf. sans décl.', '${potProfitNaked.toStringAsFixed(0)} €',
                                sub: 'avant charges sociales'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Filters
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            decoration: const InputDecoration(
                              hintText: 'Rechercher...',
                              prefixIcon: Icon(Icons.search, color: AppTheme.textLight),
                              isDense: true,
                            ),
                            onChanged: (v) => setState(() => _search = v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _filterBtn('Tous', 'all'),
                        const SizedBox(width: 4),
                        _filterBtn('Faible', 'low'),
                        const SizedBox(width: 4),
                        _filterBtn('Rupture', 'out'),
                      ],
                    ),
                  ),
                  // Collection filter chips
                  if (_collections.isNotEmpty)
                    SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        children: [
                          _collectionChip('Toutes', null),
                          ..._collections.map((c) => _collectionChip('${c.emoji} ${c.name}', c.id)),
                        ],
                      ),
                    ),
                  // Stock list
                  Expanded(
                    child: _filtered.isEmpty
                        ? const Center(
                            child: Text('Aucun produit', style: TextStyle(color: AppTheme.textSecondary)),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: _filtered.length,
                            itemBuilder: (_, i) => _stockRow(_filtered[i]),
                          ),
                  ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton(
        mini: true,
        onPressed: _showSettings,
        tooltip: 'Paramètres de calcul',
        child: const Icon(Icons.settings_outlined),
      ),
    );
  }

  Widget _sumCell(String label, String value, {String? sub}) => Expanded(
        child: Column(
          children: [
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.primary)),
            Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
            if (sub != null)
              Text(sub, style: const TextStyle(fontSize: 9, color: AppTheme.textLight)),
          ],
        ),
      );

  Widget _divider() => Container(width: 1, height: 32, color: AppTheme.borderLight);

  Widget _filterBtn(String label, String value) {
    final active = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? AppTheme.primary : AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: active ? AppTheme.primary : AppTheme.borderLight),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: active ? Colors.white : AppTheme.textSecondary),
        ),
      ),
    );
  }

  Widget _collectionChip(String label, String? id) {
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

  Widget _stockRow(ProductModel prod) {
    final qty = _stocks[prod.id] ?? 0;
    final level = _stockLevel(qty);
    final col = _getCol(prod.collectionId);
    final net = _calcNetPerUnit(prod);
    final naked = _calcNakedPerUnit(prod);

    Color levelColor;
    String levelLabel;
    IconData levelIcon;
    switch (level) {
      case 'out':
        levelColor = AppTheme.danger;
        levelLabel = 'Rupture';
        levelIcon = Icons.do_not_disturb_on_outlined;
        break;
      case 'low':
        levelColor = AppTheme.warning;
        levelLabel = 'Faible';
        levelIcon = Icons.warning_amber_outlined;
        break;
      default:
        levelColor = AppTheme.success;
        levelLabel = 'En stock';
        levelIcon = Icons.check_circle_outline;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Nom + badge niveau
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(prod.name,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.primaryDark)),
                      if (col != null)
                        Text('${col.emoji} ${col.name}',
                            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: levelColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: levelColor.withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(levelIcon, size: 12, color: levelColor),
                      const SizedBox(width: 4),
                      Text(levelLabel,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: levelColor)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Prix + controles quantité
            Row(
              children: [
                if (prod.sellingPrice != null) ...[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Prix de vente',
                          style: TextStyle(fontSize: 10, color: AppTheme.textLight)),
                      Text('${prod.sellingPrice!.toStringAsFixed(2)} €',
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.primary)),
                    ],
                  ),
                ] else
                  const Text('Prix non défini',
                      style: TextStyle(fontSize: 12, color: AppTheme.textLight, fontStyle: FontStyle.italic)),
                const Spacer(),
                _qtyBtn(Icons.remove, () => _setQty(prod.id, qty - 1)),
                SizedBox(
                  width: 44,
                  child: Text(
                    '$qty',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: AppTheme.primaryDark),
                  ),
                ),
                _qtyBtn(Icons.add, () => _setQty(prod.id, qty + 1)),
              ],
            ),
            // Bénéfices
            if (net != null || naked != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppTheme.background,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    if (net != null)
                      Expanded(child: _profitCell('Bénéf./unité (déclaré)', net)),
                    if (net != null && naked != null)
                      Container(
                          width: 1,
                          height: 30,
                          color: AppTheme.borderLight,
                          margin: const EdgeInsets.symmetric(horizontal: 10)),
                    if (naked != null)
                      Expanded(child: _profitCell('Bénéf./unité (sans décl.)', naked)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _profitCell(String label, double value) => Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textLight)),
          const SizedBox(height: 2),
          Text(
            '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)} €',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: value >= 0 ? AppTheme.success : AppTheme.danger,
            ),
          ),
        ],
      );

  Widget _qtyBtn(IconData icon, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.borderLight, width: 2),
            color: AppTheme.surface,
          ),
          child: Icon(icon, size: 16, color: AppTheme.primary),
        ),
      );

  void _showSettings() {
    showDialog(
      context: context,
      builder: (_) => _SettingsDialog(
        settings: _settings,
        onSave: (settings) {
          setState(() => _settings = settings);
          S3Service().saveData('couture_settings', settings);
        },
      ),
    );
  }
}

class _SettingsDialog extends StatefulWidget {
  final Map<String, dynamic> settings;
  final void Function(Map<String, dynamic>) onSave;

  const _SettingsDialog({required this.settings, required this.onSave});

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late TextEditingController _urssaf, _income, _waste, _machine;

  @override
  void initState() {
    super.initState();
    _urssaf = TextEditingController(text: '${widget.settings['urssafRate'] ?? 12}');
    _income = TextEditingController(text: '${widget.settings['incomeTaxRate'] ?? 30}');
    _waste = TextEditingController(text: '${widget.settings['wastePct'] ?? 15}');
    _machine = TextEditingController(text: '${widget.settings['machineCostPerH'] ?? 0.40}');
  }

  @override
  void dispose() {
    _urssaf.dispose();
    _income.dispose();
    _waste.dispose();
    _machine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Paramètres de calcul', style: TextStyle(color: AppTheme.primaryDark)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(_urssaf, 'Taux URSSAF (%)', '%'),
          const SizedBox(height: 12),
          _field(_income, 'Taux impôt revenu (%)', '%'),
          const SizedBox(height: 12),
          _field(_waste, 'Marge perte chutes (%)', '%'),
          const SizedBox(height: 12),
          _field(_machine, 'Coût machine (€/h)', '€/h'),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        ElevatedButton(
          onPressed: () {
            widget.onSave({
              'urssafRate': double.tryParse(_urssaf.text) ?? 12,
              'incomeTaxRate': double.tryParse(_income.text) ?? 30,
              'wastePct': double.tryParse(_waste.text) ?? 15,
              'machineCostPerH': double.tryParse(_machine.text) ?? 0.40,
            });
            Navigator.pop(context);
          },
          child: const Text('Sauvegarder'),
        ),
      ],
    );
  }

  Widget _field(TextEditingController ctrl, String label, String suffix) => TextField(
        controller: ctrl,
        decoration: InputDecoration(labelText: label, suffixText: suffix),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
      );
}
