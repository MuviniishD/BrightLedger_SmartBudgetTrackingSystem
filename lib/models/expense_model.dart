import 'package:cloud_firestore/cloud_firestore.dart';

class ExpenseModel {
  final String? id;
  final String userId;
  final String reference;
  final double amount;
  final String category;
  final DateTime date;
  final bool isIncome;

  ExpenseModel({
    this.id,
    required this.userId,
    required this.reference,
    required this.amount,
    required this.category,
    required this.date,
    this.isIncome = false,
  });

  factory ExpenseModel.fromMap(Map<String, dynamic> map, String id) {
    return ExpenseModel(
      id: id,
      userId: map['userId'] ?? '',
      reference: map['reference'] ?? '',
      amount: (map['amount'] ?? 0).toDouble(),
      category: map['category'] ?? '',
      date: map['date'] is Timestamp
          ? (map['date'] as Timestamp).toDate()
          : DateTime.now(),
      isIncome: map['isIncome'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'reference': reference,
      'amount': amount,
      'category': category,
      'date': Timestamp.fromDate(date),
      'isIncome': isIncome,
    };
  }
}
