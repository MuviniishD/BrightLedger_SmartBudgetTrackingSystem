import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../viewmodels/account_viewmodel.dart';
import '../viewmodels/home_viewmodel.dart';
import '../viewmodels/add_viewmodel.dart';
import '../viewmodels/records_viewmodel.dart';
import '../viewmodels/stats_viewmodel.dart';
import '../services/auth_service.dart';
import '../models/budget_model.dart';
import '../utils/app_theme.dart';
import '../utils/constants.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  static const _settingsChannel = MethodChannel('com.example.brightledger/settings');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadProfile();
    });
  }

  Future<void> _loadProfile() async {
    final authService = context.read<AuthService>();
    final userId = authService.currentUser?.uid;
    if (userId != null) {
      final accountVm = context.read<AccountViewModel>();
      await accountVm.loadUser(userId);
      await accountVm.loadBudgets(userId);
    }
  }

  Future<void> _openNotificationSettings() async {
    try {
      await _settingsChannel.invokeMethod('openNotificationSettings');
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open settings: ${e.message}')),
        );
      }
    }
  }

  void _showEditCategoriesDialog() {
    final accountVm = context.read<AccountViewModel>();
    final userId = accountVm.user?.uid;
    if (userId == null) return;

    // 1. EXPENSE CATEGORIES STATE
    final List<String> editableDefaults = AppConstants.defaultCategories
        .where((c) => c != 'Others')
        .toList();
    final Map<String, bool> categoryChecked = {};
    final List<Map<String, dynamic>> customCategories = [];

    for (var cat in editableDefaults) {
      final ext = accountVm.budgets.firstWhere(
        (BudgetModel b) => b.category.toLowerCase() == cat.toLowerCase(),
        orElse: () => BudgetModel(userId: userId, category: '', allocatedAmount: 0),
      );
      categoryChecked[cat] = ext.category.isNotEmpty;
    }

    for (var b in accountVm.budgets) {
      final isDefault = AppConstants.defaultCategories.any(
        (cat) => cat.toLowerCase() == b.category.toLowerCase(),
      );
      if (!isDefault) {
        customCategories.add({
          'nameController': TextEditingController(text: b.category),
          'checked': true,
        });
      }
    }

    // 2. INCOME CATEGORIES STATE
    final List<String> defaultIncomes = ['Earned', 'Investment', 'Passive'];
    final Map<String, bool> incomeChecked = {};
    final List<Map<String, dynamic>> customIncomes = [];
    final List<String> userIncomeCategories = accountVm.user?.selectedIncomeCategories ?? defaultIncomes;

    for (var cat in defaultIncomes) {
      incomeChecked[cat] = userIncomeCategories.any((u) => u.toLowerCase() == cat.toLowerCase());
    }

    for (var cat in userIncomeCategories) {
      final isDefault = defaultIncomes.any((d) => d.toLowerCase() == cat.toLowerCase());
      if (!isDefault) {
        customIncomes.add({
          'nameController': TextEditingController(text: cat),
          'checked': true,
        });
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return DefaultTabController(
              length: 2,
              child: AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: const Text('Edit Categories'),
                content: SizedBox(
                  width: double.maxFinite,
                  height: 380,
                  child: Column(
                    children: [
                      TabBar(
                        tabs: const [
                          Tab(text: 'Expenses'),
                          Tab(text: 'Incomes'),
                        ],
                        labelColor: AppColors.primaryTeal,
                        unselectedLabelColor: AppColors.textMuted,
                        indicatorColor: AppColors.primaryTeal,
                        indicatorSize: TabBarIndicatorSize.tab,
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: TabBarView(
                          children: [
                            _buildExpensesSection(dialogCtx, setDialogState, editableDefaults, categoryChecked, customCategories),
                            _buildIncomesSection(dialogCtx, setDialogState, defaultIncomes, incomeChecked, customIncomes),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      for (var c in customCategories) {
                        (c['nameController'] as TextEditingController).dispose();
                      }
                      for (var c in customIncomes) {
                        (c['nameController'] as TextEditingController).dispose();
                      }
                      Navigator.pop(ctx);
                    },
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: accountVm.isLoading
                        ? null
                        : () async {
                            // 1. Build budget/expense list
                            final newBudgets = <BudgetModel>[];
                            final othersExisting = accountVm.budgets.firstWhere(
                              (b) => b.category == 'Others',
                              orElse: () => BudgetModel(userId: userId, category: 'Others', allocatedAmount: 0),
                            );
                            newBudgets.add(othersExisting.category.isNotEmpty
                                ? othersExisting
                                : BudgetModel(userId: userId, category: 'Others', allocatedAmount: 0));

                            for (var cat in editableDefaults) {
                              if (categoryChecked[cat] == true) {
                                final existing = accountVm.budgets.firstWhere(
                                  (b) => b.category.toLowerCase() == cat.toLowerCase(),
                                  orElse: () => BudgetModel(userId: userId, category: cat, allocatedAmount: 0),
                                );
                                newBudgets.add(BudgetModel(
                                  userId: userId,
                                  category: cat,
                                  allocatedAmount: existing.allocatedAmount,
                                ));
                              }
                            }

                            for (var custom in customCategories) {
                              if (custom['checked'] == true) {
                                final name = (custom['nameController'] as TextEditingController).text.trim();
                                if (name.isNotEmpty) {
                                  final existing = accountVm.budgets.firstWhere(
                                    (b) => b.category.toLowerCase() == name.toLowerCase(),
                                    orElse: () => BudgetModel(userId: userId, category: name, allocatedAmount: 0),
                                  );
                                  newBudgets.add(BudgetModel(
                                    userId: userId,
                                    category: name,
                                    allocatedAmount: existing.allocatedAmount,
                                  ));
                                }
                              }
                            }

                            // 2. Build income categories list
                            final newIncomeCategories = <String>[];
                            for (var cat in defaultIncomes) {
                              if (incomeChecked[cat] == true) {
                                newIncomeCategories.add(cat);
                              }
                            }
                            for (var custom in customIncomes) {
                              if (custom['checked'] == true) {
                                final name = (custom['nameController'] as TextEditingController).text.trim();
                                if (name.isNotEmpty) {
                                  newIncomeCategories.add(name);
                                }
                              }
                            }

                            final success = await accountVm.updateCategoriesAndBudgets(
                              userId: userId,
                              newBudgets: newBudgets,
                              newIncomeCategories: newIncomeCategories,
                            );

                            if (ctx.mounted) Navigator.pop(ctx);
                            if (mounted) {
                              if (success) {
                                final homeVm = context.read<HomeViewModel>();
                                final addVm = context.read<AddViewModel>();
                                final recordsVm = context.read<RecordsViewModel>();
                                final statsVm = context.read<StatsViewModel>();
                                final uid = context.read<AuthService>().currentUser?.uid;
                                if (uid != null) {
                                  homeVm.loadData(uid);
                                  addVm.loadBudgets(uid);
                                  recordsVm.loadCategories(uid);
                                  statsVm.loadStats(uid);
                                }
                              }
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(success
                                      ? 'Categories updated successfully!'
                                      : accountVm.error ?? 'Failed to update.'),
                                  backgroundColor: success ? AppColors.successGreen : AppColors.dangerRed,
                                ),
                              );
                              accountVm.clearMessages();
                            }
                          },
                    child: accountVm.isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Save'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildExpensesSection(
      BuildContext dialogCtx,
      StateSetter setDialogState,
      List<String> editableDefaults,
      Map<String, bool> categoryChecked,
      List<Map<String, dynamic>> customCategories) {
    return ListView(
      shrinkWrap: true,
      children: [
        const Text(
          'Select the expense categories you want to track:',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: true,
                  onChanged: null,
                  activeColor: AppColors.textMuted,
                ),
              ),
              const SizedBox(width: 8),
              Icon(AppConstants.getCategoryIcon('Others'),
                  size: 20, color: AppConstants.getCategoryColor('Others')),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Others',
                    style: TextStyle(fontWeight: FontWeight.w500)),
              ),
              const Text('Compulsory',
                  style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textMuted,
                      fontStyle: FontStyle.italic)),
            ],
          ),
        ),
        ...editableDefaults.map((cat) {
          final isChecked = categoryChecked[cat] ?? false;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: isChecked,
                    activeColor: AppColors.primaryTeal,
                    onChanged: (v) {
                      setDialogState(() {
                        categoryChecked[cat] = v ?? false;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Icon(AppConstants.getCategoryIcon(cat),
                    size: 20, color: AppConstants.getCategoryColor(cat)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(cat,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                ),
              ],
            ),
          );
        }),
        ...customCategories.asMap().entries.map((entry) {
          final index = entry.key;
          final custom = entry.value;
          final isChecked = custom['checked'] as bool;
          final nameCtrl = custom['nameController'] as TextEditingController;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: isChecked,
                    activeColor: AppColors.primaryTeal,
                    onChanged: (v) {
                      setDialogState(() {
                        custom['checked'] = v ?? false;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Category name',
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    setDialogState(() {
                      nameCtrl.dispose();
                      customCategories.removeAt(index);
                    });
                  },
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () {
            setDialogState(() {
              customCategories.add({
                'nameController': TextEditingController(),
                'checked': true,
              });
            });
          },
          icon: const Icon(Icons.add_circle_outline,
              color: AppColors.primaryTeal, size: 18),
          label: const Text('Add custom expense',
              style: TextStyle(
                  color: AppColors.primaryTeal, fontSize: 13)),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            alignment: Alignment.centerLeft,
          ),
        ),
      ],
    );
  }

  Widget _buildIncomesSection(
      BuildContext dialogCtx,
      StateSetter setDialogState,
      List<String> defaultIncomes,
      Map<String, bool> incomeChecked,
      List<Map<String, dynamic>> customIncomes) {
    return ListView(
      shrinkWrap: true,
      children: [
        const Text(
          'Select the income categories you want to track:',
          style: TextStyle(fontSize: 13, color: AppColors.textMuted),
        ),
        const SizedBox(height: 12),
        ...defaultIncomes.map((cat) {
          final isChecked = incomeChecked[cat] ?? false;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: isChecked,
                    activeColor: AppColors.primaryTeal,
                    onChanged: (v) {
                      setDialogState(() {
                        incomeChecked[cat] = v ?? false;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.monetization_on_outlined,
                    size: 20, color: AppColors.successGreen),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(cat,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                ),
              ],
            ),
          );
        }),
        ...customIncomes.asMap().entries.map((entry) {
          final index = entry.key;
          final custom = entry.value;
          final isChecked = custom['checked'] as bool;
          final nameCtrl = custom['nameController'] as TextEditingController;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: isChecked,
                    activeColor: AppColors.primaryTeal,
                    onChanged: (v) {
                      setDialogState(() {
                        custom['checked'] = v ?? false;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      hintText: 'Category name',
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    setDialogState(() {
                      nameCtrl.dispose();
                      customIncomes.removeAt(index);
                    });
                  },
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () {
            setDialogState(() {
              customIncomes.add({
                'nameController': TextEditingController(),
                'checked': true,
              });
            });
          },
          icon: const Icon(Icons.add_circle_outline,
              color: AppColors.primaryTeal, size: 18),
          label: const Text('Add custom income',
              style: TextStyle(
                  color: AppColors.primaryTeal, fontSize: 13)),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            alignment: Alignment.centerLeft,
          ),
        ),
      ],
    );
  }

  void _showChangeEmailDialog() {
    final passwordController = TextEditingController();
    final newEmailController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Change Email'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: newEmailController,
                decoration: const InputDecoration(labelText: 'New Email'),
                validator: (v) => v == null || !v.contains('@') ? 'Enter a valid email' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Current Password'),
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          Consumer<AccountViewModel>(
            builder: (context, accountVm, child) => ElevatedButton(
              onPressed: accountVm.isLoading
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      final success = await accountVm.changeEmail(
                        passwordController.text,
                        newEmailController.text.trim(),
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(success
                                ? accountVm.successMessage ?? 'Verification email sent!'
                                : accountVm.error ?? 'Error changing email'),
                            backgroundColor: success ? AppColors.successGreen : AppColors.dangerRed,
                          ),
                        );
                        accountVm.clearMessages();
                      }
                    },
              child: const Text('Submit'),
            ),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog() {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Change Password'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: currentPasswordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Current Password'),
                validator: (v) => v == null || v.isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: newPasswordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New Password (min 6 chars)'),
                validator: (v) => v == null || v.length < 6 ? 'Too short' : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          Consumer<AccountViewModel>(
            builder: (context, accountVm, child) => ElevatedButton(
              onPressed: accountVm.isLoading
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      final success = await accountVm.changePassword(
                        currentPasswordController.text,
                        newPasswordController.text,
                      );
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(success
                                ? accountVm.successMessage ?? 'Password updated!'
                                : accountVm.error ?? 'Error updating password'),
                            backgroundColor: success ? AppColors.successGreen : AppColors.dangerRed,
                          ),
                        );
                        accountVm.clearMessages();
                      }
                    },
              child: const Text('Submit'),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete User Profile'),
        content: const Text(
          'Are you sure you want to delete your profile? This will permanently delete your account and all associated records and budgets. This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          Consumer<AccountViewModel>(
            builder: (context, accountVm, child) => ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.dangerRed),
              onPressed: accountVm.isLoading
                  ? null
                  : () async {
                      final authService = context.read<AuthService>();
                      final userId = authService.currentUser?.uid;
                      if (userId != null) {
                        final success = await accountVm.deleteUserProfile(userId);
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(success
                                  ? 'Profile and all data deleted.'
                                  : accountVm.error ?? 'Failed to delete user profile.'),
                              backgroundColor: success ? AppColors.successGreen : AppColors.dangerRed,
                            ),
                          );
                        }
                      }
                    },
              child: const Text('Delete', style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accountVm = Provider.of<AccountViewModel>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;

    final user = accountVm.user;
    final dateString = user != null
        ? DateFormat('MMMM yyyy').format(user.memberSince)
        : 'Loading...';

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // User profile header card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.primaryTeal,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: AppColors.secondaryGold,
                      child: const Icon(
                        Icons.person,
                        size: 36,
                        color: AppColors.primaryTealDark,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.name ?? 'Loading...',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            user?.email ?? 'Loading...',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Member since $dateString',
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Account section
              const Text(
                'Account',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : AppColors.cardWhite,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.email_outlined, color: AppColors.primaryTeal),
                      title: const Text('Change email'),
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      onTap: _showChangeEmailDialog,
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.lock_outline, color: AppColors.primaryTeal),
                      title: const Text('Change password'),
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      onTap: _showChangePasswordDialog,
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.category_outlined, color: AppColors.primaryTeal),
                      title: const Text('Edit category choices'),
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      onTap: _showEditCategoriesDialog,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Preferences section
              const Text(
                'Preferences',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : AppColors.cardWhite,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.notifications_outlined, color: AppColors.primaryTeal),
                      title: const Text('Notifications'),
                      subtitle: const Text('Manage alerts & notifications settings', style: TextStyle(fontSize: 11)),
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      onTap: _openNotificationSettings,
                    ),
                    const Divider(height: 1, indent: 56),
                    SwitchListTile(
                      secondary: Icon(
                        isDark ? Icons.dark_mode : Icons.light_mode,
                        color: AppColors.primaryTeal,
                      ),
                      title: const Text('Appearance'),
                      subtitle: Text(
                        isDark ? 'Dark mode' : 'Light mode',
                        style: const TextStyle(fontSize: 11),
                      ),
                      value: isDark,
                      activeThumbColor: AppColors.secondaryGold,
                      onChanged: (val) {
                        themeProvider.toggleTheme();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Data section
              const Text(
                'Data',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : AppColors.cardWhite,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.delete_forever_outlined, color: AppColors.dangerRed),
                      title: const Text('Delete user profile'),
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      onTap: _showDeleteConfirmDialog,
                    ),
                    const Divider(height: 1, indent: 56),
                    const ListTile(
                      leading: Icon(Icons.info_outline, color: AppColors.primaryTeal),
                      title: Text('About'),
                      subtitle: Text('Bright Ledger v1.0.0'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // Logout Button
              ElevatedButton.icon(
                onPressed: () async {
                  await context.read<AuthService>().signOut();
                  // Auth listener in main.dart handles navigation
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.dangerRed,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const Icon(Icons.logout),
                label: const Text(
                  'Log out',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
