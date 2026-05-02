import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/finance_model.dart';
import '../models/product_model.dart';
import '../services/s3_service.dart';
import '../theme/app_theme.dart';

class FinanceScreen extends StatefulWidget {
  const FinanceScreen({super.key});

  @override
  State<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends State<FinanceScreen> with SingleTickerProviderStateMixin {
  List<FinanceOrder> _orders = [];
  List<FinanceSale> _sales = [];
  List<ProductModel> _products = [];
  late TabController _tabController;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final s3 = S3Service();
    final results = await Future.wait([
      s3.loadData('couture_orders'),
      s3.loadData('couture_sales'),
      s3.loadData('couture_products'),
    ]);
    if (!mounted) return;
    setState(() {
      _orders = results[0].map((e) => FinanceOrder.fromJson(e as Map<String, dynamic>)).toList();
      _sales = results[1].map((e) => FinanceSale.fromJson(e as Map<String, dynamic>)).toList();
      _products = results[2].map((e) => ProductModel.fromJson(e as Map<String, dynamic>)).toList();
      _loading = false;
    });
  }

  Future<void> _saveOrders() async {
    await S3Service().saveData('couture_orders', _orders.map((o) => o.toJson()).toList());
  }

  Future<void> _saveSales() async {
    await S3Service().saveData('couture_sales', _sales.map((s) => s.toJson()).toList());
  }

  double get _totalOrders => _orders.fold(0, (s, o) => s + o.amount);
  double get _totalSales => _sales.fold(0, (s, v) => s + v.total);
  double get _profit => _totalSales - _totalOrders;

  // ── Orders ──

  void _openOrderForm({FinanceOrder? editing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _OrderForm(
        editing: editing,
        onSave: (order) {
          setState(() {
            if (editing != null) {
              final idx = _orders.indexWhere((o) => o.id == editing.id);
              if (idx >= 0) _orders[idx] = order;
            } else {
              _orders.insert(0, order);
            }
            _orders.sort((a, b) => b.date.compareTo(a.date));
          });
          _saveOrders();
        },
      ),
    );
  }

  Future<void> _deleteOrder(FinanceOrder order) async {
    final ok = await _confirm('Supprimer cette commande ?');
    if (!ok) return;
    setState(() => _orders.removeWhere((o) => o.id == order.id));
    await _saveOrders();
  }

  // ── Sales ──

  void _openSaleForm({FinanceSale? editing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _SaleForm(
        editing: editing,
        products: _products,
        onSave: (sale) {
          setState(() {
            if (editing != null) {
              final idx = _sales.indexWhere((s) => s.id == editing.id);
              if (idx >= 0) _sales[idx] = sale;
            } else {
              _sales.insert(0, sale);
            }
            _sales.sort((a, b) => b.date.compareTo(a.date));
          });
          _saveSales();
        },
      ),
    );
  }

  Future<void> _deleteSale(FinanceSale sale) async {
    final ok = await _confirm('Supprimer cette vente ?');
    if (!ok) return;
    setState(() => _sales.removeWhere((s) => s.id == sale.id));
    await _saveSales();
  }

