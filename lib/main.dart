import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'theme/app_theme.dart';
import 'screens/dashboard_screen.dart';
import 'screens/materials_screen.dart';
import 'screens/collections_screen.dart';
import 'screens/products_screen.dart';
import 'screens/stock_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/finance_screen.dart';
import 'screens/market_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR', null);
  runApp(const CoudCoeurApp());
}

class CoudCoeurApp extends StatelessWidget {
  const CoudCoeurApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Coud'Coeur",
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('fr', 'FR'), Locale('en', 'US')],
      locale: const Locale('fr', 'FR'),
      home: const MainScaffold(),
    );
  }
}

class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int _currentIndex = 0;
  final _productsChanged = ValueNotifier<int>(0);
  final _salesChanged = ValueNotifier<int>(0);

  static const List<_NavItem> _navItems = [
    _NavItem(Icons.home_outlined, Icons.home, 'Accueil'),
    _NavItem(Icons.web_asset_outlined, Icons.web_asset, 'Matieres'),
    _NavItem(Icons.folder_outlined, Icons.folder, 'Collections'),
    _NavItem(Icons.shopping_bag_outlined, Icons.shopping_bag, 'Produits'),
    _NavItem(Icons.inventory_2_outlined, Icons.inventory_2, 'Stocks'),
    _NavItem(Icons.storefront_outlined, Icons.storefront, 'Marchés'),
    _NavItem(Icons.calendar_month_outlined, Icons.calendar_month, 'Agenda'),
    _NavItem(Icons.euro_outlined, Icons.euro, 'Finances'),
  ];

  late List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      const DashboardScreen(),
      const MaterialsScreen(),
      const CollectionsScreen(),
      ProductsScreen(onNavigateTo: _navigateTo, onProductsChanged: () => _productsChanged.value++),
      StockScreen(productsChanged: _productsChanged),
      MarketScreen(onSalesChanged: () => _salesChanged.value++),
      const CalendarScreen(),
      FinanceScreen(salesChanged: _salesChanged),
    ];
  }

  void _navigateTo(int index) {
    setState(() => _currentIndex = index);
  }

  @override
  void dispose() {
    _productsChanged.dispose();
    _salesChanged.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_navItems[_currentIndex].label),
        leading: (_currentIndex == 2 || _currentIndex == 4)
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => _navigateTo(3),
              )
            : Builder(
                builder: (ctx) => IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(ctx).openDrawer(),
                ),
              ),
      ),
      drawer: _buildDrawer(),
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildBottomNav() {
    const bottomIndices = [0, 1, 3, 5, 6, 7];
    final currentBottomIndex = bottomIndices.contains(_currentIndex)
        ? bottomIndices.indexOf(_currentIndex)
        : (_currentIndex == 2 || _currentIndex == 4)
            ? bottomIndices.indexOf(3)
            : 0;

    return BottomNavigationBar(
      currentIndex: currentBottomIndex,
      onTap: (i) => _navigateTo(bottomIndices[i]),
      type: BottomNavigationBarType.fixed,
      selectedItemColor: AppTheme.primary,
      unselectedItemColor: AppTheme.textLight,
      backgroundColor: AppTheme.surface,
      selectedLabelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      unselectedLabelStyle: const TextStyle(fontSize: 11),
      items: bottomIndices.map((idx) {
        final item = _navItems[idx];
        final isActive = _currentIndex == idx;
        return BottomNavigationBarItem(
          icon: Icon(isActive ? item.activeIcon : item.icon),
          label: item.label,
        );
      }).toList(),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: AppTheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppTheme.primaryDark, AppTheme.primary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.all(8),
                    child: SvgPicture.asset(
                      'assets/images/logo.svg',
                      colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    "Coud'Coeur",
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const Text(
                    'Gestion de couture',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _navItems.length,
                itemBuilder: (_, i) {
                  final item = _navItems[i];
                  final isActive = _currentIndex == i;
                  return ListTile(
                    leading: Icon(
                      isActive ? item.activeIcon : item.icon,
                      color: isActive ? AppTheme.primary : AppTheme.textSecondary,
                    ),
                    title: Text(
                      item.label,
                      style: TextStyle(
                        fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                        color: isActive ? AppTheme.primary : AppTheme.textColor,
                      ),
                    ),
                    selected: isActive,
                    selectedTileColor: AppTheme.primaryFaded,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    onTap: () {
                      Navigator.pop(context);
                      _navigateTo(i);
                    },
                  );
                },
              ),
            ),
            const Divider(),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Synchronise avec AWS S3',
                style: TextStyle(fontSize: 11, color: AppTheme.textLight),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  const _NavItem(this.icon, this.activeIcon, this.label);
}
