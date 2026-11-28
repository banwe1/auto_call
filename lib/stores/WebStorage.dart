import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../viewmodels/Customer.dart';

class StorageService {
  SharedPreferences? _prefs;

  Future<SharedPreferences> get prefs async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  /// 显式初始化（Web / 桌面兜底实现）
  Future<void> init() async {
    await prefs;
  }

  // Customers
  Future<List<Customer>> getAllCustomers() async {
    final p = await prefs;
    final String? customersJson = p.getString('customers');
    if (customersJson == null) return [];
    final List<dynamic> list = json.decode(customersJson);
    return list.map((e) => _fromMap(e)).toList();
  }

  Future<void> saveCustomer(Customer customer) async {
    final p = await prefs;
    final List<Customer> customers = await getAllCustomers();
    
    // Simple mock of Isar's autoIncrement
    if (customer.id == 0) {
      customer.id = customers.isEmpty ? 1 : customers.map((e) => e.id).reduce((a, b) => a > b ? a : b) + 1;
    }

    final index = customers.indexWhere((e) => e.id == customer.id);
    if (index != -1) {
      customers[index] = customer;
    } else {
      customers.add(customer);
    }
    
    await p.setString('customers', json.encode(customers.map((e) => _toMap(e)).toList()));
  }

  /// 批量保存（导入场景）
  Future<void> saveCustomers(List<Customer> customers) async {
    for (final Customer customer in customers) {
      await saveCustomer(customer);
    }
  }

  /// 批量更新（拨号结果、情况标记回写等场景，按 id 覆盖）
  Future<void> updateCustomers(List<Customer> customers) async {
    if (customers.isEmpty) return;
    for (final Customer customer in customers) {
      await saveCustomer(customer);
    }
  }

  /// 按批次查询号码
  Future<List<Customer>> getCustomersByBatch(String batchId) async {
    final List<Customer> all = await getAllCustomers();
    return all
        .where((Customer e) => (e.note ?? '').contains(batchId))
        .toList();
  }

  /// 删除某批次的全部号码
  Future<void> deleteCustomersByBatch(String batchId) async {
    final List<Customer> all = await getAllCustomers();
    all.removeWhere((Customer e) => (e.note ?? '').contains(batchId));
    final SharedPreferences p = await prefs;
    await p.setString(
      'customers',
      json.encode(all.map((Customer e) => _toMap(e)).toList()),
    );
  }

  Future<void> deleteCustomer(int id) async {
    final p = await prefs;
    final List<Customer> customers = await getAllCustomers();
    customers.removeWhere((e) => e.id == id);
    await p.setString('customers', json.encode(customers.map((e) => _toMap(e)).toList()));
  }

  Future<List<Customer>> searchCustomers(String query) async {
    final List<Customer> customers = await getAllCustomers();
    final lowerQuery = query.toLowerCase();
    return customers.where((e) => 
      e.name.toLowerCase().contains(lowerQuery) || 
      e.phone.contains(query)
    ).toList();
  }

  // Helpers for Web (since we can't use Isar's generated code on Web due to the ID error)
  Customer _fromMap(Map<String, dynamic> map) {
    return Customer()
      ..id = map['id']
      ..name = map['name']
      ..phone = map['phone']
      ..tag = map['tag']
      ..createdAt = DateTime.parse(map['createdAt'])
      ..rating = map['rating']
      ..note = map['note'];
  }

  Map<String, dynamic> _toMap(Customer c) {
    return {
      'id': c.id,
      'name': c.name,
      'phone': c.phone,
      'tag': c.tag,
      'createdAt': c.createdAt.toIso8601String(),
      'rating': c.rating,
      'note': c.note,
    };
  }
}
