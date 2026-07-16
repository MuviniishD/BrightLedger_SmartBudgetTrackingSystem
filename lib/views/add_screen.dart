import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../viewmodels/add_viewmodel.dart';
import '../viewmodels/home_viewmodel.dart';
import '../viewmodels/stats_viewmodel.dart';
import '../services/auth_service.dart';
import '../services/ocr_service.dart';
import '../services/ai_service.dart';
import '../models/expense_model.dart';
import '../utils/app_theme.dart';
import '../utils/constants.dart';

class AddScreen extends StatefulWidget {
  const AddScreen({super.key});

  @override
  State<AddScreen> createState() => _AddScreenState();
}

class _AddScreenState extends State<AddScreen> {
  final _formKey = GlobalKey<FormState>();
  final _referenceController = TextEditingController();
  final _amountController = TextEditingController();
  String? _selectedCategory;
  final Map<String, TextEditingController> _budgetControllers = {};
  bool _isIncome = false;
  bool _isOcrLoading = false;
  final _ocrService = OcrService();
  final _aiService = AIService();
  final _imagePicker = ImagePicker();

  static const List<String> _incomeCategories = [
    'Earned',
    'Investment',
    'Passive',
    'Others',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    final userId = context.read<AuthService>().currentUser?.uid;
    if (userId != null) {
      final addVm = context.read<AddViewModel>();
      await addVm.loadBudgets(userId);
      _initControllers(addVm);
    }
  }

  void _initControllers(AddViewModel addVm) {
    _budgetControllers.clear();
    for (var b in addVm.budgets) {
      _budgetControllers[b.category] = TextEditingController(
        text: b.allocatedAmount.toStringAsFixed(0),
      );
    }
    if (addVm.budgets.isNotEmpty && !_isIncome) {
      setState(() => _selectedCategory = addVm.budgets[0].category);
    }
    if (_isIncome && _selectedCategory == null) {
      final homeVm = context.read<HomeViewModel>();
      final incomeCats = homeVm.user?.selectedIncomeCategories ?? _incomeCategories;
      if (incomeCats.isNotEmpty) {
        setState(() => _selectedCategory = incomeCats[0]);
      }
    }
  }

  @override
  void dispose() {
    _referenceController.dispose();
    _amountController.dispose();
    for (var c in _budgetControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _saveRecord() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategory == null) {
      _showSnack('Please select a category', AppColors.dangerRed);
      return;
    }

    final userId = context.read<AuthService>().currentUser?.uid;
    if (userId == null) return;

    final double? amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) return;

    final record = ExpenseModel(
      userId: userId,
      reference: _referenceController.text.trim(),
      amount: amount,
      category: _selectedCategory!,
      date: DateTime.now(),
      isIncome: _isIncome,
    );

    final addVm = context.read<AddViewModel>();
    final success = await addVm.saveRecord(record);

