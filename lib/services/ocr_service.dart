import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Result returned by [OcrService.scanReceipt].
class OcrResult {
  final String shopName;
  final double amount;
  final String rawText;

  /// Set after Gemini AI analysis
  final bool isIncome;
  final String? category;

  const OcrResult({
    required this.shopName,
    required this.amount,
    required this.rawText,
    this.isIncome = false,
    this.category,
  });

  OcrResult copyWith({
    String? shopName,
    double? amount,
    String? rawText,
    bool? isIncome,
    String? category,
  }) {
    return OcrResult(
      shopName: shopName ?? this.shopName,
      amount: amount ?? this.amount,
      rawText: rawText ?? this.rawText,
      isIncome: isIncome ?? this.isIncome,
      category: category ?? this.category,
    );
  }
}


/// Sends receipt images to the ocr.space API and parses the
/// shop name and total amount from the extracted text.
class OcrService {
  static const String _apiKey = 'K86358477388957';
  static const String _endpoint = 'https://api.ocr.space/parse/image';

  Future<OcrResult?> scanReceipt(File imageFile) async {
    try {
      final request =
          http.MultipartRequest('POST', Uri.parse(_endpoint));
      request.headers['apikey'] = _apiKey;

      // OCR settings — OCREngine 2 is more accurate for receipts
      request.fields['language'] = 'eng';
      request.fields['isOverlayRequired'] = 'false';
      request.fields['scale'] = 'true';
      request.fields['OCREngine'] = '2';
      request.fields['detectOrientation'] = 'true';

      request.files.add(
        await http.MultipartFile.fromPath('file', imageFile.path),
      );

      final streamed = await request
          .send()
          .timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);

      if (response.statusCode != 200) {
        debugPrint('OCR API HTTP error ${response.statusCode}: ${response.body}');
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;

      if (json['IsErroredOnProcessing'] == true) {
        debugPrint('OCR processing error: ${json['ErrorMessage']}');
        return null;
      }

      final results = json['ParsedResults'] as List?;
      if (results == null || results.isEmpty) return null;

      final text = (results.first['ParsedText'] as String?) ?? '';
      if (text.trim().isEmpty) return null;

      debugPrint('OCR raw text:\n$text');

      final shopName = _extractShopName(text) ?? 'Unknown';
      final amount = _extractTotal(text) ?? 0.0;

      return OcrResult(shopName: shopName, amount: amount, rawText: text);
    } catch (e) {
      debugPrint('OcrService.scanReceipt error: $e');
      return null;
    }
  }

  /// Returns the first line that looks like a business name
  /// (has ≥3 alphabetic characters, not purely numeric).
  String? _extractShopName(String text) {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    for (final line in lines.take(6)) {
      final alpha = line.replaceAll(RegExp(r'[^a-zA-Z\s]'), '').trim();
      if (alpha.length >= 3) {
        return line.replaceAll(RegExp(r'\s+'), ' ').trim();
      }
    }
    return null;
  }

  /// Searches for total-related keywords and extracts the last decimal
  /// number on that line. Works for English and Malay receipts.
  double? _extractTotal(String text) {
    final lines = text.split('\n').map((l) => l.trim()).toList();

    // Keywords in priority order — broader match at the end
    final keywords = RegExp(
      r'(grand\s*total|total\s*amount|total\s*due|amount\s*due|'
      r'net\s*total|total\s*bill|balance\s*due|amount\s*payable|'
      r'jumlah\s*besar|jumlah\s*keseluruhan|jumlah|bayaran|total)',
      caseSensitive: false,
    );

    double? result;
    for (final line in lines) {
      if (!keywords.hasMatch(line)) continue;

      // Prefer decimal numbers (e.g. 25.50) over integers
      final decimalMatches =
          RegExp(r'\d+\.\d{1,2}').allMatches(line);
      if (decimalMatches.isNotEmpty) {
        final parsed = double.tryParse(decimalMatches.last.group(0)!);
        if (parsed != null && parsed > 0) result = parsed;
      } else {
        final intMatches = RegExp(r'\d+').allMatches(line);
        if (intMatches.isNotEmpty) {
          final parsed = double.tryParse(intMatches.last.group(0)!);
          if (parsed != null && parsed > 0) result = parsed;
        }
      }
    }
    return result;
  }
}
