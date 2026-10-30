import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/depot_model.dart';
import '../models/product_model.dart';
import '../services/s3_service.dart';
import '../theme/app_theme.dart';

const _salesKey = 'couture_depot_sales';

class DepotScreen extends StatefulWidget {
  final ValueNotifier<int>? productsChanged;
  const DepotScreen({super.key, this.productsChanged});

  @override
  State<DepotScreen> createState() => _DepotScreenState();
}

class _DepotScreenState extends State<DepotScreen> {
  List<DepotSale> _sales = [];
  List<ProductModel> _products = [];
  double _taxRate = 42;
  bool _loading = true;
  late String _selectedMonth;

  @override
  void initState() {
    super.initState();
    final current = _monthKey(DateTime.now());
    _selectedMonth = current.compareTo(DepotConfig.startMonth) < 0 ? DepotConfig.startMonth : current;
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
      s3.loadData(_salesKey),
      s3.loadData('couture_products'),
      s3.loadJson('couture_settings'),
    ]);
    if (!mounted) return;
    final settings = results[2];
    setState(() {
      _sales = (results[0] as List).map((e) => DepotSale.fromJson(e as Map<String, dynamic>)).toList();
      _products = (results[1] as List).map((e) => ProductModel.fromJson(e as Map<String, dynamic>)).toList();
      if (settings is Map) {
        _taxRate = (settings['urssafRate'] as num? ?? 12).toDouble() + (settings['incomeTaxRate'] as num? ?? 30).toDouble();
      }
      _loading = false;
    });
  }

  Future<void> _save() async {
    await S3Service().saveData(_salesKey, _sales.map((s) => s.toJson()).toList());
  }

  // ── Months ──

  static String _monthKey(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';

  static String _nextMonth(String key) {
    final parts = key.split('-').map(int.parse).toList();
    return _monthKey(DateTime(parts[0], parts[1] + 1, 1));
  }

  static String _monthLabel(String key) {
    final parts = key.split('-').map(int.parse).toList();
    final label = DateFormat('MMMM yyyy', 'fr_FR').format(DateTime(parts[0], parts[1], 1));
    return label[0].toUpperCase() + label.substring(1);
  }

  List<String> get _months {
    var last = _monthKey(DateTime.now());
    for (final s in _sales) {
      if (s.monthKey.compareTo(last) > 0) last = s.monthKey;
    }
    if (last.compareTo(DepotConfig.startMonth) < 0) last = DepotConfig.startMonth;
    final months = <String>[];
    for (var k = DepotConfig.startMonth; k.compareTo(last) <= 0; k = _nextMonth(k)) {
      months.add(k);
    }
    return months;
  }

  List<DepotSale> _salesFor(String month) => _sales.where((s) => s.monthKey == month).toList();

  // ── CRUD ──

  void _openForm({DepotSale? editing}) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final defaultDate = today.startsWith(_selectedMonth) ? today : '$_selectedMonth-01';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _DepotSaleForm(
        editing: editing,
        products: _products,
        defaultDate: defaultDate,
        taxRate: _taxRate,
        onSave: (sale) {
          setState(() {
            if (editing != null) {
              final idx = _sales.indexWhere((s) => s.id == editing.id);
              if (idx >= 0) _sales[idx] = sale;
            } else {
              _sales.add(sale);
            }
            _sales.sort((a, b) => b.date.compareTo(a.date));
            if (sale.monthKey.compareTo(DepotConfig.startMonth) >= 0) _selectedMonth = sale.monthKey;
          });
          _save();
        },
      ),
    );
  }

  Future<void> _delete(DepotSale sale) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Confirmer'),
            content: const Text('Supprimer cette vente ?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Supprimer', style: TextStyle(color: AppTheme.danger)),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    setState(() => _sales.removeWhere((s) => s.id == sale.id));
    await _save();
  }

  // ── UI ──

  String _eur(double v) => '${v.toStringAsFixed(2)} €';
  String _signed(double v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(2)} €';
  Color _profitColor(double v) => v >= 0 ? AppTheme.success : AppTheme.danger;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppTheme.accent)));
    }
    final months = _months;
    final idx = months.indexOf(_selectedMonth);
    final monthSales = _salesFor(_selectedMonth);
    final m = DepotMonthSummary.compute(monthSales, _taxRate);

    return Scaffold(
      body: Column(
        children: [
          Container(
            color: AppTheme.primaryFaded,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  color: AppTheme.primary,
                  onPressed: idx > 0 ? () => setState(() => _selectedMonth = months[idx - 1]) : null,
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(_monthLabel(_selectedMonth),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.primaryDark)),
                      const Text(DepotConfig.shopName, style: TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  color: AppTheme.primary,
                  onPressed: idx >= 0 && idx < months.length - 1 ? () => setState(() => _selectedMonth = months[idx + 1]) : null,
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              color: AppTheme.accent,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                children: [
                  _breakdownCard(m),
                  const SizedBox(height: 16),
                  _sectionTitle('Ventes du mois (${m.itemsSold.toStringAsFixed(0)} article${m.itemsSold > 1 ? 's' : ''})'),
                  if (monthSales.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('Aucune vente enregistrée pour ce mois',
                          textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textLight)),
                    ),
                  ...monthSales.map(_saleCard),
                  const SizedBox(height: 16),
                  _sectionTitle('Récapitulatif mois par mois'),
                  _recapCard(months),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('Vente'),
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.primaryDark)),
      );

  Widget _row(String label, String value, {bool bold = false, Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: color ?? AppTheme.textColor)),
            ),
            Text(value, style: TextStyle(fontSize: bold ? 15 : 13, fontWeight: FontWeight.w700, color: color ?? AppTheme.textColor)),
          ],
        ),
      );

  Widget _breakdownCard(DepotMonthSummary m) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              _row('Ventes en boutique', _eur(m.revenue), bold: true),
              _row('↳ Commission boutique (${DepotConfig.commissionRate.toStringAsFixed(0)}%)', '−${_eur(m.commission)}',
                  color: AppTheme.textSecondary),
              const Divider(height: 12),
              _row('Reversé par la boutique', _eur(m.afterCommission), bold: true),
              _row('↳ Impôts (URSSAF + IR : ${_taxRate.toStringAsFixed(0)}%)', '−${_eur(m.taxes)}', color: AppTheme.textSecondary),
              _row('↳ Loyer', '−${_eur(m.rent)}', color: AppTheme.textSecondary),
              _row('↳ Prix de revient matières', '−${_eur(m.materialCost)}', color: AppTheme.textSecondary),
              const Divider(height: 12),
              _row('Gain net du mois', _signed(m.profit), bold: true, color: _profitColor(m.profit)),
            ],
          ),
        ),
      );

  Widget _saleCard(DepotSale sale) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sale.productName,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.primaryDark)),
                    Text(
                      '${sale.qty.toStringAsFixed(sale.qty % 1 == 0 ? 0 : 1)} × ${_eur(sale.unitPrice)}  ·  revient ${_eur(sale.unitCost)}',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                    Text(_fmtDate(sale.date), style: const TextStyle(fontSize: 11, color: AppTheme.textLight)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('+${_eur(sale.total)}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.success)),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 16, color: AppTheme.primary),
                        onPressed: () => _openForm(editing: sale),
                        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                        padding: EdgeInsets.zero,
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 16, color: AppTheme.danger),
                        onPressed: () => _delete(sale),
                        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _recapCard(List<String> months) {
    final summaries = {for (final k in months) k: DepotMonthSummary.compute(_salesFor(k), _taxRate)};
    final totalRevenue = summaries.values.fold<double>(0, (s, m) => s + m.revenue);
    final totalProfit = summaries.values.fold<double>(0, (s, m) => s + m.profit);
    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        children: [
          ...months.map((k) {
            final m = summaries[k]!;
            final selected = k == _selectedMonth;
            return ListTile(
              dense: true,
              selected: selected,
              selectedTileColor: AppTheme.primaryFaded,
              onTap: () => setState(() => _selectedMonth = k),
              title: Text(_monthLabel(k), style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.primaryDark)),
              subtitle: Text('Ventes ${_eur(m.revenue)}', style: const TextStyle(fontSize: 11)),
              trailing: Text(_signed(m.profit),
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: _profitColor(m.profit))),
            );
          }),
          const Divider(height: 1),
          ListTile(
            dense: true,
            title: const Text('Cumul', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('Ventes ${_eur(totalRevenue)}', style: const TextStyle(fontSize: 11)),
            trailing: Text(_signed(totalProfit),
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: _profitColor(totalProfit))),
          ),
        ],
      ),
    );
  }

  String _fmtDate(String dateStr) {
    final d = DateTime.tryParse(dateStr);
    if (d == null) return dateStr;
    return DateFormat('d MMM yyyy', 'fr_FR').format(d);
  }
}

