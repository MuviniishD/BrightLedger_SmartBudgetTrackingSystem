class BudgetModel {
  final String? id;
  final String userId;
  final String category;
  final double allocatedAmount;

  BudgetModel({
    this.id,
    required this.userId,
    required this.category,
    required this.allocatedAmount,
  });

  factory BudgetModel.fromMap(Map<String, dynamic> map, String id) {
    return BudgetModel(
      id: id,
      userId: map['userId'] ?? '',
      category: map['category'] ?? '',
      allocatedAmount: (map['allocatedAmount'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'category': category,
      'allocatedAmount': allocatedAmount,
    };
  }
}
