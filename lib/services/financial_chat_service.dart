import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/material.dart';
import '../models/budget_model.dart';
import '../models/expense_model.dart';

/// [ChatMessage] represents a single message in the chat conversation.
/// It encapsulates the text, the sender's identity, and the timestamp.
class ChatMessage {
  /// The actual text content of the message.
  final String text;
  /// True if the message was sent by the user, false if sent by the AI.
  final bool isUser;
  /// The time the message was created or received.
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// [FinancialChatService] provides a conversational AI financial assistant backed by Gemini.
/// It maintains a full chat session history so follow-up questions work naturally,
/// and it context-loads the user's financial data.
class FinancialChatService {
  // The Gemini AI model instance
  GenerativeModel? _model;
  // The active chat session which holds conversational history
  ChatSession? _chatSession;

  /// Builds a human-readable context block from the user's financial data.
  /// This string is injected into the AI's system prompt so it "knows" the user's finances.
  String _buildFinancialContext({
    required List<ExpenseModel> records,
    required List<BudgetModel> budgets,
    required double baseMonthlyIncome,
    required double totalRecordedIncome,
    required double totalExpenses,
    required String userName,
  }) {
    final now = DateTime.now();
    // Calculate total income by combining base income and individually recorded incomes
    final displayIncome = baseMonthlyIncome + totalRecordedIncome;

    // Filter and sort records to only include the last 60 days
    // This provides relevant recent context without overloading the token limit
    final recentRecords = records
        .where((r) =>
            r.date.isAfter(now.subtract(const Duration(days: 60))) &&
            !r.date.isAfter(now))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date)); // Sort newest first

    // Map each transaction record to a readable string format for the AI
    final recordLines = recentRecords.map((r) {
      final type = r.isIncome ? 'INCOME' : 'EXPENSE';
      final dateStr =
          '${r.date.day}/${r.date.month}/${r.date.year}';
      return '  [$dateStr] $type | ${r.category} | "${r.reference}" | RM${r.amount.toStringAsFixed(2)}';
    }).join('\n');

    // Map budget models to readable strings
    final budgetLines = budgets.map((b) {
      return '  • ${b.category}: budget RM${b.allocatedAmount.toStringAsFixed(2)}';
    }).join('\n');

    // Construct the final comprehensive context string
    return '''
USER FINANCIAL PROFILE:
  Name: $userName
  Base Monthly Income (from profile): RM${baseMonthlyIncome.toStringAsFixed(2)}
  Additional Income Recorded This Month: RM${totalRecordedIncome.toStringAsFixed(2)}
  Total Monthly Income (combined): RM${displayIncome.toStringAsFixed(2)}
  Total Expenses This Month: RM${totalExpenses.toStringAsFixed(2)}
  Estimated Balance: RM${(displayIncome - totalExpenses).toStringAsFixed(2)}
  Currency: Malaysian Ringgit (RM)
  Today's Date: ${now.day}/${now.month}/${now.year}

BUDGET ALLOCATIONS:
$budgetLines

RECENT TRANSACTIONS (last 60 days, newest first):
$recordLines
''';
  }

  /// Initialises or resets the Gemini chat session with fresh financial context.
  /// Must be called before [sendMessage] to provide accurate financial advice.
  void initSession({
    required List<ExpenseModel> records,
    required List<BudgetModel> budgets,
    required double baseMonthlyIncome,
    required double totalRecordedIncome,
    required double totalExpenses,
    required String userName,
  }) {
    // Initialize the Gemini model with a strict system instruction
    _model = FirebaseAI.googleAI().generativeModel(
      model: 'gemini-3.5-flash',
      // The system instruction defines the AI's persona and rules
      systemInstruction: Content.system(
        '''You are BrightBot, a friendly and concise personal finance assistant embedded in the BrightLedger app.
You have access to the user's real financial data below. Use it to answer questions accurately.
Always respond in a conversational, warm tone. Keep answers short (2–5 sentences unless detail is requested).
Use Malaysian Ringgit (RM) for all currency. If asked about affordability, consider their current balance.
Never make up transactions that don't exist in the data.

${_buildFinancialContext(
          records: records,
          budgets: budgets,
          baseMonthlyIncome: baseMonthlyIncome,
          totalRecordedIncome: totalRecordedIncome,
          totalExpenses: totalExpenses,
          userName: userName,
        )}''',
      ),
    );
    // Start a new chat session to maintain conversation history
    _chatSession = _model!.startChat();
  }

  /// Sends a user message to the active chat session and awaits the AI reply.
  /// Returns the AI's response text, or null/error message on failure.
  Future<String?> sendMessage(String userMessage) async {
    // Ensure the session was properly initialized
    if (_chatSession == null) {
      debugPrint('FinancialChatService: session not initialised');
      return 'I\'m not ready yet — please try again in a moment.';
    }

    try {
      // Send the user's message and wait for generation
      final response =
          await _chatSession!.sendMessage(Content.text(userMessage));
      return response.text?.trim();
    } catch (e) {
      // Handle network or generation errors safely
      debugPrint('FinancialChatService.sendMessage error: $e');
      return 'Sorry, I couldn\'t process that. Please try again.';
    }
  }

  /// Resets the current chat session and model instance.
  /// Useful for clearing conversation history when the user logs out.
  void resetSession() {
    _chatSession = null;
    _model = null;
  }
}