// ─── Sale Form ───

class _DepotSaleForm extends StatefulWidget {
  final DepotSale? editing;
  final List<ProductModel> products;
  final String defaultDate;
  final double taxRate;
  final void Function(DepotSale) onSave;
  const _DepotSaleForm({
    this.editing,
    required this.products,
    required this.defaultDate,
    required this.taxRate,
    required this.onSave,
  });

  @override
  State<_DepotSaleForm> createState() => _DepotSaleFormState();
}

class _DepotSaleFormState extends State<_DepotSaleForm> {
  final _formKey = GlobalKey<FormState>();
  late String _date;
  String? _productId;
  late final TextEditingController _name, _qty, _price, _cost;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _date = e?.date ?? widget.defaultDate;
    _productId = widget.products.any((p) => p.id == e?.productId) ? e?.productId : null;
    _name = TextEditingController(text: e?.productName ?? '');
    _qty = TextEditingController(text: e != null ? e.qty.toStringAsFixed(e.qty % 1 == 0 ? 0 : 1) : '1');
    _price = TextEditingController(text: e?.unitPrice.toStringAsFixed(2) ?? '');
    _cost = TextEditingController(text: e?.unitCost.toStringAsFixed(2) ?? '');
    for (final c in [_qty, _price, _cost]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _qty.dispose();
    _price.dispose();
    _cost.dispose();
    super.dispose();
  }

