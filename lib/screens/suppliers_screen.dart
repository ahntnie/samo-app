import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'dart:io';
import 'dart:developer' as developer;
import 'package:intl/intl.dart';

// Cache utility class
class CacheUtil {
  static final Map<String, String> productNameCache = {};
  static final Map<String, String> warehouseNameCache = {};

  static void cacheProductName(String id, String name) => productNameCache[id] = name;
  static void cacheWarehouseName(String id, String name) => warehouseNameCache[id] = name;
  static String getProductName(String? id) => id != null ? productNameCache[id] ?? 'Không xác định' : 'Không xác định';
  static String getWarehouseName(String? id) => id != null ? warehouseNameCache[id] ?? 'Không xác định' : 'Không xác định';
}

// Hàm định dạng số với dấu phân cách hàng nghìn
String formatNumber(num? amount) {
  if (amount == null) return '0';
  return NumberFormat.decimalPattern('vi_VN').format(amount);
}

// Hàm định dạng ngày từ ISO 8601 sang dd-MM-yyyy
String formatDate(String? dateStr) {
  if (dateStr == null) return '';
  try {
    final parsedDate = DateTime.parse(dateStr);
    return DateFormat('dd-MM-yyyy').format(parsedDate);
  } catch (e) {
    return dateStr;
  }
}

class SuppliersScreen extends StatefulWidget {
  final List<String> permissions;
  final SupabaseClient tenantClient;

  const SuppliersScreen({
    super.key,
    required this.permissions,
    required this.tenantClient,
  });

