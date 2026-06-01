import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/finance_model.dart';
import '../models/material_item.dart';
import '../models/product_model.dart';
import '../models/collection_model.dart';
import '../services/s3_service.dart';
import '../theme/app_theme.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<MaterialItem> _materials = [];
  List<ProductModel> _products = [];
  List<CollectionModel> _collections = [];
  Map<String, int> _stocks = {};
  double _totalOrders = 0;
  double _totalSales = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s3 = S3Service();
    final results = await Future.wait([
      s3.loadData('couture_materials'),
      s3.loadData('couture_products'),
      s3.loadData('couture_collections'),
      s3.loadJson('couture_stocks'),
      s3.loadData('couture_orders'),
      s3.loadData('couture_sales'),
    ]);
    if (!mounted) return;
    setState(() {
      _materials = results[0].map((e) => MaterialItem.fromJson(e as Map<String, dynamic>)).toList();
      _products = results[1].map((e) => ProductModel.fromJson(e as Map<String, dynamic>)).toList();
      _collections = results[2].map((e) => CollectionModel.fromJson(e as Map<String, dynamic>)).toList();
      final stocksRaw = results[3];
      _stocks = stocksRaw is Map
          ? stocksRaw.map((k, v) => MapEntry(k.toString(), (v as num).toInt()))
          : {};
      final orders = (results[4] as List).whereType<Map<String, dynamic>>().map((e) => FinanceOrder.fromJson(e)).toList();
      final sales = (results[5] as List).whereType<Map<String, dynamic>>().map((e) => FinanceSale.fromJson(e)).toList();
      _totalOrders = orders.fold(0.0, (s, o) => s + o.amount);
      _totalSales = sales.fold(0.0, (s, v) => s + v.total);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final categories = _materials.map((m) => m.category).toSet();
    final recent = [..._products]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final recentSlice = recent.take(6).toList();

    // Stock KPIs
    final totalStockItems = _products.fold<int>(0, (s, p) => s + (_stocks[p.id] ?? 0));
    final totalStockValue = _products.fold<double>(0, (s, p) => s + (_stocks[p.id] ?? 0) * (p.sellingPrice ?? 0));

    // Finance KPIs
    final balance = _totalSales - _totalOrders;
    final balancePositive = balance >= 0;

    return RefreshIndicator(
      onRefresh: _load,
      color: AppTheme.accent,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: _loading
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(color: AppTheme.accent),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Hero ──
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [AppTheme.primary, AppTheme.primaryLight],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        SvgPicture.asset(
                          'assets/images/logo.svg',
                          height: 80,
                          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          "Coud'Coeur",
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Gérez vos matières, créez vos produits\net calculez vos prix de revient.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // ── KPI cards (stock + finances) ──
                  Row(
                    children: [
                      _kpiCard(
                        icon: Icons.inventory_2_outlined,
                        label: 'Articles en stock',
                        value: '$totalStockItems',
                        color: AppTheme.primary,
                      ),
                      const SizedBox(width: 10),
                      _kpiCard(
                        icon: Icons.euro,
                        label: 'Valeur du stock',
                        value: '${totalStockValue.toStringAsFixed(0)} €',
                        color: AppTheme.success,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _financeBalanceCard(
                    sales: _totalSales,
                    orders: _totalOrders,
                    balance: balance,
                    positive: balancePositive,
                  ),

                  const SizedBox(height: 16),

                  // ── Stats grid (secondary) ──
                  GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: 2,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: 1.8,
                    children: [
                      _statCard(Icons.web_asset, '${_materials.length}', 'Matières'),
                      _statCard(Icons.shopping_bag_outlined, '${_products.length}', 'Produits'),
                      _statCard(Icons.label_outline, '${categories.length}', 'Catégories'),
                      _statCard(Icons.folder_outlined, '${_collections.length}', 'Collections'),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ── Quick actions ──
                  const Text(
                    'Accès rapide',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryDark,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _quickCard(
                          context,
                          icon: Icons.add_circle_outline,
                          title: 'Ajouter une matière',
                          subtitle: 'Tissus, fils, boutons...',
                          routeIndex: 1,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _quickCard(
                          context,
                          icon: Icons.add_shopping_cart,
                          title: 'Créer un produit',
                          subtitle: 'Calculez votre coût',
                          routeIndex: 3,
                        ),
                      ),
                    ],
                  ),

                  // ── Recent products ──
                  if (recentSlice.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Text(
                      'Produits récents',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryDark,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...recentSlice.map((p) {
                      final col = _collections.firstWhere(
                        (c) => c.id == p.collectionId,
                        orElse: () => CollectionModel(
                          id: '',
                          name: '',
                          createdAt: DateTime.now(),
                          updatedAt: DateTime.now(),
                        ),
                      );
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppTheme.primaryFaded,
                            child: const Icon(Icons.shopping_bag_outlined, color: AppTheme.primary, size: 20),
                          ),
                          title: Text(
                            p.name,
                            style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.primaryDark),
                          ),
                          subtitle: col.name.isNotEmpty ? Text(col.name, style: const TextStyle(fontSize: 12)) : null,
                          trailing: Text(
                            '${p.totalCost.toStringAsFixed(2)} €',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.primary,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      );
                    }),
                  ],

                  const SizedBox(height: 20),
                ],
              ),
      ),
    );
  }

  Widget _kpiCard({required IconData icon, required String label, required String value, required Color color}) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
                    Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _financeBalanceCard({required double sales, required double orders, required double balance, required bool positive}) {
    final color = positive ? AppTheme.success : AppTheme.danger;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(positive ? Icons.trending_up : Icons.trending_down, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${positive ? '+' : ''}${balance.toStringAsFixed(2)} €',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color),
                ),
                const Text('Solde finances (recettes − dépenses)', style: TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('↑ ${sales.toStringAsFixed(0)} €', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.success)),
              Text('↓ ${orders.toStringAsFixed(0)} €', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.danger)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statCard(IconData icon, String value, String label) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: AppTheme.accent, size: 24),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primary,
                ),
              ),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      );

  Widget _quickCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required int routeIndex,
  }) =>
      Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            _DashboardNavNotifier.of(context)?.navigate(routeIndex);
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppTheme.primary, AppTheme.primaryLight],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppTheme.primaryDark)),
                      Text(subtitle, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

// Simple inherited widget to allow Dashboard to trigger tab navigation
class _DashboardNavNotifier extends InheritedWidget {
  final void Function(int) navigate;

  const _DashboardNavNotifier({super.key, required this.navigate, required super.child});

  static _DashboardNavNotifier? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_DashboardNavNotifier>();

  @override
  bool updateShouldNotify(_DashboardNavNotifier oldWidget) => false;
}

// Expose the notifier so MainScaffold can wrap it
class DashboardNavNotifier extends _DashboardNavNotifier {
  const DashboardNavNotifier({super.key, required super.navigate, required super.child});
}