  Future<bool> _confirm(String msg) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Confirmer'),
            content: Text(msg),
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
  }

  void _viewInvoice(String key, String name) async {
    final url = S3Service().getPresignedUrl(key);
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impossible d\'ouvrir la facture')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : Column(
              children: [
                // Summary strip
                Container(
                  color: AppTheme.primaryFaded,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      _sumCard('Dépenses', _totalOrders, AppTheme.danger),
                      _vDivider(),
                      _sumCard('Recettes', _totalSales, AppTheme.success),
                      _vDivider(),
                      _sumCard('Résultat', _profit, _profit >= 0 ? AppTheme.success : AppTheme.danger),
                    ],
                  ),
                ),
                // Tab bar
                TabBar(
                  controller: _tabController,
                  labelColor: AppTheme.primary,
                  unselectedLabelColor: AppTheme.textSecondary,
                  indicatorColor: AppTheme.primary,
                  tabs: const [
                    Tab(text: 'Commandes'),
                    Tab(text: 'Ventes'),
                  ],
                ),
                // Tab views
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      // Orders tab
                      RefreshIndicator(
                        onRefresh: _load,
                        color: AppTheme.accent,
                        child: _orders.isEmpty
                            ? _emptyState('Aucune commande', 'Enregistrez vos achats de matières')
                            : ListView.builder(
                                padding: const EdgeInsets.all(12),
                                itemCount: _orders.length,
                                itemBuilder: (_, i) => _orderCard(_orders[i]),
                              ),
                      ),
                      // Sales tab
                      RefreshIndicator(
                        onRefresh: _load,
                        color: AppTheme.accent,
                        child: _sales.isEmpty
                            ? _emptyState('Aucune vente', 'Enregistrez vos ventes de produits')
                            : ListView.builder(
                                padding: const EdgeInsets.all(12),
                                itemCount: _sales.length,
                                itemBuilder: (_, i) => _saleCard(_sales[i]),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          if (_tabController.index == 0) {
            _openOrderForm();
          } else {
            _openSaleForm();
          }
        },
        icon: const Icon(Icons.add),
        label: AnimatedBuilder(
          animation: _tabController,
          builder: (_, __) => Text(_tabController.index == 0 ? 'Commande' : 'Vente'),
        ),
      ),
    );
  }

  Widget _sumCard(String label, double value, Color color) => Expanded(
        child: Column(
          children: [
            Text(
              '${value.toStringAsFixed(2)} €',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: color),
            ),
            Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
          ],
        ),
      );

  Widget _vDivider() => Container(width: 1, height: 32, color: AppTheme.borderLight);

  Widget _orderCard(FinanceOrder order) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(order.description.isNotEmpty ? order.description : order.supplier,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.primaryDark)),
                        if (order.supplier.isNotEmpty && order.description.isNotEmpty)
                          Text(order.supplier, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                        Text(_fmtDate(order.date), style: const TextStyle(fontSize: 11, color: AppTheme.textLight)),
                      ],
                    ),
                  ),
                  Text(
                    '-${order.amount.toStringAsFixed(2)} €',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.danger),
                  ),
                ],
              ),
              if (order.invoiceKey.isNotEmpty) ...[
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: () => _viewInvoice(order.invoiceKey, order.invoiceName),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F4FD),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.receipt_outlined, size: 14, color: Color(0xFF2980B9)),
                        const SizedBox(width: 4),
                        Text(
                          order.invoiceName.isNotEmpty ? order.invoiceName : 'Facture',
                          style: const TextStyle(fontSize: 11, color: Color(0xFF2980B9), fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openOrderForm(editing: order),
                      icon: const Icon(Icons.edit_outlined, size: 14),
                      label: const Text('Modifier', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(foregroundColor: AppTheme.primary, side: const BorderSide(color: AppTheme.borderLight), minimumSize: const Size(0, 32)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _deleteOrder(order),
                      icon: const Icon(Icons.delete_outline, size: 14),
                      label: const Text('Supprimer', style: TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(foregroundColor: AppTheme.danger, side: const BorderSide(color: Color(0xFFFDE8E8)), minimumSize: const Size(0, 32)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

  Widget _saleCard(FinanceSale sale) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sale.productName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppTheme.primaryDark)),
                    Text(
                      '${sale.qty.toStringAsFixed(sale.qty % 1 == 0 ? 0 : 1)} × ${sale.unitPrice.toStringAsFixed(2)} €',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                    Text(_fmtDate(sale.date), style: const TextStyle(fontSize: 11, color: AppTheme.textLight)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '+${sale.total.toStringAsFixed(2)} €',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppTheme.success),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 16, color: AppTheme.primary),
                        onPressed: () => _openSaleForm(editing: sale),
                        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                        padding: EdgeInsets.zero,
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 16, color: AppTheme.danger),
                        onPressed: () => _deleteSale(sale),
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

  String _fmtDate(String dateStr) {
    final d = DateTime.tryParse(dateStr);
    if (d == null) return dateStr;
    return DateFormat('d MMM yyyy', 'fr_FR').format(d);
  }

  Widget _emptyState(String title, String subtitle) => ListView(
        children: [
          const SizedBox(height: 80),
          const Icon(Icons.euro_outlined, size: 72, color: AppTheme.borderLight),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
          const SizedBox(height: 8),
          Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AppTheme.textLight)),
        ],
      );
}

// ─── Order Form ───

class _OrderForm extends StatefulWidget {
  final FinanceOrder? editing;
  final void Function(FinanceOrder) onSave;
  const _OrderForm({this.editing, required this.onSave});

  @override
  State<_OrderForm> createState() => _OrderFormState();
}

