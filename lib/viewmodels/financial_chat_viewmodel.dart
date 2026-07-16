import 'package:flutter/material.dart';
import '../services/financial_chat_service.dart';
import '../viewmodels/home_viewmodel.dart';

// Export ChatMessage so views using this ViewModel don't need a separate import
export '../services/financial_chat_service.dart' show ChatMessage;

/// [FinancialChatViewModel] manages the UI state for the AI Assistant chat screen.
/// It holds the conversation history and coordinates with [FinancialChatService] to
/// send and receive messages from the Gemini AI.
class FinancialChatViewModel extends ChangeNotifier {
  final FinancialChatService _chatService = FinancialChatService();

  // --- State Variables ---

  /// The complete history of messages in the current session.
  final List<ChatMessage> messages = [];
  
  /// Indicates if the AI is currently processing a response (used to show a typing indicator).
  bool isThinking = false;
  
  /// Tracks whether the Gemini session has been loaded with the user's latest context.
  bool _sessionInitialised = false;

  /// Initialises (or re-initialises) the Gemini chat session with up-to-date
  /// financial data from [HomeViewModel]. Call this every time the home data
  /// is refreshed so the AI always has current numbers.
  void initFromHomeViewModel(HomeViewModel homeVm, String userName) {
    _chatService.initSession(
      records: homeVm.monthRecords,
      budgets: homeVm.budgets,
      baseMonthlyIncome: homeVm.user?.monthlyIncome ?? 0,
      totalRecordedIncome: homeVm.totalIncome,
      totalExpenses: homeVm.totalExpenses,
      userName: userName,
    );
    _sessionInitialised = true;
  }

  /// Helper to determine if the chat screen should show the welcome placeholder or the list of messages.
  bool get hasMessages => messages.isNotEmpty;
  
  /// Helper to check if it's safe to send a message.
  bool get sessionReady => _sessionInitialised;

  /// Sends a user message to the AI and appends both the user's bubble and the AI's reply bubble.
  Future<void> sendMessage(String text, HomeViewModel homeVm, String userName) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    // Ensure session is initialised with latest data before sending
    if (!_sessionInitialised) {
      initFromHomeViewModel(homeVm, userName);
    }

    // Add user message bubble to the UI immediately for responsiveness
    messages.add(ChatMessage(text: trimmed, isUser: true));
    isThinking = true;
    notifyListeners();

    // Await the AI reply from the service layer
    final reply = await _chatService.sendMessage(trimmed);
    
    // AI has responded, stop the typing indicator
    isThinking = false;

    if (reply != null && reply.isNotEmpty) {
      // Append the successful AI response
      messages.add(ChatMessage(text: reply, isUser: false));
    } else {
      // Append a fallback error message if the API fails
      messages.add(ChatMessage(
        text: 'Sorry, I couldn\'t get a response. Please try again.',
        isUser: false,
      ));
    }

    notifyListeners();
  }

  /// Clears the conversation history and hard-resets the AI session.
  /// Used when the user wants to start a fresh chat context.
  void clearChat(HomeViewModel homeVm, String userName) {
    messages.clear();
    _chatService.resetSession();
    _sessionInitialised = false;
    
    // Immediately re-initialize so it's ready for the next message
    initFromHomeViewModel(homeVm, userName);
    notifyListeners();
  }
}