    if (!mounted) return;
    if (success) {
      _showSnack(
          '${_isIncome ? "Income" : "Expense"} record saved!',
          AppColors.successGreen);
      _referenceController.clear();
      _amountController.clear();
      // Refresh Home, Stats and budget list with latest data
      final homeVm = context.read<HomeViewModel>();
      final statsVm = context.read<StatsViewModel>();
      homeVm.loadData(userId);
      statsVm.loadStats(userId);
      addVm.loadBudgets(userId);
    } else {
      _showSnack(addVm.error ?? 'Failed to save record.', AppColors.dangerRed);
    }
  }

  Future<void> _saveBudgets() async {
    final userId = context.read<AuthService>().currentUser?.uid;
    if (userId == null) return;

    final addVm = context.read<AddViewModel>();
    final amounts = <String, String>{};
    for (var entry in _budgetControllers.entries) {
      amounts[entry.key] = entry.value.text;
    }

    final success = await addVm.saveBudgets(userId, amounts);
    if (!mounted) return;
    _showSnack(
      success ? 'Budgets updated!' : (addVm.error ?? 'Failed to update budgets.'),
      success ? AppColors.successGreen : AppColors.dangerRed,
    );
    if (success) {
      // Refresh Home and Stats so budget progress bars are current
      context.read<HomeViewModel>().loadData(userId);
      context.read<StatsViewModel>().loadStats(userId);
    }
  }

  void _showSnack(String msg, Color bg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: bg),
    );
  }

  /// Shows a bottom sheet asking the user to pick Camera or Gallery,
  /// then runs the OCR scan and auto-fills the form fields.
  Future<void> _showOcrPicker() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(ctx).colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Text(
                  'Scan Receipt',
                  style: TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Choose how you\'d like to provide the receipt',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ocrSourceTile(
                      ctx,
                      icon: Icons.camera_alt,
                      label: 'Take Photo',
                      sub: 'Open camera',
                      source: ImageSource.camera,
                    ),
                    _ocrSourceTile(
                      ctx,
                      icon: Icons.photo_library,
                      label: 'From Gallery',
                      sub: 'Pick from storage',
                      source: ImageSource.gallery,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );

    if (source != null) await _runOcr(source);
  }

  Widget _ocrSourceTile(
    BuildContext ctx, {
    required IconData icon,
    required String label,
    required String sub,
    required ImageSource source,
  }) {
    return GestureDetector(
      onTap: () => Navigator.pop(ctx, source),
      child: Container(
        width: 140,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.primaryTeal.withValues(alpha: 0.08),
          border: Border.all(
              color: AppColors.primaryTeal.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, size: 36, color: AppColors.primaryTeal),
            const SizedBox(height: 10),
            Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 4),
            Text(sub,
                style: const TextStyle(
                    color: Colors.grey, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  /// Picks an image using [source], sends it to ocr.space, then uses
  /// Gemini AI to extract type, reference, amount, and category.
  Future<void> _runOcr(ImageSource source) async {
    final picked = await _imagePicker.pickImage(
      source: source,
      imageQuality: 90,
      maxWidth: 2000,
    );
    if (picked == null) return;

    setState(() => _isOcrLoading = true);

    try {
      final ocrResult = await _ocrService.scanReceipt(File(picked.path));
      if (!mounted) return;

      if (ocrResult == null) {
        _showSnack(
          '⚠️ Could not read receipt. Please fill in manually.',
          AppColors.alertCoral,
        );
        return;
      }

      // Now call Gemini AI with the raw OCR text for full analysis
      final addVm = context.read<AddViewModel>();
      final homeVm = context.read<HomeViewModel>();
      final expCats = addVm.budgets.map((b) => b.category).toList();
      final incCats = homeVm.user?.selectedIncomeCategories ?? ['Earned', 'Investment', 'Passive'];

      _showSnack('🤖 Analyzing receipt with AI…', AppColors.primaryTeal);

      final aiResult = await _aiService.analyzeReceiptText(
        rawText: ocrResult.rawText,
        availableExpenseCategories: expCats,
        availableIncomeCategories: incCats,
      );

      if (!mounted) return;

      if (aiResult != null) {
        setState(() {
          _isIncome = aiResult.isIncome;
          _referenceController.text = aiResult.reference;
          _amountController.text = aiResult.amount > 0
              ? aiResult.amount.toStringAsFixed(2)
              : ocrResult.amount.toStringAsFixed(2);
          _selectedCategory = aiResult.category;
        });
        _showSnack(
          '✅ AI filled: "${aiResult.reference}" • RM ${aiResult.amount.toStringAsFixed(2)} • ${aiResult.isIncome ? "Income" : "Expense"} • ${aiResult.category}',
          AppColors.successGreen,
        );
      } else {
        // Fallback to basic OCR data
        _referenceController.text = ocrResult.shopName;
        _amountController.text = ocrResult.amount.toStringAsFixed(2);
        _showSnack(
          '✅ OCR filled: "${ocrResult.shopName}" • RM ${ocrResult.amount.toStringAsFixed(2)}',
          AppColors.successGreen,
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnack('OCR failed: $e', AppColors.dangerRed);
      }
    } finally {
      if (mounted) setState(() => _isOcrLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final addVm = Provider.of<AddViewModel>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;

    // Reactively load budgets if they are empty and not loading
    if (addVm.budgets.isEmpty && !addVm.isLoading) {
      final userId = context.read<AuthService>().currentUser?.uid;
      if (userId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _loadData();
        });
      }
    }

    // Reactively populate controllers if they are empty but budgets have loaded
    if (_budgetControllers.isEmpty && addVm.budgets.isNotEmpty) {
      for (var b in addVm.budgets) {
        _budgetControllers[b.category] = TextEditingController(
          text: b.allocatedAmount.toStringAsFixed(0),
        );
      }
      if (_selectedCategory == null && !_isIncome) {
        _selectedCategory = addVm.budgets[0].category;
      }
    }

    // Consume a pending OCR result set from the Home screen
    if (addVm.pendingOcr != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final ocr = addVm.pendingOcr!;
        _referenceController.text = ocr.shopName;
        _amountController.text = ocr.amount.toStringAsFixed(2);

        // Apply AI-detected type and category
        setState(() {
          _isIncome = ocr.isIncome;
          if (ocr.category != null) {
            _selectedCategory = ocr.category;
          } else if (!ocr.isIncome && addVm.budgets.isNotEmpty) {
            _selectedCategory = addVm.budgets[0].category;
          }
        });

        addVm.clearOcrResult();
        _showSnack(
          '✅ AI filled: "${ocr.shopName}" • RM ${ocr.amount.toStringAsFixed(2)} • ${ocr.isIncome ? "Income" : "Expense"} • ${ocr.category ?? "—"}',
          AppColors.primaryTeal,
        );
      });
    }

    return Scaffold(
      body: SafeArea(
        child: addVm.isLoading && addVm.budgets.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: AppColors.primaryTeal,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: const BoxDecoration(
                                color: AppColors.secondaryGold,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.add_card,
                                  color: AppColors.primaryTealDark, size: 24),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Add record',
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 22,
                                          fontWeight: FontWeight.bold)),
                                  Text('Manual entry or receipt OCR auto-fill',
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: Colors.white70, fontSize: 13)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // OCR button
                      ElevatedButton.icon(
                        onPressed: _isOcrLoading ? null : _showOcrPicker,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryTeal,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor:
                              AppColors.primaryTeal.withValues(alpha: 0.5),
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: _isOcrLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.camera_alt),
                        label: Flexible(
                          child: Text(
                            _isOcrLoading
                                ? 'Scanning receipt…'
                                : 'Capture / upload receipt for OCR',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Record type toggle
                      Row(
                        children: [
                          const Text('Record type:',
                              style:
                                  TextStyle(fontWeight: FontWeight.bold)),
                          const Spacer(),
                          ChoiceChip(
                            label: const Text('Expense'),
                            selected: !_isIncome,
                            onSelected: (s) {
                              if (s) {
                                setState(() {
                                  _isIncome = false;
                                  _selectedCategory = addVm.budgets.isNotEmpty
                                      ? addVm.budgets[0].category
                                      : null;
                                });
                              }
                            },
                          ),
                          const SizedBox(width: 8),
                          ChoiceChip(
                            label: const Text('Income'),
                            selected: _isIncome,
                            onSelected: (s) {
                              if (s) {
                                setState(() {
                                  _isIncome = true;
                                  _selectedCategory = _incomeCategories[0];
                                });
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Reference / Source
                      TextFormField(
                        controller: _referenceController,
                        decoration: InputDecoration(
                          labelText: _isIncome ? 'Source' : 'Reference',
                          hintText: _isIncome
                              ? 'e.g. Monthly Salary'
                              : 'e.g. Sunrise Cafe',
                          prefixIcon: const Icon(Icons.label_outline),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Required'
                            : null,
                      ),
                      const SizedBox(height: 16),

                      // Amount
                      TextFormField(
                        controller: _amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Amount (RM)',
                          prefixIcon: Icon(Icons.attach_money),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Required';
                          if (double.tryParse(v) == null) {
                            return 'Enter a valid number';
                          }
                          if (double.parse(v) <= 0) {
                            return 'Must be greater than 0';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),

                      // Category selection
                      const Text('Select Category',
                          style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),

                       if (_isIncome) ...[
                        Builder(
                          builder: (context) {
                            final homeVm = Provider.of<HomeViewModel>(context);
                            var incomeCats = homeVm.user?.selectedIncomeCategories ?? _incomeCategories;
                            if (!incomeCats.contains('Others')) {
                              incomeCats = List.from(incomeCats)..add('Others');
                            }
                            return Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: incomeCats.map((cat) {
                                final isSelected = _selectedCategory == cat;
                                return ChoiceChip(
                                  label: Text(cat),
                                  selected: isSelected,
                                  onSelected: (s) {
                                    if (s) {
                                      setState(() => _selectedCategory = cat);
                                    }
                                  },
                                );
                              }).toList(),
                            );
                          }
                        )
                       ]
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: addVm.budgets.map((budget) {
                            final isSelected =
                                _selectedCategory == budget.category;
                            final color = AppConstants.getCategoryColor(
                                budget.category);
                            return ChoiceChip(
                              label: Text(budget.category),
                              selected: isSelected,
                              selectedColor: color.withValues(alpha: 0.2),
                              labelStyle: TextStyle(
                                color: isSelected
                                    ? color
                                    : (isDark
                                        ? Colors.white70
                                        : Colors.black87),
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                              onSelected: (s) {
                                if (s) {
                                  setState(
                                      () => _selectedCategory = budget.category);
                                }
                              },
                            );
                          }).toList(),
                        ),
                      const SizedBox(height: 24),

                      // Save record button
                      ElevatedButton.icon(
                        onPressed:
                            addVm.isLoading ? null : _saveRecord,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryTeal,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: addVm.isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.save),
                        label: Text(
                          _isIncome ? 'Save income' : 'Save expense',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Edit monthly budget per category (always visible)
                      if (addVm.budgets.isNotEmpty) ...[
                        const Text('Edit monthly budget per category',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: addVm.budgets.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final budget = addVm.budgets[index];
                            final color = AppConstants.getCategoryColor(
                                budget.category);
                            final ctrl =
                                _budgetControllers[budget.category];
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? AppColors.darkCard
                                    : AppColors.cardWhite,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                        color: color,
                                        shape: BoxShape.circle),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(budget.category,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600)),
                                  ),
                                  SizedBox(
                                    width: 120,
                                    child: TextFormField(
                                      controller: ctrl,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                                      ],
                                      textAlign: TextAlign.right,
                                      decoration: InputDecoration(
                                        prefixText: 'RM ',
                                        isDense: true,
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 8),
                                        filled: true,
                                        fillColor: isDark
                                            ? AppColors.darkSurface
                                            : Colors.grey.shade100,
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          borderSide: BorderSide.none,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        const SizedBox(height: 16),

                        // Save budgets button
                        ElevatedButton.icon(
                          onPressed: addVm.isSavingBudgets
                              ? null
                              : _saveBudgets,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.secondaryGold,
                            foregroundColor: AppColors.textDark,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          icon: addVm.isSavingBudgets
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.textDark),
                                )
                              : const Icon(Icons.save_as),
                          label: const Text('Save budgets',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
