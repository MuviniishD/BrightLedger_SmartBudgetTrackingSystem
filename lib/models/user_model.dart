import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String name;
  final String email;
  final double monthlyIncome;
  final List<String> selectedCategories;
  final List<String> selectedIncomeCategories;
  final DateTime memberSince;

  UserModel({
    required this.uid,
    required this.name,
    required this.email,
    required this.monthlyIncome,
    required this.selectedCategories,
    required this.selectedIncomeCategories,
    required this.memberSince,
  });

  factory UserModel.fromMap(Map<String, dynamic> map, String uid) {
    return UserModel(
      uid: uid,
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      monthlyIncome: (map['monthlyIncome'] ?? 0).toDouble(),
      selectedCategories: List<String>.from(map['selectedCategories'] ?? []),
      selectedIncomeCategories: map['selectedIncomeCategories'] != null
          ? List<String>.from(map['selectedIncomeCategories'])
          : ['Earned', 'Investment', 'Passive'],
      memberSince: map['memberSince'] is Timestamp
          ? (map['memberSince'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'monthlyIncome': monthlyIncome,
      'selectedCategories': selectedCategories,
      'selectedIncomeCategories': selectedIncomeCategories,
      'memberSince': Timestamp.fromDate(memberSince),
    };
  }
}
