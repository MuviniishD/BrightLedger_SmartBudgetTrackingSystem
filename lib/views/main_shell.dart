import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'home_screen.dart';
import 'add_screen.dart';
import 'records_screen.dart';
import 'stats_screen.dart';
import 'account_screen.dart';
import '../utils/app_theme.dart';
import '../utils/tab_notifier.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      const HomeScreen(),
      const AddScreen(),
      const RecordsScreen(),
      const StatsScreen(),
      const AccountScreen(),
    ];
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;

    // Listen to TabNotifier so any screen can switch tabs programmatically
    // (e.g. HomeScreen navigates to Add after OCR completes)
    final tabNotifier = Provider.of<TabNotifier>(context);
    if (tabNotifier.index != _selectedIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _selectedIndex != tabNotifier.index) {
          setState(() => _selectedIndex = tabNotifier.index);
        }
      });
    }

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (i) {
            _onItemTapped(i);
            // Keep TabNotifier in sync when user taps a tab manually
            context.read<TabNotifier>().jumpTo(i);
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor:
              isDark ? AppColors.darkSurface : AppColors.cardWhite,
          selectedItemColor: AppColors.secondaryGold,
          unselectedItemColor:
              isDark ? Colors.white60 : AppColors.textMuted,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          selectedLabelStyle:
              const TextStyle(fontWeight: FontWeight.bold),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.qr_code_scanner_outlined),
              activeIcon: Icon(Icons.qr_code_scanner),
              label: 'Add',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.receipt_long_outlined),
              activeIcon: Icon(Icons.receipt_long),
              label: 'Records',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.pie_chart_outline),
              activeIcon: Icon(Icons.pie_chart),
              label: 'Stats',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'Account',
            ),
          ],
        ),
      ),
    );
  }
}
