import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../models/collection_model.dart';
import '../models/finance_model.dart';
import '../models/market_model.dart';
import '../models/product_model.dart';
import '../services/s3_service.dart';
import '../theme/app_theme.dart';

class MarketScreen extends StatefulWidget {
  final VoidCallback? onSalesChanged;
  const MarketScreen({super.key, this.onSalesChanged});

  @override
  State<MarketScreen> createState() => _MarketScreenState();
}

class _MarketScreenState extends State<MarketScreen> {
  List<MarketModel> _markets = [];
  List<ProductModel> _products = [];
  List<CollectionModel> _collections = [];
  Map<String, int> _stocks = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final s3 = S3Service();
    final results = await Future.wait([
      s3.loadData('couture_markets'),
      s3.loadData('couture_products'),
      s3.loadData('couture_collections'),
      s3.loadJson('couture_stocks'),
    ]);
    if (!mounted) return;
    setState(() {
      _markets = (results[0] as List)
          .whereType<Map<String, dynamic>>()
          .map((e) => MarketModel.fromJson(e))
          .toList();
      _products = (results[1] as List)
          .whereType<Map<String, dynamic>>()
          .map((e) => ProductModel.fromJson(e))
          .toList();
      _collections = (results[2] as List)
          .whereType<Map<String, dynamic>>()
          .map((e) => CollectionModel.fromJson(e))
          .toList();
      final stocksRaw = results[3];
      _stocks = stocksRaw is Map
          ? stocksRaw.map((k, v) => MapEntry(k.toString(), (v as num).toInt()))
          : {};
      _loading = false;
    });
  }

  Future<void> _saveMarkets() async {
    await S3Service().saveData(
      'couture_markets',
      _markets.map((m) => m.toJson()).toList(),
    );
  }

  Future<void> _saveStocks() async {
    await S3Service().saveData('couture_stocks', _stocks);
  }

  MarketModel? get _activeMarket =>
      _markets.cast<MarketModel?>().firstWhere((m) => m!.isActive, orElse: () => null);

  List<MarketModel> get _pastMarkets =>
      _markets.where((m) => !m.isActive).toList()..sort((a, b) => (b.endedAt ?? b.startedAt).compareTo(a.endedAt ?? a.startedAt));

  Future<void> _startMarket() async {
    final nameCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Lancer un marché'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Nom du marché *'),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: locationCtrl,
              decoration: const InputDecoration(labelText: 'Lieu (optionnel)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Lancer')),
        ],
      ),
    );
    if (result != true || nameCtrl.text.trim().isEmpty) return;

    final market = MarketModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: nameCtrl.text.trim(),
      location: locationCtrl.text.trim().isNotEmpty ? locationCtrl.text.trim() : null,
      startedAt: DateTime.now(),
      isActive: true,
      sales: [],
      initialStock: Map<String, int>.from(_stocks),
    );
    setState(() => _markets.insert(0, market));
    await _saveMarkets();
  }

  Future<void> _endMarket(MarketModel market) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Terminer le marché ?'),
        content: Text('Clôturer "${market.name}" ?\nVentes: ${market.totalArticlesSold} articles — ${market.totalRevenue.toStringAsFixed(2)} €\n\nLes ventes seront enregistrées automatiquement dans Finances.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Terminer')),
        ],
      ),
    );
    if (confirm != true) return;

    final now = DateTime.now();
    setState(() {
      market.isActive = false;
      market.endedAt = now;
    });

    // Group sales by product and push to Finance
    await _exportSalesToFinance(market, now);
    widget.onSalesChanged?.call();
    await _saveMarkets();
  }

  Future<void> _exportSalesToFinance(MarketModel market, DateTime closedAt) async {
    if (market.sales.isEmpty) return;
    final s3 = S3Service();
    final raw = await s3.loadData('couture_sales');
    final existing = raw.whereType<Map<String, dynamic>>().map((e) => e).toList();

    final dateStr = DateFormat('yyyy-MM-dd').format(market.startedAt);
    final total = market.totalRevenue;
    final qty = market.totalArticlesSold.toDouble();

    final entry = FinanceSale(
      id: const Uuid().v4(),
      date: dateStr,
      productId: null,
      productName: market.name,
      qty: qty,
      unitPrice: qty > 0 ? total / qty : 0.0,
      total: total,
      createdAt: closedAt,
      updatedAt: closedAt,
    ).toJson();

    await s3.saveData('couture_sales', [...existing, entry]);
  }

  Future<void> _deleteMarket(MarketModel market) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Supprimer ?'),
        content: Text('Supprimer le compte rendu de "${market.name}" ?'),
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
    setState(() => _markets.removeWhere((m) => m.id == market.id));
    await _saveMarkets();
  }

  Future<void> _registerSale(MarketModel market) async {
    // Show products with available stock
    final availableProducts = _products.where((p) => (_stocks[p.id] ?? 0) > 0).toList();
    if (availableProducts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun produit en stock')),
      );
      return;
    }

    final result = await showModalBottomSheet<_SaleEntry>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _SaleForm(products: availableProducts, stocks: _stocks, collections: _collections),
    );
    if (result == null) return;

    final product = _products.firstWhere((p) => p.id == result.productId);
    final sale = MarketSaleLine(
      productId: result.productId,
      productName: product.name,
      quantity: result.quantity,
      unitPrice: result.unitPrice,
    );

    setState(() {
      market.sales.add(sale);
      // Decrement stock
      _stocks[result.productId] = ((_stocks[result.productId] ?? 0) - result.quantity).clamp(0, 9999);
    });
    await Future.wait([_saveMarkets(), _saveStocks()]);
  }

  Future<void> _undoLastSale(MarketModel market) async {
    if (market.sales.isEmpty) return;
    final last = market.sales.last;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Annuler la dernière vente ?'),
        content: Text('${last.quantity}× ${last.productName} (${last.total.toStringAsFixed(2)} €)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Non')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Oui, annuler')),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() {
      market.sales.removeLast();
      // Restore stock
      _stocks[last.productId] = ((_stocks[last.productId] ?? 0) + last.quantity).clamp(0, 9999);
    });
    await Future.wait([_saveMarkets(), _saveStocks()]);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppTheme.accent)),
      );
    }

    final active = _activeMarket;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppTheme.accent,
        child: active != null
            ? _buildActiveMarket(active)
            : _buildMarketList(),
      ),
      floatingActionButton: active == null
          ? FloatingActionButton.extended(
              onPressed: _startMarket,
              icon: const Icon(Icons.storefront),
              label: const Text('Lancer un marché'),
            )
          : FloatingActionButton.extended(
              onPressed: () => _registerSale(active),
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text('Vente'),
            ),
    );
  }

  // ─── Active Market View ───

  Widget _buildActiveMarket(MarketModel market) {
    final duration = market.duration;
    final durationStr = '${duration.inHours}h${(duration.inMinutes % 60).toString().padLeft(2, '0')}';

    // Group sales by product
    final salesByProduct = <String, _ProductSalesSummary>{};
    for (final sale in market.sales) {
      final entry = salesByProduct.putIfAbsent(
        sale.productId,
        () => _ProductSalesSummary(name: sale.productName),
      );
      entry.quantity += sale.quantity;
      entry.revenue += sale.total;
    }
    final sortedSales = salesByProduct.values.toList()
      ..sort((a, b) => b.revenue.compareTo(a.revenue));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Market header
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppTheme.primaryDark, AppTheme.primary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.storefront, color: Colors.white, size: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(market.name,
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                        if (market.location != null)
                          Text('📍 ${market.location}',
                              style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.success,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text('EN COURS', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('⏱ Durée : $durationStr', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // KPI cards
        Row(
          children: [
            _kpiCard('Articles vendus', '${market.totalArticlesSold}', Icons.shopping_bag_outlined, AppTheme.primary),
            const SizedBox(width: 10),
            _kpiCard('Recette', '${market.totalRevenue.toStringAsFixed(2)} €', Icons.euro, AppTheme.success),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            _kpiCard('Produits diff.', '${market.uniqueProductsSold}', Icons.category_outlined, AppTheme.warning),
            const SizedBox(width: 10),
            _kpiCard('Moy./vente', market.sales.isNotEmpty
                ? '${(market.totalRevenue / market.sales.length).toStringAsFixed(2)} €'
                : '—', Icons.trending_up, AppTheme.accent),
          ],
        ),
        const SizedBox(height: 16),

        // Sales breakdown by product
        if (sortedSales.isNotEmpty) ...[
          const Text('Ventes par produit', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primaryDark)),
          const SizedBox(height: 8),
          ...sortedSales.map((s) => Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryFaded,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.borderLight),
                ),
                child: Row(
                  children: [
                    Expanded(child: Text(s.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                    Text('×${s.quantity}', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    const SizedBox(width: 12),
                    Text('${s.revenue.toStringAsFixed(2)} €',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.primary)),
                  ],
                ),
              )),
        ],

        // Last sales feed
        if (market.sales.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('Dernières ventes', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primaryDark)),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _undoLastSale(market),
                icon: const Icon(Icons.undo, size: 16),
                label: const Text('Annuler dernière'),
                style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ...market.sales.reversed.take(10).map((sale) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outline, size: 14, color: AppTheme.success),
                    const SizedBox(width: 6),
                    Expanded(child: Text('${sale.quantity}× ${sale.productName}', style: const TextStyle(fontSize: 12))),
                    Text('${sale.total.toStringAsFixed(2)} €',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primary)),
                  ],
                ),
              )),
        ],

        const SizedBox(height: 24),
        // End market button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _endMarket(market),
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Terminer le marché'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.danger,
              side: const BorderSide(color: AppTheme.danger),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 80),
      ],
    );
  }

  // ─── Market List (no active market) ───

  Widget _buildMarketList() {
    final past = _pastMarkets;
    if (past.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 100),
          Icon(Icons.storefront_outlined, size: 72, color: AppTheme.borderLight),
          SizedBox(height: 16),
          Text('Aucun marché', textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
          SizedBox(height: 8),
          Text('Lancez votre premier marché pour commencer\nà enregistrer vos ventes.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppTheme.textLight)),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: past.length,
      itemBuilder: (_, i) => _pastMarketCard(past[i]),
    );
  }

  Widget _pastMarketCard(MarketModel market) {
    final dateStr = DateFormat('dd/MM/yyyy – HH:mm', 'fr_FR').format(market.startedAt);
    final duration = market.duration;
    final durationStr = '${duration.inHours}h${(duration.inMinutes % 60).toString().padLeft(2, '0')}';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showReport(market),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.storefront_outlined, size: 20, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(market.name,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.primaryDark)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18, color: AppTheme.danger),
                    onPressed: () => _deleteMarket(market),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('$dateStr  •  $durationStr${market.location != null ? '  •  📍 ${market.location}' : ''}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
              const SizedBox(height: 10),
              Row(
                children: [
                  _miniStat('Articles', '${market.totalArticlesSold}'),
                  _miniStat('Recette', '${market.totalRevenue.toStringAsFixed(2)} €'),
                  _miniStat('Produits', '${market.uniqueProductsSold}'),
                ],
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: Text('Voir le compte rendu →',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.primary)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showReport(MarketModel market) {
    final duration = market.duration;
    final durationStr = '${duration.inHours}h${(duration.inMinutes % 60).toString().padLeft(2, '0')}';
    final dateStr = DateFormat('dd/MM/yyyy – HH:mm', 'fr_FR').format(market.startedAt);

    // Group sales by product
    final salesByProduct = <String, _ProductSalesSummary>{};
    for (final sale in market.sales) {
      final entry = salesByProduct.putIfAbsent(
        sale.productId,
        () => _ProductSalesSummary(name: sale.productName),
      );
      entry.quantity += sale.quantity;
      entry.revenue += sale.total;
    }
    final sortedSales = salesByProduct.values.toList()
      ..sort((a, b) => b.revenue.compareTo(a.revenue));

    // Best seller
    final bestSeller = sortedSales.isNotEmpty ? sortedSales.first : null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        builder: (_, ctrl) => ListView(
          controller: ctrl,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            // Title
            Row(
              children: [
                const Icon(Icons.receipt_long, color: AppTheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Compte rendu — ${market.name}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.primaryDark)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('$dateStr  •  $durationStr${market.location != null ? '  •  📍 ${market.location}' : ''}',
                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
            const SizedBox(height: 20),

            // KPIs
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primaryFaded,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      _reportKpi('Recette totale', '${market.totalRevenue.toStringAsFixed(2)} €'),
                      _reportKpi('Articles vendus', '${market.totalArticlesSold}'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _reportKpi('Produits diff.', '${market.uniqueProductsSold}'),
                      _reportKpi('Durée', durationStr),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _reportKpi('Moy./vente', market.sales.isNotEmpty
                          ? '${(market.totalRevenue / market.sales.length).toStringAsFixed(2)} €'
                          : '—'),
                      _reportKpi('€/heure', duration.inMinutes > 0
                          ? '${(market.totalRevenue / (duration.inMinutes / 60)).toStringAsFixed(2)} €'
                          : '—'),
                    ],
                  ),
                  if (bestSeller != null) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _reportKpi('🏆 Best-seller', '${bestSeller.name} (×${bestSeller.quantity})'),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Detail by product
            const Text('Détail des ventes', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primaryDark)),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.borderLight),
              ),
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: const BoxDecoration(
                      color: AppTheme.primaryFaded,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
                    ),
                    child: const Row(
                      children: [
                        Expanded(flex: 3, child: Text('PRODUIT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.textSecondary))),
                        Expanded(flex: 1, child: Text('QTÉ', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.textSecondary))),
                        Expanded(flex: 2, child: Text('TOTAL', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppTheme.textSecondary))),
                      ],
                    ),
                  ),
                  ...sortedSales.asMap().entries.map((e) {
                    final s = e.value;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: e.key.isEven ? Colors.transparent : AppTheme.primaryFaded,
                      ),
                      child: Row(
                        children: [
                          Expanded(flex: 3, child: Text(s.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                          Expanded(flex: 1, child: Text('${s.quantity}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary))),
                          Expanded(flex: 2, child: Text('${s.revenue.toStringAsFixed(2)} €', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primary))),
                        ],
                      ),
                    );
                  }),
                  // Total row
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: const BoxDecoration(
                      color: AppTheme.primaryFaded,
                      borderRadius: BorderRadius.vertical(bottom: Radius.circular(7)),
                    ),
                    child: Row(
                      children: [
                        const Expanded(flex: 3, child: Text('TOTAL', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primaryDark))),
                        Expanded(flex: 1, child: Text('${market.totalArticlesSold}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppTheme.primaryDark))),
                        Expanded(flex: 2, child: Text('${market.totalRevenue.toStringAsFixed(2)} €', textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppTheme.primaryDark))),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Chronological feed
            if (market.sales.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text('Historique chronologique', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primaryDark)),
              const SizedBox(height: 8),
              ...market.sales.asMap().entries.map((e) {
                final sale = e.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Text('#${e.key + 1}', style: const TextStyle(fontSize: 11, color: AppTheme.textLight, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 8),
                      Expanded(child: Text('${sale.quantity}× ${sale.productName}', style: const TextStyle(fontSize: 12))),
                      Text('${sale.total.toStringAsFixed(2)} €',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primary)),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  Widget _kpiCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(height: 6),
            Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
            Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primary)),
          Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _reportKpi(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.primaryDark)),
          Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}

// ─── Sale Form ───

class _SaleEntry {
  final String productId;
  final int quantity;
  final double unitPrice;
  _SaleEntry({required this.productId, required this.quantity, required this.unitPrice});
}

class _SaleForm extends StatefulWidget {
  final List<ProductModel> products;
  final Map<String, int> stocks;
  final List<CollectionModel> collections;
  const _SaleForm({required this.products, required this.stocks, required this.collections});

  @override
  State<_SaleForm> createState() => _SaleFormState();
}

class _SaleFormState extends State<_SaleForm> {
  String? _selectedProductId;
  int _quantity = 1;
  double? _customPrice;
  String _search = '';
  late final TextEditingController _searchCtrl;
  late final TextEditingController _priceCtrl;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
    _priceCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  ProductModel? get _selectedProduct =>
      _selectedProductId == null
          ? null
          : widget.products.cast<ProductModel?>().firstWhere((p) => p!.id == _selectedProductId, orElse: () => null);

  int get _maxQty => widget.stocks[_selectedProductId] ?? 0;

  double get _unitPrice => _customPrice ?? _selectedProduct?.sellingPrice ?? 0;

  List<ProductModel> get _filteredProducts {
    final sorted = [...widget.products]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (_search.isEmpty) return sorted;
    return sorted.where((p) => p.name.toLowerCase().contains(_search.toLowerCase())).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredProducts;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (_, ctrl) => SafeArea(
        top: false,
        child: Column(
          children: [
          // Header + search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(color: AppTheme.borderLight, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Enregistrer une vente',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppTheme.primaryDark)),
                const SizedBox(height: 12),
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Rechercher un produit...',
                    prefixIcon: const Icon(Icons.search, size: 18, color: AppTheme.textLight),
                    suffixIcon: _search.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 16),
                            onPressed: () { _searchCtrl.clear(); setState(() => _search = ''); },
                          )
                        : null,
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),

          // Alphabetically sorted + filtered product list
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('Aucun produit trouv\u00e9', style: TextStyle(color: AppTheme.textSecondary)))
                : ListView.builder(
                    controller: ctrl,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final p = filtered[i];
                      final stock = widget.stocks[p.id] ?? 0;
                      final col = p.collectionId == null
                          ? null
                          : widget.collections.cast<CollectionModel?>().firstWhere(
                              (c) => c!.id == p.collectionId, orElse: () => null);
                      final isSelected = _selectedProductId == p.id;
                      return GestureDetector(
                        onTap: () => setState(() {
                          _selectedProductId = p.id;
                          _quantity = 1;
                          _customPrice = null;
                          _priceCtrl.text = (p.sellingPrice ?? 0).toStringAsFixed(2);
                        }),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected ? AppTheme.primaryFaded : AppTheme.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? AppTheme.primary : AppTheme.borderLight,
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(p.name, style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: isSelected ? AppTheme.primaryDark : AppTheme.textColor,
                                    )),
                                    Row(
                                      children: [
                                        if (col != null)
                                          Text('${col.emoji} ${col.name}  \u00b7  ', style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                                        Text('stock : $stock', style: TextStyle(
                                          fontSize: 11,
                                          color: stock == 0 ? AppTheme.danger : AppTheme.textLight,
                                          fontWeight: stock == 0 ? FontWeight.w600 : FontWeight.normal,
                                        )),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                const Icon(Icons.check_circle, color: AppTheme.primary, size: 20),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Price / quantity / total + action buttons
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppTheme.borderLight)),
            ),
            child: Column(
              children: [
                if (_selectedProduct != null) ...[
                  Row(
                    children: [
                      const Text('Prix unitaire :', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 90,
                        child: TextField(
                          controller: _priceCtrl,
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            suffixText: '\u20ac',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (v) => setState(() => _customPrice = double.tryParse(v)),
                        ),
                      ),
                      const Spacer(),
                      const Text('Qt\u00e9 :', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                      IconButton(
                        onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                        icon: const Icon(Icons.remove_circle_outline),
                        iconSize: 26,
                        color: AppTheme.primary,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text('$_quantity', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                      ),
                      IconButton(
                        onPressed: _quantity < _maxQty ? () => setState(() => _quantity++) : null,
                        icon: const Icon(Icons.add_circle_outline),
                        iconSize: 26,
                        color: AppTheme.primary,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      Text('/ $_maxQty', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    decoration: BoxDecoration(color: AppTheme.primaryFaded, borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      'Total : ${(_unitPrice * _quantity).toStringAsFixed(2)} \u20ac',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.primaryDark),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                Padding(
                  padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom + 16),
                  child: Row(
                    children: [
                      Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler'))),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _selectedProductId != null && _quantity > 0 && _unitPrice > 0
                              ? () => Navigator.pop(context, _SaleEntry(
                                  productId: _selectedProductId!,
                                  quantity: _quantity,
                                  unitPrice: _unitPrice,
                                ))
                              : null,
                          child: const Text('Valider'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductSalesSummary {
  final String name;
  int quantity = 0;
  double revenue = 0;
  _ProductSalesSummary({required this.name});
}