  double _num(TextEditingController c, [double def = 0]) => double.tryParse(c.text.replaceAll(',', '.')) ?? def;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_date) ?? DateTime.now(),
      firstDate: DateTime(2026, 11, 1),
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => _date = DateFormat('yyyy-MM-dd').format(picked));
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final now = DateTime.now();
    widget.onSave(DepotSale(
      id: widget.editing?.id ?? const Uuid().v4(),
      date: _date,
      productId: _productId,
      productName: _name.text.trim().isEmpty ? 'Vente' : _name.text.trim(),
      qty: _num(_qty, 1),
      unitPrice: _num(_price),
      unitCost: _num(_cost),
      createdAt: widget.editing?.createdAt ?? now,
      updatedAt: now,
    ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final preview = DepotMonthSummary.compute([
      DepotSale(
        id: '',
        date: _date,
        productName: '',
        qty: _num(_qty, 1),
        unitPrice: _num(_price),
        unitCost: _num(_cost),
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ], widget.taxRate, rent: 0);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.editing != null ? 'Modifier la vente' : 'Nouvelle vente en dépôt',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.primaryDark)),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: const InputDecoration(labelText: 'Date *', suffixIcon: Icon(Icons.calendar_today, size: 18)),
                  child: Text(_date),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _productId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Produit'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('— Libre —')),
                  ...widget.products.map((p) => DropdownMenuItem(
                      value: p.id, child: Text(p.name, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis))),
                ],
                onChanged: (v) {
                  setState(() {
                    _productId = v;
                    if (v != null) {
                      final prod = widget.products.firstWhere((p) => p.id == v);
                      _name.text = prod.name;
                      if (prod.sellingPrice != null && prod.sellingPrice! > 0) {
                        _price.text = prod.sellingPrice!.toStringAsFixed(2);
                      }
                      _cost.text = prod.totalCost.toStringAsFixed(2);
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Nom produit'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _qty,
                      decoration: const InputDecoration(labelText: 'Qté'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      controller: _price,
                      decoration: const InputDecoration(labelText: 'Prix de vente *', suffixText: '€'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Requis' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _cost,
                decoration: const InputDecoration(labelText: 'Prix de revient matière (unitaire)', suffixText: '€'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              if (preview.revenue > 0) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: AppTheme.primaryFaded, borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    children: [
                      _line('Total vente', preview.revenue),
                      _line('− Commission (${DepotConfig.commissionRate.toStringAsFixed(0)}%)', -preview.commission),
                      _line('− Impôts (${widget.taxRate.toStringAsFixed(0)}%)', -preview.taxes),
                      _line('− Matières', -preview.materialCost),
                      const Divider(height: 10),
                      _line('Gain sur cette vente (hors loyer)', preview.profit, bold: true),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler'))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: ElevatedButton(onPressed: _submit, child: Text(widget.editing != null ? 'Modifier' : 'Ajouter'))),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(String label, double value, {bool bold = false}) {
    final color = bold ? (value >= 0 ? AppTheme.success : AppTheme.danger) : AppTheme.textColor;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: color))),
          Text('${value.toStringAsFixed(2)} €', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }
}