class _OrderFormState extends State<_OrderForm> {
  final _formKey = GlobalKey<FormState>();
  late String _date, _supplier, _description, _amount;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _date = e?.date ?? DateFormat('yyyy-MM-dd').format(DateTime.now());
    _supplier = e?.supplier ?? '';
    _description = e?.description ?? '';
    _amount = e != null ? e.amount.toString() : '';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_date) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => _date = DateFormat('yyyy-MM-dd').format(picked));
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    final now = DateTime.now();
    widget.onSave(FinanceOrder(
      id: widget.editing?.id ?? const Uuid().v4(),
      date: _date,
      supplier: _supplier.trim(),
      description: _description.trim(),
      amount: double.tryParse(_amount) ?? 0,
      invoiceKey: widget.editing?.invoiceKey ?? '',
      invoiceName: widget.editing?.invoiceName ?? '',
      createdAt: widget.editing?.createdAt ?? now,
      updatedAt: now,
    ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.editing != null ? 'Modifier la commande' : 'Nouvelle commande',
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
              TextFormField(
                initialValue: _supplier,
                decoration: const InputDecoration(labelText: 'Fournisseur'),
                onSaved: (v) => _supplier = v ?? '',
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: _description,
                decoration: const InputDecoration(labelText: 'Description'),
                onSaved: (v) => _description = v ?? '',
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: _amount,
                decoration: const InputDecoration(labelText: 'Montant *', suffixText: '€'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) => v == null || v.isEmpty ? 'Requis' : null,
                onSaved: (v) => _amount = v ?? '0',
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler'))),
                  const SizedBox(width: 12),
                  Expanded(child: ElevatedButton(onPressed: _submit, child: Text(widget.editing != null ? 'Modifier' : 'Ajouter'))),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Sale Form ───

class _SaleForm extends StatefulWidget {
  final FinanceSale? editing;
  final List<ProductModel> products;
  final void Function(FinanceSale) onSave;
  const _SaleForm({this.editing, required this.products, required this.onSave});

  @override
  State<_SaleForm> createState() => _SaleFormState();
}

class _SaleFormState extends State<_SaleForm> {
  final _formKey = GlobalKey<FormState>();
  late String _date, _productName, _qty, _unitPrice;
  String? _productId;

  @override
  void initState() {
    super.initState();
    final e = widget.editing;
    _date = e?.date ?? DateFormat('yyyy-MM-dd').format(DateTime.now());
    _productId = e?.productId;
    _productName = e?.productName ?? '';
    _qty = e?.qty.toString() ?? '1';
    _unitPrice = e?.unitPrice.toString() ?? '';
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(_date) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => _date = DateFormat('yyyy-MM-dd').format(picked));
  }

  double get _total => (double.tryParse(_qty) ?? 1) * (double.tryParse(_unitPrice) ?? 0);

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    _formKey.currentState!.save();
    final qty = double.tryParse(_qty) ?? 1;
    final unitPrice = double.tryParse(_unitPrice) ?? 0;
    final now = DateTime.now();
    widget.onSave(FinanceSale(
      id: widget.editing?.id ?? const Uuid().v4(),
      date: _date,
      productId: _productId,
      productName: _productName.trim(),
      qty: qty,
      unitPrice: unitPrice,
      total: qty * unitPrice,
      createdAt: widget.editing?.createdAt ?? now,
      updatedAt: now,
    ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.editing != null ? 'Modifier la vente' : 'Nouvelle vente',
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
                decoration: const InputDecoration(labelText: 'Produit'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('— Libre —')),
                  ...widget.products.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name, style: const TextStyle(fontSize: 13)))),
                ],
                onChanged: (v) {
                  setState(() {
                    _productId = v;
                    if (v != null) {
                      final prod = widget.products.firstWhere((p) => p.id == v);
                      _productName = prod.name;
                      if (prod.sellingPrice != null) _unitPrice = prod.sellingPrice!.toStringAsFixed(2);
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                initialValue: _productName,
                decoration: const InputDecoration(labelText: 'Nom produit *'),
                validator: (v) => v == null || v.trim().isEmpty ? 'Requis' : null,
                onSaved: (v) => _productName = v ?? '',
                onChanged: (v) => _productName = v,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: _qty,
                      decoration: const InputDecoration(labelText: 'Qté'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (v) => setState(() => _qty = v),
                      onSaved: (v) => _qty = v ?? '1',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      initialValue: _unitPrice,
                      decoration: const InputDecoration(labelText: 'Prix unitaire', suffixText: '€'),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) => v == null || v.isEmpty ? 'Requis' : null,
                      onChanged: (v) => setState(() => _unitPrice = v),
                      onSaved: (v) => _unitPrice = v ?? '0',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text('Total : ${_total.toStringAsFixed(2)} €',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: AppTheme.success)),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler'))),
                  const SizedBox(width: 12),
                  Expanded(child: ElevatedButton(onPressed: _submit, child: Text(widget.editing != null ? 'Modifier' : 'Ajouter'))),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
