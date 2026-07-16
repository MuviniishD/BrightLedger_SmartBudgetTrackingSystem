import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../viewmodels/stats_viewmodel.dart';
import '../services/auth_service.dart';
import '../utils/app_theme.dart';
import '../utils/constants.dart';

/// [StatsScreen] provides comprehensive visual analytics for the user's finances.
/// It includes AI-generated insights, weekly bar charts, monthly pie charts,
/// and the ability to export these analytics as a PDF report.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStats());
  }

  /// Triggers a fetch of statistics data based on the selected month.
  Future<void> _loadStats() async {
    final userId = context.read<AuthService>().currentUser?.uid;
    if (userId != null) {
      await context.read<StatsViewModel>().loadStats(userId);
    }
  }

  /// Maps high-level comparison names or budget categories to correct colors
  Color _getChartColor(String name) {
    if (name == 'Expenses') return AppColors.alertCoral;
    if (name == 'Income') return AppColors.successGreen;
    return AppConstants.getCategoryColor(name);
  }

  // ─────────────────────────────────────────────────────────────
  // PDF Export
  // ─────────────────────────────────────────────────────────────

  /// Prompts the user to select which data they want to include in their PDF export
  /// (Expenses, Income, or Both).
  Future<void> _showExportDialog(StatsViewModel statsVm) async {
    final choice = await showDialog<StatsViewMode>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Download Stats PDF'),
        content: const Text('Which data would you like to export?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, StatsViewMode.expenses),
            child: const Text('Expenses'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, StatsViewMode.income),
            child: const Text('Income'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, StatsViewMode.both),
            child: const Text('Both'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );

    if (choice != null) {
      await _exportPdf(statsVm, choice);
    }
  }

  /// Generates a PDF report containing summaries, category breakdowns, and weekly data,
  /// then prompts the user to share or save the file.
  Future<void> _exportPdf(StatsViewModel statsVm, StatsViewMode mode) async {
    setState(() => _isExporting = true);
    try {
      final pdf = pw.Document();
      final monthLabel = DateFormat('MMMM yyyy').format(statsVm.selectedMonth);

      String modeLabel;
      switch (mode) {
        case StatsViewMode.expenses:
          modeLabel = 'Expenses';
          break;
        case StatsViewMode.income:
          modeLabel = 'Income';
          break;
        case StatsViewMode.both:
          modeLabel = 'Expenses & Income';
          break;
      }

      // Build category breakdown rows
      Map<String, double> categoryData;
      switch (mode) {
        case StatsViewMode.expenses:
          categoryData = statsVm.monthlyByCategory;
          break;
        case StatsViewMode.income:
          categoryData = statsVm.monthlyIncomeByCategory;
          break;
        case StatsViewMode.both:
          categoryData = {
            ...statsVm.monthlyByCategory
                .map((k, v) => MapEntry('[Exp] $k', v)),
            ...statsVm.monthlyIncomeByCategory
                .map((k, v) => MapEntry('[Inc] $k', v)),
          };
          break;
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          header: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'BrightLedger — Financial Report',
                style: pw.TextStyle(
                  fontSize: 22,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                '$modeLabel · $monthLabel',
                style: const pw.TextStyle(fontSize: 13, color: PdfColors.grey700),
              ),
              pw.Divider(thickness: 1, color: PdfColors.grey400),
              pw.SizedBox(height: 8),
            ],
          ),
          build: (ctx) => [
            // Summary section
            if (mode == StatsViewMode.expenses ||
                mode == StatsViewMode.both) ...[
              pw.Text(
                'Total Expenses: RM ${statsVm.totalMonthlyExpenses.toStringAsFixed(2)}',
                style: pw.TextStyle(
                    fontSize: 15,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.red700),
              ),
              pw.SizedBox(height: 6),
            ],
            if (mode == StatsViewMode.income ||
                mode == StatsViewMode.both) ...[
              pw.Text(
                'Total Income: RM ${statsVm.totalMonthlyIncome.toStringAsFixed(2)}',
                style: pw.TextStyle(
                    fontSize: 15,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.green700),
              ),
              pw.SizedBox(height: 6),
            ],
            if (mode == StatsViewMode.both) ...[
              () {
                final profit =
                    statsVm.totalMonthlyIncome - statsVm.totalMonthlyExpenses;
                final isProfit = profit >= 0;
                return pw.Text(
                  isProfit
                      ? 'Net Profit: RM ${profit.toStringAsFixed(2)}'
                      : 'Net Loss: RM ${profit.abs().toStringAsFixed(2)}',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: isProfit ? PdfColors.green800 : PdfColors.red800,
                  ),
                );
              }(),
              pw.SizedBox(height: 12),
            ],
            pw.SizedBox(height: 8),

            // Category breakdown table
            pw.Text(
              'Category Breakdown',
              style: pw.TextStyle(
                  fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(2),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('Category',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(8),
                      child: pw.Text('Amount (RM)',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    ),
                  ],
                ),
                ...categoryData.entries.map(
                  (e) => pw.TableRow(
                    children: [
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(e.key),
                      ),
                      pw.Padding(
                        padding: const pw.EdgeInsets.all(8),
                        child: pw.Text(e.value.toStringAsFixed(2)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 20),

            // Weekly breakdown
            pw.Text(
              'Weekly Breakdown',
              style: pw.TextStyle(
                  fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            // Weekly table header
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              columnWidths: mode == StatsViewMode.both
                  ? {
                      0: const pw.FlexColumnWidth(1.2),
                      1: const pw.FlexColumnWidth(2),
                      2: const pw.FlexColumnWidth(2),
                      3: const pw.FlexColumnWidth(2),
                    }
                  : {
                      0: const pw.FlexColumnWidth(1.5),
                      1: const pw.FlexColumnWidth(3),
                    },
              children: [
                // Header row
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: mode == StatsViewMode.both
                      ? [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text('Week',
                                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text('Total Income (RM)',
                                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text('Total Expenses (RM)',
                                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text('Net (RM)',
                                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                          ),
                        ]
                      : [
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text('Week',
                                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.all(6),
                            child: pw.Text(
                                mode == StatsViewMode.expenses
                                    ? 'Total Expenses (RM)'
                                    : 'Total Income (RM)',
                                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
                          ),
                        ],
                ),
                // Data rows
                ...List.generate(statsVm.visibleWeekCount, (i) {
                  final weekMap = statsVm.displayWeeklyData.length > i
                      ? statsVm.displayWeeklyData[i]
                      : <String, double>{};

                  if (mode == StatsViewMode.both) {
                    final inc = weekMap['Income'] ?? 0.0;
                    final exp = weekMap['Expenses'] ?? 0.0;
                    final net = inc - exp;
                    final isProfit = net >= 0;
                    return pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('Week ${i + 1}', style: const pw.TextStyle(fontSize: 10)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(
                            '+ ${inc.toStringAsFixed(2)}',
                            style: pw.TextStyle(fontSize: 10, color: PdfColors.green700),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(
                            '- ${exp.toStringAsFixed(2)}',
                            style: pw.TextStyle(fontSize: 10, color: PdfColors.red700),
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(
                            isProfit
                                ? '+ ${net.toStringAsFixed(2)}'
                                : '- ${net.abs().toStringAsFixed(2)}',
                            style: pw.TextStyle(
                              fontSize: 10,
                              fontWeight: pw.FontWeight.bold,
                              color: isProfit ? PdfColors.green800 : PdfColors.red800,
                            ),
                          ),
                        ),
                      ],
                    );
                  } else {
                    final total = weekMap.values.fold(0.0, (a, b) => a + b);
                    return pw.TableRow(
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('Week ${i + 1}', style: const pw.TextStyle(fontSize: 10)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(
                            total.toStringAsFixed(2),
                            style: pw.TextStyle(
                              fontSize: 10,
                              color: mode == StatsViewMode.expenses
                                  ? PdfColors.red700
                                  : PdfColors.green700,
                            ),
                          ),
                        ),
                      ],
                    );
                  }
                }),
              ],
            ),
            pw.SizedBox(height: 20),

            // Footer
            pw.Divider(color: PdfColors.grey300),
            pw.Text(
              'Generated by BrightLedger on ${DateFormat('dd MMM yyyy, h:mm a').format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
          ],
        ),
      );

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/brightledger_${modeLabel.replaceAll(' ', '_')}_$monthLabel.pdf');
      await file.writeAsBytes(await pdf.save());

      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path)],
          text: 'BrightLedger $modeLabel Report — $monthLabel',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF export failed: $e'),
            backgroundColor: AppColors.dangerRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // The main scrollable view displays the header, month selector,
    // view mode toggle (Expenses/Income/Both), weekly bar chart, 
    // monthly pie chart, and the AI insights section.
    final statsVm = Provider.of<StatsViewModel>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final pastMonths = statsVm.getPast6Months();

    return Scaffold(
      body: SafeArea(
        child: statsVm.isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Header ──────────────────────────────────────────
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
                            child: const Icon(Icons.insights,
                                color: AppColors.primaryTealDark, size: 24),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Stats',
                                    style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold)),
                                Text('Past 6 months at a glance',
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

                    // ── Month dropdown ───────────────────────────────────
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkCard
                            : AppColors.cardWhite,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<DateTime>(
                          value: pastMonths.firstWhere(
                            (m) =>
                                m.year == statsVm.selectedMonth.year &&
                                m.month == statsVm.selectedMonth.month,
                            orElse: () => pastMonths[0],
                          ),
                          onChanged: (DateTime? newMonth) {
                            if (newMonth != null) {
                              final userId = context
                                  .read<AuthService>()
                                  .currentUser
                                  ?.uid;
                              if (userId != null) {
                                statsVm.selectMonth(newMonth, userId);
                              }
                            }
                          },
                          isExpanded: true,
                          icon: const Icon(Icons.arrow_drop_down,
                              color: AppColors.primaryTeal),
                          items: pastMonths.map((month) {
                            return DropdownMenuItem<DateTime>(
                              value: month,
                              child: Text(
                                DateFormat('MMMM yyyy').format(month),
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── View mode toggle ─────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkCard
                            : AppColors.cardWhite,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          _viewModeTab(statsVm, StatsViewMode.expenses,
                              'Expenses', isDark),
                          _viewModeTab(statsVm, StatsViewMode.income,
                              'Income', isDark),
                          _viewModeTab(
                              statsVm, StatsViewMode.both, 'Both', isDark),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    if (statsVm.displayTotal == 0)
                      Container(
                        padding: const EdgeInsets.all(40),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.darkCard
                              : AppColors.cardWhite,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(
                          child: Text(
                            'No ${_viewLabel(statsVm.viewMode)} recorded for this month.',
                            style:
                                const TextStyle(color: AppColors.textMuted),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    else ...[
                      // ── Weekly stacked bar chart ─────────────────────
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.darkCard
                              : AppColors.cardWhite,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              statsVm.viewMode == StatsViewMode.both
                                  ? 'Weekly Incomes vs Expenses'
                                  : 'Weekly ${_viewLabel(statsVm.viewMode)}',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 12),
                            // Legend
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: statsVm.displayByCategory.keys
                                  .map((cat) {
                                final color = _getChartColor(cat);
                                return Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                          color: color,
                                          shape: BoxShape.circle),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(cat,
                                        style:
                                            const TextStyle(fontSize: 11)),
                                  ],
                                );
                              }).toList(),
                            ),
                            const SizedBox(height: 24),
                            // Horizontal stacked bars (only visible weeks)
                            ...List.generate(
                              statsVm.visibleWeekCount,
                              (weekIndex) {
                                final weekData =
                                    statsVm.displayWeeklyData.length >
                                            weekIndex
                                        ? statsVm
                                            .displayWeeklyData[weekIndex]
                                        : <String, double>{};
                                final weekTotal = weekData.values
                                    .fold(0.0, (a, b) => a + b);

                                // Profit/Loss for "Both" mode
                                Widget weekLabel;
                                if (statsVm.viewMode == StatsViewMode.both) {
                                  final exp = weekData['Expenses'] ?? 0;
                                  final inc = weekData['Income'] ?? 0;
                                  final net = inc - exp;
                                  final isProfit = net >= 0;
                                  weekLabel = Text(
                                    isProfit
                                        ? 'Profit: RM ${net.toStringAsFixed(0)}'
                                        : 'Loss: RM ${net.abs().toStringAsFixed(0)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: isProfit
                                          ? AppColors.successGreen
                                          : AppColors.dangerRed,
                                    ),
                                  );
                                } else {
                                  weekLabel = Text(
                                    AppConstants.formatCurrency(weekTotal),
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textMuted),
                                  );
                                }

                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 8),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            'W${weekIndex + 1}',
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12),
                                          ),
                                          weekLabel,
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      ClipRRect(
                                        borderRadius:
                                            BorderRadius.circular(4),
                                        child: Container(
                                          height: 10,
                                          color: isDark
                                              ? Colors.grey.shade800
                                              : Colors.grey.shade200,
                                          child: weekTotal > 0
                                              ? Row(
                                                  children: weekData.entries
                                                      .map((entry) {
                                                    final ratio =
                                                        entry.value /
                                                            weekTotal;
                                                    if (ratio <= 0) {
                                                      return const SizedBox
                                                          .shrink();
                                                    }
                                                    return Expanded(
                                                      flex: (ratio * 100)
                                                          .round()
                                                          .clamp(1, 100),
                                                      child: Container(
                                                        color: _getChartColor(
                                                            entry.key),
                                                      ),
                                                    );
                                                  }).toList(),
                                                )
                                              : const SizedBox.shrink(),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Monthly donut chart ──────────────────────────
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.darkCard
                              : AppColors.cardWhite,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              statsVm.viewMode == StatsViewMode.both
                                  ? 'Monthly Incomes vs Expenses'
                                  : 'Monthly ${_viewLabel(statsVm.viewMode)}',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            // Display Total Expenses / Total Income ONLY in their individual sections
                            if (statsVm.viewMode == StatsViewMode.expenses)
                              Text(
                                'Total Expenses: ${AppConstants.formatCurrency(statsVm.totalMonthlyExpenses)}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.dangerRed,
                                ),
                              ),
                            if (statsVm.viewMode == StatsViewMode.income)
                              Text(
                                'Total Income: ${AppConstants.formatCurrency(statsVm.totalMonthlyIncome)}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.successGreen,
                                ),
                              ),
                            // Overall profit/loss line for "Both" mode
                            if (statsVm.viewMode == StatsViewMode.both) ...[
                              const SizedBox(height: 8),
                              Builder(builder: (_) {
                                final net = statsVm.totalMonthlyIncome -
                                    statsVm.totalMonthlyExpenses;
                                final isProfit = net >= 0;
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: isProfit
                                        ? AppColors.successGreen
                                            .withValues(alpha: 0.12)
                                        : AppColors.dangerRed
                                            .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    isProfit
                                        ? '📈 Net Profit: ${AppConstants.formatCurrency(net)}'
                                        : '📉 Net Loss: ${AppConstants.formatCurrency(net.abs())}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: isProfit
                                          ? AppColors.successGreen
                                          : AppColors.dangerRed,
                                    ),
                                  ),
                                );
                              }),
                            ],
                            const SizedBox(height: 24),
                            Row(
                              children: [
                                SizedBox(
                                  width: 140,
                                  height: 140,
                                  child: PieChart(
                                    PieChartData(
                                      sectionsSpace: 2,
                                      centerSpaceRadius: 40,
                                      sections: statsVm.displayByCategory
                                          .entries
                                          .map((entry) {
                                        final color = _getChartColor(entry.key);
                                        return PieChartSectionData(
                                          color: color,
                                          value: entry.value,
                                          radius: 20,
                                          title: '',
                                        );
                                      }).toList(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: statsVm.displayByCategory
                                        .entries
                                        .map((entry) {
                                      final color = _getChartColor(entry.key);
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 4),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 10,
                                              height: 10,
                                              decoration: BoxDecoration(
                                                  color: color,
                                                  shape: BoxShape.circle),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(entry.key,
                                                  style: const TextStyle(
                                                      fontSize: 12),
                                                  overflow:
                                                      TextOverflow.ellipsis),
                                            ),
                                            Text(
                                              AppConstants.formatCurrency(
                                                  entry.value),
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight:
                                                      FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // ── Download PDF button ──────────────────────────────
                    ElevatedButton.icon(
                      onPressed: _isExporting
                          ? null
                          : () => _showExportDialog(statsVm),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryTeal,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor:
                            AppColors.primaryTeal.withValues(alpha: 0.5),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: _isExporting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.picture_as_pdf),
                      label: Flexible(
                        child: Text(
                          _isExporting
                              ? 'Generating PDF…'
                              : 'Download Stats as PDF',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _viewModeTab(StatsViewModel vm, StatsViewMode mode, String label,
      bool isDark) {
    final isActive = vm.viewMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => vm.setViewMode(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: isActive ? AppColors.primaryTeal : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13,
              color: isActive
                  ? Colors.white
                  : (isDark ? Colors.white54 : AppColors.textMuted),
            ),
          ),
        ),
      ),
    );
  }

  String _viewLabel(StatsViewMode mode) {
    switch (mode) {
      case StatsViewMode.expenses:
        return 'Expenses';
      case StatsViewMode.income:
        return 'Income';
      case StatsViewMode.both:
        return 'Activity';
    }
  }
}
