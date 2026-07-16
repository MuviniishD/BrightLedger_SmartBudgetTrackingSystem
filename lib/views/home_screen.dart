import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../viewmodels/home_viewmodel.dart';
import '../viewmodels/add_viewmodel.dart';
import '../viewmodels/financial_chat_viewmodel.dart';
import '../services/auth_service.dart';
import '../services/ocr_service.dart';
import '../services/ai_service.dart';
import '../utils/app_theme.dart';
import '../utils/constants.dart';
import '../utils/tab_notifier.dart';

/// [HomeScreen] is the primary dashboard of the application. 
/// It displays an overview of the user's finances, including income vs expenses,
/// dynamically generated AI advice, budget progress bars, and the OCR receipt scanner.
/// It also serves as the entry point for the BrightBot AI chat assistant.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isOcrLoading = false;
  final _ocrService = OcrService();
  final _aiService = AIService();
  final _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshData());
  }

  /// Fetches the latest data from [HomeViewModel] and initializes the 
  /// AI chat session with the updated context.
  Future<void> _refreshData() async {
    final authService = context.read<AuthService>();
    final userId = authService.currentUser?.uid;
    if (userId != null) {
      final homeVm = context.read<HomeViewModel>();
      await homeVm.loadData(userId);
      if (mounted) {
        final chatVm = context.read<FinancialChatViewModel>();
        final userName = homeVm.user?.name ?? 'User';
        chatVm.initFromHomeViewModel(homeVm, userName);
      }
    }
  }

  /// Opens the BrightBot AI Chat assistant in a bottom sheet modal.
  void _openBrightBot(HomeViewModel homeVm) {
    final themeProvider = context.read<ThemeProvider>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => _BrightBotModal(
        homeVm: homeVm,
        isDark: themeProvider.isDarkMode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The main layout comprises a scrollable dashboard (header, summary cards,
    // AI advice banner, OCR button, and budget list) and a floating action button
    // for the BrightBot chat.
    final homeVm = Provider.of<HomeViewModel>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);
    final chatVm = Provider.of<FinancialChatViewModel>(context);
    final isDark = themeProvider.isDarkMode;

    return Scaffold(
      body: Stack(
        children: [
          // ── Main scrollable content ──────────────────────────────────
          SafeArea(
            child: homeVm.isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _refreshData,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // ── Header ─────────────────────────────────
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: AppColors.primaryTeal,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primaryTeal
                                      .withValues(alpha: 0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: const BoxDecoration(
                                    color: AppColors.secondaryGold,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.wb_sunny,
                                      color: AppColors.primaryTealDark,
                                      size: 24),
                                ),
                                const SizedBox(width: 14),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Bright Ledger',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 22,
                                              fontWeight: FontWeight.bold)),
                                      Text(
                                          'Your spending, instantly understood',
                                          style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 13)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // ── Income & Expense summary ────────────────
                          Row(
                            children: [
                              Expanded(
                                child: _summaryCard(
                                  isDark: isDark,
                                  color: const Color(0xFFE8F5E9),
                                  darkColor: const Color(0xFF1B3D2F),
                                  icon: Icons.arrow_downward,
                                  iconColor: AppColors.successGreen,
                                  label: 'Monthly income',
                                  value:
                                      '+RM ${homeVm.displayMonthlyIncome.toStringAsFixed(0)}',
                                  valueColor: AppColors.successGreen,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _summaryCard(
                                  isDark: isDark,
                                  color: AppColors.alertCoralLight,
                                  darkColor: const Color(0xFF3E2723),
                                  icon: Icons.arrow_upward,
                                  iconColor: AppColors.alertCoral,
                                  label: 'Monthly expenses',
                                  value:
                                      '-RM ${homeVm.totalExpenses.toStringAsFixed(0)}',
                                  valueColor: AppColors.alertCoral,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // ── Advice banner ───────────────────────────
                          if (homeVm.advice.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF3D2520)
                                    : AppColors.alertCoralLight,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: AppColors.alertCoral
                                      .withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.warning_amber_rounded,
                                      color: AppColors.alertCoral, size: 22),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      homeVm.advice,
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.white
                                            : AppColors.textDark,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 16),

                          // ── OCR button ──────────────────────────────
                          ElevatedButton.icon(
                            onPressed:
                                _isOcrLoading ? null : _showOcrPicker,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.alertCoral,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor:
                                  AppColors.alertCoral.withValues(alpha: 0.5),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            icon: _isOcrLoading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white),
                                  )
                                : const Icon(Icons.document_scanner),
                            label: Text(
                              _isOcrLoading
                                  ? 'Scanning receipt…'
                                  : 'Scan receipt with OCR',
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // ── Category budget sliders ─────────────────
                          const Text('Budgets per category',
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),

                          if (homeVm.budgets.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? AppColors.darkCard
                                    : AppColors.cardWhite,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Center(
                                child: Text(
                                  'No budget categories set up yet.',
                                  textAlign: TextAlign.center,
                                  style:
                                      TextStyle(color: AppColors.textMuted),
                                ),
                              ),
                            )
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: homeVm.budgets.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 16),
                              itemBuilder: (context, index) {
                                final budget = homeVm.budgets[index];
                                final used =
                                    homeVm.getUsedAmount(budget.category);
                                final remaining =
                                    homeVm.getRemainingAmount(budget);
                                final ratio =
                                    homeVm.getProgressRatio(budget);
                                final isOver = ratio >= 1.0;
                                final usedStr =
                                    AppConstants.formatCurrency(used);
                                final remStr = AppConstants.formatCurrency(remaining);

                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              budget.category,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                                color: isDark
                                                    ? Colors.white
                                                    : AppColors.textDark,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            AppConstants.formatCurrency(
                                                budget.allocatedAmount),
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: isDark
                                                  ? AppColors.secondaryGold
                                                  : AppColors.primaryTeal,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      ClipRRect(
                                        borderRadius:
                                            BorderRadius.circular(10),
                                        child: LinearProgressIndicator(
                                          value: ratio.clamp(0.0, 1.0),
                                          minHeight: 14,
                                          backgroundColor:
                                              const Color(0xFFE8F5E9),
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                            isOver
                                                ? const Color(0xFFF37365)
                                                : AppColors.successGreen,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Used $usedStr • Remaining $remStr',
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.textMuted,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),

                          // Extra space so FAB doesn't overlap last item
                          const SizedBox(height: 90),
                        ],
                      ),
                    ),
                  ),
          ),

          // ── Floating BrightBot button ────────────────────────────────
          Positioned(
            bottom: 20,
            right: 16,
            child: _buildChatFab(chatVm, homeVm),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Floating chat FAB
  // ──────────────────────────────────────────────────────────────────────────

  /// Builds the floating action button that opens BrightBot, complete with a 
  /// "teaser" message bubble and a badge for unread messages.
  Widget _buildChatFab(
      FinancialChatViewModel chatVm, HomeViewModel homeVm) {
    final msgCount = chatVm.messages.length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Teaser bubble floating next to the bot avatar
        GestureDetector(
          onTap: () => _openBrightBot(homeVm),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0F3D35),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: AppColors.secondaryGold.withValues(alpha: 0.5)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 8,
                ),
              ],
            ),
            child: const Text(
              'Ask BrightBot!',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ),

        // Robot face FAB
        Stack(
          clipBehavior: Clip.none,
          children: [
            GestureDetector(
              onTap: () => _openBrightBot(homeVm),
              child: Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF0F3D35), Color(0xFF0A2840)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryTeal.withValues(alpha: 0.5),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(Icons.auto_awesome,
                      color: AppColors.secondaryGold, size: 28),
                ),
              ),
            ),
            // Badge showing message count
            if (msgCount > 0)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: AppColors.alertCoral,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Center(
                    child: Text(
                      msgCount > 9 ? '9+' : '$msgCount',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // OCR helpers
  // ──────────────────────────────────────────────────────────────────────────

  /// Shows a bottom sheet letting the user choose between the camera or gallery
  /// to scan a receipt.
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
                const Text('Scan Receipt',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                const Text(
                  'Choose how you\'d like to provide the receipt',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ocrSourceTile(ctx,
                        icon: Icons.camera_alt,
                        label: 'Take Photo',
                        sub: 'Open camera',
                        source: ImageSource.camera),
                    _ocrSourceTile(ctx,
                        icon: Icons.photo_library,
                        label: 'From Gallery',
                        sub: 'Pick from storage',
                        source: ImageSource.gallery),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
    if (source != null) await _runOcrFromHome(source);
  }

  Widget _ocrSourceTile(BuildContext ctx,
      {required IconData icon,
      required String label,
      required String sub,
      required ImageSource source}) {
    return GestureDetector(
      onTap: () => Navigator.pop(ctx, source),
      child: Container(
        width: 140,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.alertCoral.withValues(alpha: 0.08),
          border:
              Border.all(color: AppColors.alertCoral.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, size: 36, color: AppColors.alertCoral),
            const SizedBox(height: 10),
            Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 4),
            Text(sub,
                style:
                    const TextStyle(color: Colors.grey, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Future<void> _runOcrFromHome(ImageSource source) async {
    final picked = await _imagePicker.pickImage(
        source: source, imageQuality: 90, maxWidth: 2000);
    if (picked == null || !mounted) return;
    setState(() => _isOcrLoading = true);
    try {
      final ocrResult = await _ocrService.scanReceipt(File(picked.path));
      if (!mounted) return;
      if (ocrResult == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              '⚠️ Could not detect shop or total. Fill in manually on the Add tab.'),
          backgroundColor: Colors.orange,
        ));
        context.read<TabNotifier>().jumpTo(1);
      } else {
        // Run Gemini AI analysis on the raw OCR text
        final addVm = context.read<AddViewModel>();
        final homeVm = context.read<HomeViewModel>();
        final expCats = addVm.budgets.map((b) => b.category).toList();
        final incCats = homeVm.user?.selectedIncomeCategories ?? ['Earned', 'Investment', 'Passive'];

        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('🤖 Analyzing receipt with AI…'),
          backgroundColor: Colors.blueGrey,
          duration: Duration(seconds: 2),
        ));

        final aiResult = await _aiService.analyzeReceiptText(
          rawText: ocrResult.rawText,
          availableExpenseCategories: expCats,
          availableIncomeCategories: incCats,
        );

        if (!mounted) return;

        if (aiResult != null) {
          // Build an enriched OcrResult with AI fields
          final enriched = ocrResult.copyWith(
            shopName: aiResult.reference,
            amount: aiResult.amount > 0 ? aiResult.amount : ocrResult.amount,
            isIncome: aiResult.isIncome,
            category: aiResult.category,
          );
          addVm.setOcrResult(enriched);
        } else {
          addVm.setOcrResult(ocrResult);
        }
        context.read<TabNotifier>().jumpTo(1);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('OCR failed: $e'),
          backgroundColor: AppColors.dangerRed,
        ));
      }
    } finally {
      if (mounted) setState(() => _isOcrLoading = false);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────

  Widget _summaryCard({
    required bool isDark,
    required Color color,
    required Color darkColor,
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
    required Color valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? darkColor : color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 16),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isDark ? Colors.white70 : AppColors.textDark,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(value,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: valueColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// BrightBot modal — full-screen chat sheet
// ══════════════════════════════════════════════════════════════════════════════

/// [_BrightBotModal] is the internal chat interface for the AI assistant.
/// It displays the message history and an input field, interacting directly
/// with [FinancialChatViewModel].
class _BrightBotModal extends StatefulWidget {
  final HomeViewModel homeVm;
  final bool isDark;
  const _BrightBotModal({required this.homeVm, required this.isDark});

  @override
  State<_BrightBotModal> createState() => _BrightBotModalState();
}

class _BrightBotModalState extends State<_BrightBotModal> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send(String text, FinancialChatViewModel chatVm) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || chatVm.isThinking) return;
    _inputController.clear();
    final userName = widget.homeVm.user?.name ?? 'User';
    await chatVm.sendMessage(trimmed, widget.homeVm, userName);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final isDark = widget.isDark;
    final bgColor = isDark ? const Color(0xFF0B1A27) : Colors.white;
    final textColor = isDark ? Colors.white : AppColors.textDark;
    final subtleColor = isDark ? Colors.white54 : Colors.black45;
    final inputBg = isDark
        ? Colors.white.withValues(alpha: 0.09)
        : Colors.grey.shade100;
    final inputBorder = isDark
        ? Colors.white.withValues(alpha: 0.15)
        : Colors.grey.shade300;
    final headerGradient = isDark
        ? const LinearGradient(
            colors: [Color(0xFF0F3D35), Color(0xFF0A2840)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : const LinearGradient(
            colors: [AppColors.primaryTeal, AppColors.primaryTealLight],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          );

    return Consumer<FinancialChatViewModel>(
      builder: (context, chatVm, _) {
        if (chatVm.hasMessages) _scrollToBottom();
        return Container(
          height: screenHeight * 0.87,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              // ── Drag handle ──────────────────────────────────────────
              Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(top: 12, bottom: 2),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // ── Header ───────────────────────────────────────────────
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: headerGradient,
                ),
                child: Row(
                  children: [
                    // Bot avatar
                    Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                        color: AppColors.secondaryGold,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.auto_awesome,
                          color: AppColors.primaryTealDark, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('BrightBot',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold)),
                          Row(
                            children: [
                              const Icon(Icons.circle,
                                  color: Color(0xFF4CAF50), size: 8),
                              const SizedBox(width: 4),
                              const Expanded(
                                child: Text(
                                  'Online • AI Financial Assistant',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: Colors.white60, fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Refresh (clear) button
                    if (chatVm.hasMessages)
                      IconButton(
                        icon: const Icon(Icons.refresh,
                            color: Colors.white54, size: 20),
                        tooltip: 'Clear chat',
                        onPressed: () {
                          final userName =
                              widget.homeVm.user?.name ?? 'User';
                          chatVm.clearChat(widget.homeVm, userName);
                        },
                      ),
                    // Close
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white70),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // ── Messages or welcome screen ───────────────────────────
              Expanded(
                child: !chatVm.hasMessages
                    ? _buildWelcome(chatVm)
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        itemCount: chatVm.messages.length,
                        itemBuilder: (_, i) =>
                            _chatBubble(chatVm.messages[i]),
                      ),
              ),

              // ── Thinking indicator ───────────────────────────────────
              if (chatVm.isThinking)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.secondaryGold),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text('BrightBot is thinking…',
                          style: TextStyle(
                              color: subtleColor, fontSize: 12)),
                    ],
                  ),
                ),

              // ── Input bar ───────────────────────────────────────────
              Container(
                padding:
                    const EdgeInsets.fromLTRB(14, 10, 14, 20),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.grey.shade50,
                  border: Border(
                      top: BorderSide(
                          color: isDark ? Colors.white12 : Colors.grey.shade200)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: inputBg,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: inputBorder),
                        ),
                        child: TextField(
                          controller: _inputController,
                          style: TextStyle(color: textColor, fontSize: 14),
                          cursorColor: AppColors.secondaryGold,
                          maxLines: 4,
                          minLines: 1,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (text) => _send(text, chatVm),
                          decoration: InputDecoration(
                            hintText: 'Ask about your finances…',
                            hintStyle: TextStyle(
                                color: isDark ? Colors.white38 : Colors.black38,
                                fontSize: 13),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: chatVm.isThinking
                          ? null
                          : () => _send(_inputController.text, chatVm),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: chatVm.isThinking
                              ? (isDark
                                  ? Colors.white.withValues(alpha: 0.1)
                                  : Colors.grey.shade200)
                              : AppColors.secondaryGold,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.send_rounded,
                          color: chatVm.isThinking
                              ? (isDark ? Colors.white24 : Colors.grey)
                              : AppColors.primaryTealDark,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Welcome screen with quick chips
  Widget _buildWelcome(FinancialChatViewModel chatVm) {
    final isDark = widget.isDark;
    final textColor = isDark ? Colors.white : AppColors.textDark;
    final subtleTextColor = isDark ? Colors.white70 : Colors.black54;
    final bubbleBg = isDark
        ? Colors.white.withValues(alpha: 0.09)
        : AppColors.primaryTeal.withValues(alpha: 0.08);
    final chipBg = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : AppColors.primaryTeal.withValues(alpha: 0.06);

    const chips = [
      "This month's summary",
      'Top spending category',
      'Can I afford RM200?',
      'Transactions over RM50',
      'How much did I save?',
      'Am I over budget?',
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bot greeting bubble
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                    color: AppColors.secondaryGold, shape: BoxShape.circle),
                child: const Icon(Icons.auto_awesome,
                    color: AppColors.primaryTealDark, size: 18),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: bubbleBg,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(18),
                      bottomLeft: Radius.circular(18),
                      bottomRight: Radius.circular(18),
                    ),
                  ),
                  child: Text(
                    'Hi there! 👋 I\'m BrightBot — your personal finance assistant.\n\nI have full access to your transactions, budgets, and income. Ask me anything!',
                    style: TextStyle(
                        color: textColor, fontSize: 13, height: 1.55),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Quick chips label
          Row(
            children: [
              Container(
                width: 3,
                height: 14,
                decoration: BoxDecoration(
                  color: AppColors.secondaryGold,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Text('Quick questions',
                  style: TextStyle(
                      color: subtleTextColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),

          Wrap(
            spacing: 8,
            runSpacing: 10,
            children: chips
                .map(
                  (chip) => GestureDetector(
                    onTap: chatVm.isThinking
                        ? null
                        : () => _send(chip, chatVm),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: chipBg,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                            color: AppColors.secondaryGold
                                .withValues(alpha: 0.45)),
                      ),
                      child: Text(chip,
                          style: TextStyle(
                              color: textColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w500)),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  // Individual chat bubble
  Widget _chatBubble(ChatMessage msg) {
    final isDark = widget.isDark;
    final isUser = msg.isUser;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              width: 30,
              height: 30,
              margin: const EdgeInsets.only(right: 8, bottom: 2),
              decoration: const BoxDecoration(
                  color: AppColors.secondaryGold, shape: BoxShape.circle),
              child: const Icon(Icons.auto_awesome,
                  color: AppColors.primaryTealDark, size: 15),
            ),
          ],
          Flexible(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? AppColors.secondaryGold.withValues(alpha: 0.92)
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.11)
                        : AppColors.primaryTeal.withValues(alpha: 0.10)),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 18),
                ),
              ),
              child: Text(
                msg.text,
                style: TextStyle(
                  color: isUser
                      ? AppColors.primaryTealDark
                      : (isDark ? Colors.white : AppColors.textDark),
                  fontSize: 13,
                  height: 1.55,
                ),
              ),
            ),
          ),
          if (isUser) ...[
            Container(
              width: 30,
              height: 30,
              margin: const EdgeInsets.only(left: 8, bottom: 2),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : AppColors.primaryTeal.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.person,
                  color: isDark ? Colors.white60 : AppColors.primaryTeal,
                  size: 16),
            ),
          ],
        ],
      ),
    );
  }
}