  @override
  _SuppliersScreenState createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  String searchText = '';
  String sortOption = 'name-asc';
  List<Map<String, dynamic>> suppliers = [];
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchSuppliers();
  }

  Future<void> _fetchSuppliers() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      // Fetch product name cache
      final productResponse = await widget.tenantClient.from('products_name').select('id, products');
      developer.log('Loaded ${productResponse.length} products into CacheUtil');
      for (var product in productResponse) {
        CacheUtil.cacheProductName(product['id'].toString(), product['products'] as String);
      }

      // Fetch warehouse name cache
      final warehouseResponse = await widget.tenantClient.from('warehouses').select('id, name');
      developer.log('Loaded ${warehouseResponse.length} warehouses into CacheUtil');
      for (var warehouse in warehouseResponse) {
        CacheUtil.cacheWarehouseName(warehouse['id'].toString(), warehouse['name'] as String);
      }

      final response = await widget.tenantClient.from('suppliers').select();
      setState(() {
        suppliers = (response as List<dynamic>).cast<Map<String, dynamic>>();
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Không thể tải dữ liệu từ Supabase: $e';
        isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get filteredSuppliers {
    var filtered = suppliers.where((supplier) {
      final name = supplier['name']?.toString().toLowerCase() ?? '';
      final phone = supplier['phone']?.toString().toLowerCase() ?? '';
      return name.contains(searchText.toLowerCase()) || phone.contains(searchText.toLowerCase());
    }).toList();

    if (sortOption == 'name-asc') {
      filtered.sort((a, b) => (a['name']?.toString() ?? '').compareTo(b['name']?.toString() ?? ''));
    } else if (sortOption == 'name-desc') {
      filtered.sort((a, b) => (b['name']?.toString() ?? '').compareTo(a['name']?.toString() ?? ''));
    } else if (sortOption == 'debt-desc') {
      filtered.sort((a, b) {
        final debtA = (a['debt_vnd'] as num? ?? 0) + (a['debt_cny'] as num? ?? 0) + (a['debt_usd'] as num? ?? 0);
        final debtB = (b['debt_vnd'] as num? ?? 0) + (b['debt_cny'] as num? ?? 0) + (b['debt_usd'] as num? ?? 0);
        return debtB.compareTo(debtA);
      });
    } else if (sortOption == 'debt-asc') {
      filtered.sort((a, b) {
        final debtA = (a['debt_vnd'] as num? ?? 0) + (a['debt_cny'] as num? ?? 0) + (a['debt_usd'] as num? ?? 0);
        final debtB = (b['debt_vnd'] as num? ?? 0) + (b['debt_cny'] as num? ?? 0) + (b['debt_usd'] as num? ?? 0);
        return debtA.compareTo(debtB);
      });
    }

    return filtered;
  }

  void _showSupplierDetails(Map<String, dynamic> supplier) {
    showDialog(
      context: context,
      builder: (context) => SupplierDetailsDialog(
        supplier: supplier,
        tenantClient: widget.tenantClient,
      ),
    );
  }

  void _showEditSupplierDialog(Map<String, dynamic> supplier) {
    showDialog(
      context: context,
      builder: (context) => EditSupplierDialog(
        supplier: supplier,
        onSave: (updatedSupplier) async {
          try {
            await widget.tenantClient.from('suppliers').update({
              'name': updatedSupplier['name'],
              'phone': updatedSupplier['phone'],
              'address': updatedSupplier['address'],
              'social_link': updatedSupplier['social_link'],
            }).eq('id', supplier['id']);

            setState(() {
              final index = suppliers.indexWhere((s) => s['id'] == supplier['id']);
              if (index != -1) {
                suppliers[index] = {...suppliers[index], ...updatedSupplier};
              }
            });

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Đã cập nhật thông tin nhà cung cấp')),
            );
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Lỗi khi cập nhật: $e')),
            );
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (errorMessage != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(errorMessage!),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _fetchSuppliers,
                child: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity != null && details.primaryVelocity! > 0) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text('Nhà Cung Cấp', style: TextStyle(color: Colors.white)),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      decoration: InputDecoration(
                        labelText: 'Tìm kiếm nhà cung cấp',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      onChanged: (value) {
                        setState(() {
                          searchText = value;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      decoration: InputDecoration(
                        labelText: 'Sắp xếp',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                      ),
                      isDense: true,
                      value: sortOption,
                      items: const [
                        DropdownMenuItem(value: 'name-asc', child: Text('Tên (A-Z)', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'name-desc', child: Text('Tên (Z-A)', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'debt-asc', child: Text('Công nợ thấp đến cao', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'debt-desc', child: Text('Công nợ cao đến thấp', overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (value) {
                        setState(() {
                          sortOption = value ?? 'name-asc';
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: filteredSuppliers.length,
                  itemBuilder: (context, index) {
                    final supplier = filteredSuppliers[index];
                    final debtVnd = supplier['debt_vnd'] as num? ?? 0;
                    final debtCny = supplier['debt_cny'] as num? ?? 0;
                    final debtUsd = supplier['debt_usd'] as num? ?? 0;
                    final debtDetails = <String>[];
                    if (debtVnd != 0) debtDetails.add('${formatNumber(debtVnd)} VND');
                    if (debtCny != 0) debtDetails.add('${formatNumber(debtCny)} CNY');
                    if (debtUsd != 0) debtDetails.add('${formatNumber(debtUsd)} USD');
                    final debtText = debtDetails.isNotEmpty ? debtDetails.join(', ') : '0 VND';

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      child: ListTile(
                        title: Text(supplier['name']?.toString() ?? ''),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Điện thoại: ${supplier['phone']?.toString() ?? ''}'),
                            Text('Công nợ: $debtText'),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.orange),
                              onPressed: () => _showEditSupplierDialog(supplier),
                            ),
                            IconButton(
                              icon: const Icon(Icons.visibility, color: Colors.blue),
                              onPressed: () => _showSupplierDetails(supplier),
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

class EditSupplierDialog extends StatefulWidget {
  final Map<String, dynamic> supplier;
  final Function(Map<String, dynamic>) onSave;

  const EditSupplierDialog({super.key, required this.supplier, required this.onSave});

  @override
  _EditSupplierDialogState createState() => _EditSupplierDialogState();
}

class _EditSupplierDialogState extends State<EditSupplierDialog> {
  late TextEditingController nameController;
  late TextEditingController phoneController;
  late TextEditingController addressController;
  late TextEditingController socialLinkController;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.supplier['name']?.toString() ?? '');
    phoneController = TextEditingController(text: widget.supplier['phone']?.toString() ?? '');
    addressController = TextEditingController(text: widget.supplier['address']?.toString() ?? '');
    socialLinkController = TextEditingController(text: widget.supplier['social_link']?.toString() ?? '');
  }

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    addressController.dispose();
    socialLinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sửa Thông Tin Nhà Cung Cấp'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Tên'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(labelText: 'Số Điện Thoại'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: addressController,
              decoration: const InputDecoration(labelText: 'Địa Chỉ'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: socialLinkController,
              decoration: const InputDecoration(labelText: 'Link Mạng Xã Hội'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hủy'),
        ),
        ElevatedButton(
          onPressed: () {
            if (nameController.text.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Tên không được để trống!')),
              );
              return;
            }
            final updatedSupplier = {
              'name': nameController.text,
              'phone': phoneController.text,
              'address': addressController.text,
              'social_link': socialLinkController.text,
            };
            widget.onSave(updatedSupplier);
            Navigator.pop(context);
          },
          child: const Text('Lưu'),
        ),
      ],
    );
  }
}

class SupplierDetailsDialog extends StatefulWidget {
  final Map<String, dynamic> supplier;
  final SupabaseClient tenantClient;

  const SupplierDetailsDialog({
    super.key,
    required this.supplier,
    required this.tenantClient,
  });

  @override
  _SupplierDetailsDialogState createState() => _SupplierDetailsDialogState();
}

class _SupplierDetailsDialogState extends State<SupplierDetailsDialog> {
  DateTime? startDate;
  DateTime? endDate;
  List<Map<String, dynamic>> transactions = [];
  bool isLoadingTransactions = true;
  String? transactionError;
  int pageSize = 20;
  int currentPage = 0;
  bool hasMoreData = true;
  bool isLoadingMore = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _fetchTransactions();

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
              _scrollController.position.maxScrollExtent - 200 &&
          !isLoadingMore &&
          hasMoreData &&
          startDate == null &&
          endDate == null) {
        _loadMoreTransactions();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchTransactions() async {
    setState(() {
      isLoadingTransactions = true;
      transactionError = null;
      transactions = [];
      currentPage = 0;
      hasMoreData = true;
    });

    try {
      await _loadMoreTransactions();
    } catch (e) {
      setState(() {
        transactionError = 'Không thể tải giao dịch: $e';
        isLoadingTransactions = false;
      });
    }
  }

  Future<void> _loadMoreTransactions() async {
    if (!hasMoreData || isLoadingMore) return;

    setState(() {
      isLoadingMore = true;
    });

    try {
      final supplierName = widget.supplier['name']?.toString().trim() ?? '';
      developer.log('Fetching transactions for supplier: "$supplierName"');
      final start = currentPage * pageSize;
      final end = start + pageSize - 1;

      final importOrdersQuery = widget.tenantClient
          .from('import_orders')
          .select('id, product_id, imei, quantity, price, currency, created_at, account, note, warehouse_id')
          .eq('supplier', supplierName)
          .eq('iscancelled', false);

      final returnOrdersQuery = widget.tenantClient
          .from('return_orders')
          .select('id, product_id, imei, quantity, price, currency, created_at, account, note, warehouse_id')
          .eq('supplier', supplierName)
          .eq('iscancelled', false);

      final financialOrdersQuery = widget.tenantClient
          .from('financial_orders')
          .select('id, amount, currency, created_at, account, note')
          .eq('partner_type', 'suppliers')
          .eq('partner_name', supplierName)
          .eq('iscancelled', false);

      // Add date filters if dates are selected
      if (startDate != null) {
        importOrdersQuery.gte('created_at', startDate!.toIso8601String());
        returnOrdersQuery.gte('created_at', startDate!.toIso8601String());
        financialOrdersQuery.gte('created_at', startDate!.toIso8601String());
      }
      if (endDate != null) {
        final endDateTime = endDate!.add(const Duration(days: 1));
        importOrdersQuery.lt('created_at', endDateTime.toIso8601String());
        returnOrdersQuery.lt('created_at', endDateTime.toIso8601String());
        financialOrdersQuery.lt('created_at', endDateTime.toIso8601String());
      }

      developer.log('Executing queries for supplier: "$supplierName"');
      final results = await Future.wait([
        importOrdersQuery,
        returnOrdersQuery,
        financialOrdersQuery,
      ]);
      developer.log('Queries completed');

      final importOrders = (results[0] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((order) => {...order, 'type': 'Phiếu Nhập Hàng'})
          .toList();
      developer.log('Import Orders: ${importOrders.length}, First order: ${importOrders.isNotEmpty ? importOrders.first : "none"}');

      final returnOrders = (results[1] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((order) => {...order, 'type': 'Phiếu Trả Hàng'})
          .toList();
      developer.log('Return Orders: ${returnOrders.length}, First order: ${returnOrders.isNotEmpty ? returnOrders.first : "none"}');

      final financialOrders = (results[2] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((order) => {...order, 'type': 'Chi Thanh Toán Đối Tác'})
          .toList();
      developer.log('Financial Orders: ${financialOrders.length}, First order: ${financialOrders.isNotEmpty ? financialOrders.first : "none"}');

      final newTransactions = [...importOrders, ...returnOrders, ...financialOrders];
      developer.log('Total transactions: ${newTransactions.length}');

      newTransactions.sort((a, b) {
        final dateA = DateTime.tryParse(a['created_at']?.toString() ?? '1900-01-01') ?? DateTime(1900);
        final dateB = DateTime.tryParse(b['created_at']?.toString() ?? '1900-01-01') ?? DateTime(1900);
        return dateB.compareTo(dateA);
      });

      setState(() {
        transactions.addAll(newTransactions);
        if (newTransactions.length < pageSize) {
          hasMoreData = false;
        }
        currentPage++;
        isLoadingTransactions = false;
        isLoadingMore = false;
      });
    } catch (e) {
      setState(() {
        transactionError = 'Không thể tải thêm giao dịch: $e';
        isLoadingMore = false;
      });
    }
  }

  List<Map<String, dynamic>> get filteredTransactions {
    var filtered = transactions;

    if (startDate != null && endDate != null) {
      filtered = filtered.where((transaction) {
        final transactionDate = DateTime.tryParse(transaction['created_at']?.toString() ?? '1900-01-01');
        if (transactionDate == null) return false;
        return transactionDate.isAfter(startDate!.subtract(const Duration(days: 1))) &&
            transactionDate.isBefore(endDate!.add(const Duration(days: 1)));
      }).toList();
    }

    return filtered;
  }

  Future<void> _selectDate(BuildContext context, bool isStart) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          startDate = picked;
        } else {
          endDate = picked;
        }
        hasMoreData = false;
      });
    }
  }

  Future<void> _exportToExcel() async {
    if (filteredTransactions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không có giao dịch để xuất!')),
      );
      return;
    }

    try {
      List<Map<String, dynamic>> exportTransactions = filteredTransactions;
      if (hasMoreData && startDate == null && endDate == null) {
        final supplierName = widget.supplier['name']?.toString().trim() ?? '';

        final importOrdersFuture = widget.tenantClient
            .from('import_orders')
            .select('id, product_id, imei, quantity, price, currency, created_at, account, note, warehouse_id')
            .eq('supplier', supplierName)
            .eq('iscancelled', false);

        final returnOrdersFuture = widget.tenantClient
            .from('return_orders')
            .select('id, product_id, imei, quantity, price, currency, created_at, account, note, warehouse_id')
            .eq('supplier', supplierName)
            .eq('iscancelled', false);

        final financialOrdersFuture = widget.tenantClient
            .from('financial_orders')
            .select('id, amount, currency, created_at, account, note')
            .eq('partner_type', 'suppliers')
            .eq('partner_name', supplierName)
            .eq('iscancelled', false);

        final results = await Future.wait([
          importOrdersFuture,
          returnOrdersFuture,
          financialOrdersFuture,
        ]);

        final importOrders = (results[0] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map((order) => {...order, 'type': 'Phiếu Nhập Hàng'})
            .toList();
        final returnOrders = (results[1] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map((order) => {...order, 'type': 'Phiếu Trả Hàng'})
            .toList();
        final financialOrders = (results[2] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map((order) => {...order, 'type': 'Chi Thanh Toán Đối Tác'})
            .toList();

        exportTransactions = [...importOrders, ...returnOrders, ...financialOrders];
        exportTransactions.sort((a, b) {
          final dateA = DateTime.tryParse(a['created_at']?.toString() ?? '1900-01-01') ?? DateTime(1900);
          final dateB = DateTime.tryParse(b['created_at']?.toString() ?? '1900-01-01') ?? DateTime(1900);
          return dateB.compareTo(dateA);
        });
      }

      var excel = Excel.createExcel();
      excel.delete('Sheet1');

      Sheet sheet = excel['GiaoDichNhaCungCap'];

      List<TextCellValue> headers = [
        TextCellValue('Loại giao dịch'),
        TextCellValue('Ngày'),
        TextCellValue('Số tiền'),
        TextCellValue('Đơn vị tiền'),
        TextCellValue('Mã sản phẩm'),
        TextCellValue('Tên sản phẩm'),
        TextCellValue('IMEI'),
        TextCellValue('Số lượng'),
        TextCellValue('Mã kho'),
        TextCellValue('Tên kho'),
        TextCellValue('Tài khoản'),
        TextCellValue('Ghi chú'),
      ];

      sheet.appendRow(headers);

      for (int i = 0; i < exportTransactions.length; i++) {
        final transaction = exportTransactions[i];
        final type = transaction['type'] as String;
        final createdAt = formatDate(transaction['created_at']?.toString());
        num totalAmount;
        final currency = transaction['currency']?.toString() ?? 'VND';
        if (type == 'Phiếu Nhập Hàng' || type == 'Phiếu Trả Hàng') {
          final price = (transaction['price'] as num?) ?? 0;
          final quantity = (transaction['quantity'] as num?) ?? 0;
          totalAmount = price * quantity;
        } else {
          totalAmount = (transaction['amount'] as num?) ?? 0;
        }
        final formattedAmount = formatNumber(totalAmount);
        final productId = transaction['product_id']?.toString() ?? '';
        final productName = CacheUtil.getProductName(productId);
        final imei = transaction['imei']?.toString() ?? '';
        final quantity = transaction['quantity']?.toString() ?? '';
        final warehouseId = transaction['warehouse_id']?.toString() ?? '';
        final warehouseName = CacheUtil.getWarehouseName(warehouseId);
        final account = transaction['account']?.toString() ?? '';
        final note = transaction['note']?.toString() ?? '';

        List<TextCellValue> row = [
          TextCellValue(type),
          TextCellValue(createdAt),
          TextCellValue(formattedAmount),
          TextCellValue(currency),
          TextCellValue(productId),
          TextCellValue(productName),
          TextCellValue(imei),
          TextCellValue(quantity),
          TextCellValue(warehouseId),
          TextCellValue(warehouseName),
          TextCellValue(account),
          TextCellValue(note),
        ];

        sheet.appendRow(row);
      }

      Directory downloadsDir;
      if (Platform.isAndroid) {
        downloadsDir = Directory('/storage/emulated/0/Download');
        if (!await downloadsDir.exists()) {
          await downloadsDir.create(recursive: true);
        }
      } else {
        downloadsDir = await getTemporaryDirectory();
      }

      final now = DateTime.now();
      final supplierName = widget.supplier['name']?.toString() ?? 'Unknown';
      final fileName = 'Báo Cáo Giao Dịch Nhà Cung Cấp $supplierName ${now.day}_${now.month}_${now.year} ${now.hour}_${now.minute}_${now.second}.xlsx';
      final filePath = '${downloadsDir.path}/$fileName';
      final file = File(filePath);

      final excelBytes = excel.encode();
      if (excelBytes == null) {
        throw Exception('Không thể tạo file Excel');
      }
      await file.writeAsBytes(excelBytes);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã xuất file Excel: $filePath')),
      );

      final openResult = await OpenFile.open(filePath);
      if (openResult.type != ResultType.done) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Không thể mở file. File đã được lưu tại: $filePath'),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi khi xuất file Excel: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final supplier = widget.supplier;
    final debtDetails = <String>[];
    final debtVnd = supplier['debt_vnd'] as num? ?? 0;
    final debtCny = supplier['debt_cny'] as num? ?? 0;
    final debtUsd = supplier['debt_usd'] as num? ?? 0;
    if (debtVnd != 0) debtDetails.add('${formatNumber(debtVnd)} VND');
    if (debtCny != 0) debtDetails.add('${formatNumber(debtCny)} CNY');
    if (debtUsd != 0) debtDetails.add('${formatNumber(debtUsd)} USD');
    final debtText = debtDetails.isNotEmpty ? debtDetails.join(', ') : '0 VND';

    return AlertDialog(
      title: const Text('Chi tiết nhà cung cấp'),
      content: Container(
        width: MediaQuery.of(context).size.width * 0.9, // Set width to 90% of screen width
        height: MediaQuery.of(context).size.height * 0.8, // Set height to 80% of screen height
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tên: ${supplier['name']?.toString() ?? ''}'),
            const SizedBox(height: 8),
            Text('Số điện thoại: ${supplier['phone']?.toString() ?? ''}'),
            const SizedBox(height: 8),
            Text('Link mạng xã hội: ${supplier['social_link']?.toString() ?? ''}'),
            const SizedBox(height: 8),
            Text('Địa chỉ: ${supplier['address']?.toString() ?? ''}'),
            const SizedBox(height: 8),
            Text('Công nợ: $debtText'),
            const SizedBox(height: 16),
            const Text('Lịch sử giao dịch', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _selectDate(context, true),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Từ ngày',
                        border: OutlineInputBorder(),
                      ),
                      child: Text(startDate != null ? formatDate(startDate!.toIso8601String()) : 'Chọn ngày'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () => _selectDate(context, false),
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Đến ngày',
                        border: OutlineInputBorder(),
                      ),
                      child: Text(endDate != null ? formatDate(endDate!.toIso8601String()) : 'Chọn ngày'),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (isLoadingTransactions)
              const Center(child: CircularProgressIndicator())
            else if (transactionError != null)
              Text(transactionError!)
            else if (filteredTransactions.isEmpty)
              const Text('Không có giao dịch trong khoảng thời gian này.')
            else
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  shrinkWrap: true,
                  itemCount: filteredTransactions.length + (isLoadingMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == filteredTransactions.length && isLoadingMore) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final transaction = filteredTransactions[index];
                    final type = transaction['type'] as String;
                    final createdAt = formatDate(transaction['created_at']?.toString());
                    num totalAmount;
                    final currency = transaction['currency']?.toString() ?? 'VND';
                    if (type == 'Phiếu Nhập Hàng' || type == 'Phiếu Trả Hàng') {
                      final price = (transaction['price'] as num?) ?? 0;
                      final quantity = (transaction['quantity'] as num?) ?? 0;
                      totalAmount = price * quantity;
                    } else {
                      totalAmount = (transaction['amount'] as num?) ?? 0;
                    }
                    final formattedAmount = formatNumber(totalAmount);
                    final productId = transaction['product_id']?.toString() ?? '';
                    final productName = CacheUtil.getProductName(productId);
                    final imei = transaction['imei']?.toString() ?? '';
                    final quantity = transaction['quantity']?.toString() ?? '';
                    final warehouseId = transaction['warehouse_id']?.toString() ?? '';
                    final warehouseName = CacheUtil.getWarehouseName(warehouseId);
                    final account = transaction['account']?.toString() ?? '';
                    final note = transaction['note']?.toString() ?? '';

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        title: Text('$type - $createdAt'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (type != 'Chi Thanh Toán Đối Tác') ...[
                              Text('Sản phẩm: $productName'),
                              if (imei.isNotEmpty) Text('IMEI: $imei'),
                              if (quantity.isNotEmpty) Text('Số lượng: $quantity'),
                              if (warehouseName != 'Không xác định') Text('Kho: $warehouseName'),
                            ],
                            Text('Số tiền: $formattedAmount $currency'),
                            if (account.isNotEmpty) Text('Tài khoản: $account'),
                            if (note.isNotEmpty) Text('Ghi chú: $note'),
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
      actions: [
        TextButton(
          onPressed: _exportToExcel,
          child: const Text('Xuất Excel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Đóng'),
        ),
      ],
    );
  }
}