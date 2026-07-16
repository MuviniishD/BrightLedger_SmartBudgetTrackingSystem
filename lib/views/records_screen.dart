import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../viewmodels/records_viewmodel.dart';
import '../viewmodels/home_viewmodel.dart';
import '../viewmodels/stats_viewmodel.dart';
import '../models/expense_model.dart';
import '../services/auth_service.dart';
import '../utils/app_theme.dart';
import '../utils/constants.dart';

class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key});

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userId = context.read<AuthService>().currentUser?.uid;
      if (userId != null) {
        context.read<RecordsViewModel>().listenToRecords(userId);
      }
    });
  }

  Future<void> _pickDateRange(RecordsViewModel vm) async {
    final now = DateTime.now();
    final initialRange = vm.hasDateFilter
        ? DateTimeRange(
            start: vm.dateRangeStart!,
            end: vm.dateRangeEnd!,
          )
        : DateTimeRange(
            start: now.subtract(const Duration(days: 30)),
            end: now,
          );

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: initialRange,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(
            primary: AppColors.primaryTeal,
            onPrimary: Colors.white,
            surface: AppColors.cardWhite,
          ),
        ),
        child: child!,
      ),
    );

    if (picked != null) {
      vm.filterByDateRange(picked.start, picked.end);
    }
  }

  /// Opens a modal sheet allowing user to choose between editing or deleting the record.
  void _showRecordOptionsSheet(BuildContext context, ExpenseModel record, RecordsViewModel vm) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(ctx).colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Transaction Options',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined, color: AppColors.primaryTeal),
                title: const Text('Edit Transaction'),
                onTap: () {
                  Navigator.pop(ctx);
                  _showEditRecordDialog(context, record, vm);
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppColors.dangerRed),
                title: const Text('Delete Transaction', style: TextStyle(color: AppColors.dangerRed)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showDeleteRecordConfirmDialog(context, record, vm);
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  /// Dialog to confirm transaction deletion
  void _showDeleteRecordConfirmDialog(BuildContext context, ExpenseModel record, RecordsViewModel vm) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete Transaction'),
        content: Text('Are you sure you want to delete "${record.reference}"? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.dangerRed),
            onPressed: () async {
              final success = await vm.deleteRecord(record.id!);
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(success ? 'Record deleted successfully!' : 'Failed to delete record.'),
                    backgroundColor: success ? AppColors.successGreen : AppColors.dangerRed,
                  ),
                );
                if (success) {
                  final userId = context.read<AuthService>().currentUser?.uid;
                  if (userId != null) {
                    context.read<HomeViewModel>().loadData(userId);
                    context.read<StatsViewModel>().loadStats(userId);
                  }
                }
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  /// Dialog to edit reference name and category choices
  void _showEditRecordDialog(BuildContext context, ExpenseModel record, RecordsViewModel vm) {
    final refController = TextEditingController(text: record.reference);
    final formKey = GlobalKey<FormState>();
    final categories = record.isIncome ? vm.incomeCategories : vm.expenseCategories;
    String currentCategory = categories.contains(record.category)
        ? record.category
        : (categories.isNotEmpty ? categories.first : record.category);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(record.isIncome ? 'Edit Income Details' : 'Edit Expense Details'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: refController,
                  decoration: InputDecoration(
                    labelText: record.isIncome ? 'Source' : 'Reference',
                    hintText: 'e.g. Shop or Source name',
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Please enter a name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                const Text(
                  'Category:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: currentCategory,
                      isExpanded: true,
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() {
                            currentCategory = val;
                          });
                        }
                      },
                      items: categories.map((cat) {
                        return DropdownMenuItem<String>(
                          value: cat,
                          child: Text(cat),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                final success = await vm.updateRecord(
                  record.id!,
                  refController.text.trim(),
                  currentCategory,
                );
                if (ctx.mounted) Navigator.pop(ctx);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(success ? 'Record updated successfully!' : 'Failed to update record.'),
                      backgroundColor: success ? AppColors.successGreen : AppColors.dangerRed,
                    ),
                  );
                  if (success) {
                    final userId = context.read<AuthService>().currentUser?.uid;
                    if (userId != null) {
                      context.read<HomeViewModel>().loadData(userId);
                      context.read<StatsViewModel>().loadStats(userId);
                    }
                  }
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = Provider.of<RecordsViewModel>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;

    // Reactively load categories if only 'All' is present
    if (vm.availableCategories.length == 1 && vm.availableCategories.first == 'All') {
      final userId = context.read<AuthService>().currentUser?.uid;
      if (userId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          vm.loadCategories(userId);
        });
      }
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                      child: const Icon(Icons.receipt,
                          color: AppColors.primaryTealDark, size: 24),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Recent records',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold)),
                          Text('Filter by category and search by date/name',
                              overflow: TextOverflow.ellipsis,
                              style:
                                  TextStyle(color: Colors.white70, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Category filter chips (2 rows, scrollable/swipeable)
              Builder(
                builder: (context) {
                  final total = vm.availableCategories.length;
                  final half = (total / 2).ceil();
                  final row1Categories = vm.availableCategories.sublist(0, half);
                  final row2Categories = vm.availableCategories.sublist(half);

                  Widget buildChip(String cat) {
                    final isSelected = vm.selectedCategory == cat;
                    return ChoiceChip(
                      label: Text(cat),
                      selected: isSelected,
                      selectedColor: isDark
                          ? AppColors.primaryTealLight.withValues(alpha: 0.3)
                          : AppColors.primaryTeal.withValues(alpha: 0.15),
                      labelStyle: TextStyle(
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSelected
                            ? (isDark ? Colors.white : AppColors.primaryTeal)
                            : (isDark ? Colors.white70 : Colors.black87),
                      ),
                      onSelected: (selected) {
                        if (selected) {
                          vm.filterByCategory(cat);
                          vm.searchByDate(_searchController.text);
                        }
                      },
                    );
                  }

                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: row1Categories.map((cat) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 8, bottom: 8),
                              child: buildChip(cat),
                            );
                          }).toList(),
                        ),
                        Row(
                          children: row2Categories.map((cat) {
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: buildChip(cat),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  );
                }
              ),
              const SizedBox(height: 12),

              // Unified Search & Date filter field
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: vm.hasDateFilter
                      ? 'Date range: ${vm.dateFilterLabel}'
                      : 'Search shop name or date (e.g. 12 May)',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (vm.hasDateFilter)
                        IconButton(
                          icon: const Icon(Icons.clear, color: AppColors.alertCoral),
                          onPressed: () {
                            vm.clearDateFilter();
                            vm.searchByDate(_searchController.text);
                          },
                        ),
                      IconButton(
                        icon: Icon(Icons.calendar_today,
                            color: vm.hasDateFilter
                                ? AppColors.primaryTeal
                                : Colors.grey),
                        onPressed: () => _pickDateRange(vm),
                      ),
                    ],
                  ),
                  filled: true,
                  fillColor: isDark ? AppColors.darkCard : AppColors.cardWhite,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide(
                      color: isDark ? Colors.transparent : Colors.grey.shade300,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(
                      color: AppColors.primaryTeal,
                      width: 2,
                    ),
                  ),
                ),
                onChanged: (val) {
                  vm.searchByDate(val);
                },
              ),
              const SizedBox(height: 16),

              // Records list
              Expanded(
                child: vm.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : vm.filteredRecords.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.receipt_long,
                                    size: 60,
                                    color: AppColors.textMuted.withValues(alpha: 0.4)),
                                const SizedBox(height: 12),
                                const Text(
                                  'No records found.',
                                  style: TextStyle(color: AppColors.textMuted),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            itemCount: vm.filteredRecords.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final record = vm.filteredRecords[index];
                              final formattedDate =
                                  DateFormat('dd MMM yyyy').format(record.date);
                              final categoryColor =
                                  AppConstants.getCategoryColor(
                                      record.category);

                              return InkWell(
                                onTap: () => _showRecordOptionsSheet(context, record, vm),
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? AppColors.darkCard
                                        : AppColors.cardWhite,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Row(
                                    children: [
                                      // Icon
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: record.isIncome
                                              ? const Color(0xFFE8F5E9)
                                              : AppColors.alertCoralLight,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          record.isIncome
                                              ? Icons.arrow_downward
                                              : Icons.arrow_upward,
                                          color: record.isIncome
                                              ? AppColors.successGreen
                                              : AppColors.alertCoral,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      // Content
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              record.reference,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 14),
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                              children: [
                                                Container(
                                                  width: 8,
                                                  height: 8,
                                                  decoration: BoxDecoration(
                                                    color: categoryColor,
                                                    shape: BoxShape.circle,
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                Flexible(
                                                  child: Text(
                                                    '${record.category == "Others" || record.category == "Other" ? (record.isIncome ? "Others (Income)" : "Others (Expense)") : record.category} • $formattedDate',
                                                    overflow: TextOverflow.ellipsis,
                                                    style: const TextStyle(
                                                        color: AppColors.textMuted,
                                                        fontSize: 12),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      // Amount
                                      FittedBox(
                                        child: Text(
                                          '${record.isIncome ? "+" : "-"}RM ${record.amount.toStringAsFixed(1)}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 15,
                                            color: record.isIncome
                                                ? AppColors.successGreen
                                                : AppColors.alertCoral,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
