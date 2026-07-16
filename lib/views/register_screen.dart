import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../viewmodels/auth_viewmodel.dart';
import '../models/budget_model.dart';
import '../utils/app_theme.dart';
import '../utils/constants.dart';

/// [RegisterScreen] handles the multi-step user registration process.
/// Phase 1: Authentication credentials (Email, Password).
/// Phase 2: User Profile (Name, Income) and initial Budget Allocations.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _pageController = PageController();
  int _currentPage = 0;

  // Phase 1 – Credentials
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _phase1Key = GlobalKey<FormState>();
  bool _obscurePass = true;
  bool _obscureConfirm = true;

  // Phase 2 – Profile & Budgets
  final _nameController = TextEditingController();
  final _incomeController = TextEditingController();
  final _phase2Key = GlobalKey<FormState>();

  // Default category state
  final Map<String, bool> _categoryChecked = {};
  final Map<String, TextEditingController> _budgetControllers = {};

  // Custom categories
  final List<Map<String, dynamic>> _customCategories = [];

  @override
  void initState() {
    super.initState();
    for (var cat in AppConstants.defaultCategories) {
      _categoryChecked[cat] = false;
      _budgetControllers[cat] = TextEditingController();
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _nameController.dispose();
    _incomeController.dispose();
    _pageController.dispose();
    for (var c in _budgetControllers.values) {
      c.dispose();
    }
    for (var custom in _customCategories) {
      (custom['nameController'] as TextEditingController).dispose();
      (custom['budgetController'] as TextEditingController).dispose();
    }
    super.dispose();
  }

  double get _totalBudget {
    double total = 0;
    for (var cat in AppConstants.defaultCategories) {
      if (cat == 'Others' || _categoryChecked[cat] == true) {
        total += double.tryParse(_budgetControllers[cat]!.text) ?? 0;
      }
    }
    for (var custom in _customCategories) {
      if (custom['checked'] == true) {
        total += double.tryParse(
                (custom['budgetController'] as TextEditingController).text) ??
            0;
      }
    }
    return total;
  }

  double get _monthlyIncome => double.tryParse(_incomeController.text) ?? 0;

  void _goToPage2() {
    if (!_phase1Key.currentState!.validate()) return;
    _pageController.animateToPage(
      1,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
    );
    setState(() => _currentPage = 1);
  }

  void _addCustomCategory() {
    setState(() {
      _customCategories.add({
        'nameController': TextEditingController(),
        'budgetController': TextEditingController(),
        'checked': true, // auto-checked when added
      });
    });
  }

  void _removeCustomCategory(int index) {
    setState(() {
      ((_customCategories[index]['nameController']) as TextEditingController)
          .dispose();
      ((_customCategories[index]['budgetController']) as TextEditingController)
          .dispose();
      _customCategories.removeAt(index);
    });
  }

  /// Validates Phase 2 inputs, checks budget constraints (e.g., > 75% income warning),
  /// and sends the final data to [AuthViewModel] to create the account.
  Future<void> _handleRegister() async {
    if (!_phase2Key.currentState!.validate()) return;

    final income = _monthlyIncome;
    final total = _totalBudget;

    // Must select at least 1 non-Others category
    final hasSelectedCategory = AppConstants.defaultCategories
            .where((c) => c != 'Others')
            .any((c) => _categoryChecked[c] == true) ||
        _customCategories.any((c) => c['checked'] == true);

    if (!hasSelectedCategory) {
      _showError(
          'Please select at least one expense category (other than Others).');
      return;
    }

    if (total > income) {
      _showError('Total budget (RM ${total.toStringAsFixed(0)}) exceeds '
          'monthly income (RM ${income.toStringAsFixed(0)}). '
          'Please reduce your budget allocations.');
      return;
    }

    if (total > income * 0.75) {
      final proceed = await _show75PercentWarning();
      if (proceed != true) return;
    }

    // Build budget list
    final budgets = <BudgetModel>[];

    // Always include Others (compulsory)
    budgets.add(BudgetModel(
      userId: '',
      category: 'Others',
      allocatedAmount:
          double.tryParse(_budgetControllers['Others']?.text ?? '') ?? 0,
    ));

    for (var cat in AppConstants.defaultCategories) {
      if (cat == 'Others') continue;
      if (_categoryChecked[cat] == true) {
        budgets.add(BudgetModel(
          userId: '',
          category: cat,
          allocatedAmount:
              double.tryParse(_budgetControllers[cat]!.text) ?? 0,
        ));
      }
    }
    for (var custom in _customCategories) {
      if (custom['checked'] == true) {
        final name =
            (custom['nameController'] as TextEditingController).text.trim();
        if (name.isNotEmpty) {
          budgets.add(BudgetModel(
            userId: '',
            category: name,
            allocatedAmount: double.tryParse(
                    (custom['budgetController'] as TextEditingController)
                        .text) ??
                0,
          ));
        }
      }
    }

    if (!mounted) return;
    final authVm = context.read<AuthViewModel>();
    final success = await authVm.register(
      email: _emailController.text,
      password: _passwordController.text,
      name: _nameController.text.trim(),
      monthlyIncome: income,
      budgets: budgets,
    );

    if (!mounted) return;
    if (success) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else {
      _showError(authVm.error ?? 'Registration failed.');
      authVm.clearError();
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.dangerRed,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<bool?> _show75PercentWarning() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: AppColors.secondaryGold, size: 28),
            const SizedBox(width: 8),
            const Text('Budget Warning'),
          ],
        ),
        content: const Text(
          'Your total budget exceeds 75% of your monthly income. '
          'It is encouraged to lower your expenses to ensure '
          'healthy financial habits.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Go back & adjust'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Continue anyway'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The main Scaffold wraps a PageView to allow sliding between Phase 1 and Phase 2.
    // A custom step indicator sits above the PageView.
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.primaryTealDark,
              AppColors.primaryTeal,
              AppColors.primaryTealLight,
              AppColors.backgroundCream,
            ],
            stops: [0.0, 0.3, 0.6, 1.0],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () {
                        if (_currentPage == 1) {
                          _pageController.animateToPage(0,
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeInOut);
                          setState(() => _currentPage = 0);
                        } else {
                          Navigator.pop(context);
                        }
                      },
                    ),
                    const Expanded(
                      child: Text(
                        'Create Account',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 48),
                  ],
                ),
              ),

              // Phase indicators
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 60),
                child: Row(
                  children: [
                    _buildStepIndicator(0, 'Credentials'),
                    Expanded(
                      child: Container(
                        height: 2,
                        color: _currentPage >= 1
                            ? AppColors.secondaryGold
                            : Colors.white38,
                      ),
                    ),
                    _buildStepIndicator(1, 'Profile'),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [_buildPhase1(), _buildPhase2()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator(int step, String label) {
    final isActive = _currentPage >= step;
    return Column(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor:
              isActive ? AppColors.secondaryGold : Colors.white38,
          child: Text(
            '${step + 1}',
            style: TextStyle(
              color: isActive ? AppColors.primaryTealDark : Colors.white70,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isActive ? Colors.white : Colors.white54,
          ),
        ),
      ],
    );
  }

  // ── Phase 1: Credentials ──
  /// Builds the UI for entering Email, Password, and Password Confirmation.
  Widget _buildPhase1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.cardWhite,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Form(
          key: _phase1Key,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Login Credentials',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Set up your email and password',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  // Email format regex
                  final emailRegex = RegExp(
                      r'^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$');
                  if (!emailRegex.hasMatch(v.trim())) {
                    return 'Enter a valid email address';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                obscureText: _obscurePass,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePass
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () =>
                        setState(() => _obscurePass = !_obscurePass),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (v.length < 6) return 'At least 6 characters';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirm,
                decoration: InputDecoration(
                  labelText: 'Confirm Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureConfirm
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () => setState(
                        () => _obscureConfirm = !_obscureConfirm),
                  ),
                ),
                validator: (v) {
                  if (v != _passwordController.text) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 28),
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _goToPage2,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryTeal,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Next',
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Phase 2: Profile & Budget Setup ──
  /// Builds the UI for entering Name, Income, and selecting/allocating Budgets.
  /// Includes dynamic warnings if budgets exceed income limits.
  Widget _buildPhase2() {
    final income = _monthlyIncome;
    final total = _totalBudget;
    final remaining = income - total;
    final isOver = total > income;
    final isNear75 = total > income * 0.75 && !isOver;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        padding: const EdgeInsets.all(24),
        margin: const EdgeInsets.only(bottom: 30),
        decoration: BoxDecoration(
          color: AppColors.cardWhite,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Form(
          key: _phase2Key,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Basic Information',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Tell us about yourself & set up budgets',
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _incomeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Monthly Income (RM)',
                  prefixIcon: Icon(Icons.attach_money),
                ),
                onChanged: (_) => setState(() {}),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Required';
                  if (double.tryParse(v) == null) return 'Enter a valid number';
                  if (double.parse(v) <= 0) return 'Must be greater than 0';
                  return null;
                },
              ),
              const SizedBox(height: 24),
              const Text(
                'Budget Categories',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Select expenses to monitor and allocate budgets',
                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
              ),
              const SizedBox(height: 12),

              // Default categories (Others is always shown first, mandatory)
              _buildCategoryRow('Others'),
              ...AppConstants.defaultCategories
                  .where((c) => c != 'Others')
                  .map((cat) => _buildCategoryRow(cat)),

              // Custom categories
              ..._customCategories.asMap().entries.map(
                    (entry) => _buildCustomCategoryRow(entry.key),
                  ),

              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _addCustomCategory,
                icon: const Icon(Icons.add_circle_outline,
                    color: AppColors.primaryTeal),
                label: const Text('Add custom category',
                    style: TextStyle(color: AppColors.primaryTeal)),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  alignment: Alignment.centerLeft,
                ),
              ),
              const SizedBox(height: 16),

              // Budget summary box
              if (income > 0)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isOver
                        ? AppColors.dangerRed.withValues(alpha: 0.08)
                        : isNear75
                            ? AppColors.secondaryGold.withValues(alpha: 0.12)
                            : AppColors.primaryTeal.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isOver
                          ? AppColors.dangerRed.withValues(alpha: 0.3)
                          : isNear75
                              ? AppColors.secondaryGold.withValues(alpha: 0.5)
                              : AppColors.primaryTeal.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total Allocated:',
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                          Text(
                            'RM ${total.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isOver
                                  ? AppColors.dangerRed
                                  : AppColors.primaryTeal,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            isOver ? 'Exceeds by:' : 'Remaining:',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.textMuted),
                          ),
                          Text(
                            isOver
                                ? '-RM ${(total - income).toStringAsFixed(0)}'
                                : 'RM ${remaining.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isOver
                                  ? AppColors.dangerRed
                                  : AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                      if (isOver) ...[
                        const SizedBox(height: 6),
                        Row(children: [
                          const Icon(Icons.error,
                              color: AppColors.dangerRed, size: 14),
                          const SizedBox(width: 4),
                          const Expanded(
                            child: Text(
                              'Total budget cannot exceed monthly income!',
                              style: TextStyle(
                                  color: AppColors.dangerRed,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ]),
                      ] else if (isNear75) ...[
                        const SizedBox(height: 6),
                        Row(children: [
                          Icon(Icons.warning_amber_rounded,
                              color: AppColors.secondaryGold, size: 14),
                          const SizedBox(width: 4),
                          const Expanded(
                            child: Text(
                              'Budget exceeds 75% of income. Consider saving more!',
                              style: TextStyle(
                                  color: AppColors.alertCoral, fontSize: 11),
                            ),
                          ),
                        ]),
                      ],
                    ],
                  ),
                ),

              const SizedBox(height: 24),
              Consumer<AuthViewModel>(
                builder: (_, authVm, _) => SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed:
                        authVm.isLoading ? null : _handleRegister,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryTeal,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: authVm.isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text('Register',
                            style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryRow(String cat) {
    // 'Others' is compulsory — show locked row with budget input
    if (cat == 'Others') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: true,
                onChanged: null, // locked
                activeColor: AppColors.textMuted,
              ),
            ),
            const SizedBox(width: 8),
            Icon(AppConstants.getCategoryIcon(cat),
                size: 20, color: AppConstants.getCategoryColor(cat)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Others',
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  const Text('Compulsory',
                      style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textMuted,
                          fontStyle: FontStyle.italic)),
                ],
              ),
            ),
            SizedBox(
              width: 110,
              child: TextFormField(
                controller: _budgetControllers['Others'],
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'RM 0',
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  filled: true,
                  fillColor: AppColors.cardWhite,
                ),
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
      );
    }

    final isChecked = _categoryChecked[cat] ?? false;
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
                setState(() => _categoryChecked[cat] = v ?? false);
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
          SizedBox(
            width: 110,
            child: TextFormField(
              controller: _budgetControllers[cat],
              enabled: isChecked,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'RM 0',
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                filled: true,
                fillColor:
                    isChecked ? AppColors.cardWhite : Colors.grey.shade100,
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomCategoryRow(int index) {
    final custom = _customCategories[index];
    final isChecked = custom['checked'] as bool;
    final nameCtrl = custom['nameController'] as TextEditingController;
    final budgetCtrl = custom['budgetController'] as TextEditingController;

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
                setState(() => custom['checked'] = v ?? false);
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
                    EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 90,
            child: TextFormField(
              controller: budgetCtrl,
              enabled: isChecked,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'RM 0',
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                filled: true,
                fillColor:
                    isChecked ? AppColors.cardWhite : Colors.grey.shade100,
              ),
              style: const TextStyle(fontSize: 14),
            ),
          ),
          SizedBox(
            width: 30,
            child: IconButton(
              icon: const Icon(Icons.close, size: 18),
              padding: EdgeInsets.zero,
              onPressed: () => _removeCustomCategory(index),
            ),
          ),
        ],
      ),
    );
  }
}
