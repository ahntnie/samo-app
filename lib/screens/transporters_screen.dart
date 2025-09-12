import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'dart:io';

// Cache utility class
class CacheUtil {
  static final Map<String, String> productNameCache = {};

  static void cacheProductName(String id, String name) => productNameCache[id] = name;
  static String getProductName(String? id) => id != null ? productNameCache[id] ?? 'Không xác định' : 'Không xác định';
}

/// Hàm định dạng số với dấu phân cách hàng nghìn (ví dụ: 1000000000 → 1.000.000.000)
String formatNumber(num? amount) {
  if (amount == null) return '0';
  return NumberFormat.decimalPattern('vi_VN').format(amount);
}

/// Hàm định dạng ngày từ ISO 8601 sang dd-MM-yyyy
String formatDate(String? dateStr) {
  if (dateStr == null) return '';
  try {
    final parsedDate = DateTime.parse(dateStr);
    return DateFormat('dd-MM-yyyy').format(parsedDate);
  } catch (e) {
    return dateStr;
  }
}

class TransportersScreen extends StatefulWidget {
  final List<String> permissions;
  final SupabaseClient tenantClient;

  const TransportersScreen({
    super.key,
    required this.permissions,
    required this.tenantClient,
  });

  @override
  _TransportersScreenState createState() => _TransportersScreenState();
}

class _TransportersScreenState extends State<TransportersScreen> {
  String searchText = '';
  String sortOption = 'name-asc';
  List<Map<String, dynamic>> transporters = [];
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _initProductCache().then((_) => _fetchTransporters());
  }

  Future<void> _initProductCache() async {
    try {
      final productResponse = await widget.tenantClient.from('products_name').select('id, products');
      for (var product in productResponse) {
        CacheUtil.cacheProductName(product['id'].toString(), product['products'] as String);
      }
    } catch (e) {
      print('Error initializing product cache: $e');
    }
  }

  Future<void> _fetchTransporters() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final response = await widget.tenantClient.from('transporters').select();
      setState(() {
        transporters = (response as List<dynamic>).cast<Map<String, dynamic>>();
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = 'Không thể tải dữ liệu từ Supabase: $e';
        isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get filteredTransporters {
    var filtered = transporters.where((transporter) {
      final name = transporter['name']?.toString().toLowerCase() ?? '';
      final phone = transporter['phone']?.toString().toLowerCase() ?? '';
      return name.contains(searchText.toLowerCase()) || phone.contains(searchText.toLowerCase());
    }).toList();

    if (sortOption == 'name-asc') {
      filtered.sort((a, b) => (a['name']?.toString() ?? '').compareTo(b['name']?.toString() ?? ''));
    } else if (sortOption == 'name-desc') {
      filtered.sort((a, b) => (b['name']?.toString() ?? '').compareTo(a['name']?.toString() ?? ''));
    } else if (sortOption == 'debt-desc') {
      filtered.sort((a, b) {
        final debtA = (a['debt'] as num? ?? 0);
        final debtB = (b['debt'] as num? ?? 0);
        return debtB.compareTo(debtA);
      });
    } else if (sortOption == 'debt-asc') {
      filtered.sort((a, b) {
        final debtA = (a['debt'] as num? ?? 0);
        final debtB = (b['debt'] as num? ?? 0);
        return debtA.compareTo(debtB);
      });
    }

    return filtered;
  }

  void _showTransporterDetails(Map<String, dynamic> transporter) {
    showDialog(
      context: context,
      builder: (context) => TransporterDetailsDialog(
        transporter: transporter,
        tenantClient: widget.tenantClient,
      ),
    );
  }

  void _showEditTransporterDialog(Map<String, dynamic> transporter) {
    showDialog(
      context: context,
      builder: (context) => EditTransporterDialog(
        transporter: transporter,
        onSave: (updatedTransporter) async {
          try {
            await widget.tenantClient.from('transporters').update({
              'name': updatedTransporter['name'],
              'phone': updatedTransporter['phone'],
              'address': updatedTransporter['address'],
            }).eq('id', transporter['id']);

            setState(() {
              final index = transporters.indexWhere((t) => t['id'] == transporter['id']);
              if (index != -1) {
                transporters[index] = {...transporters[index], ...updatedTransporter};
              }
            });

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Đã cập nhật thông tin đơn vị vận chuyển')),
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
                onPressed: _fetchTransporters,
                child: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Đơn Vị Vận Chuyển', style: TextStyle(color: Colors.white, fontSize: 20)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: InputDecoration(
                      labelText: 'Tìm kiếm đơn vị vận chuyển',
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
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                      labelText: 'Sắp xếp',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    icon: Container(),
                    value: sortOption,
                    items: const [
                      DropdownMenuItem(value: 'name-asc', child: Text('Tên (A-Z)')),
                      DropdownMenuItem(value: 'name-desc', child: Text('Tên (Z-A)')),
                      DropdownMenuItem(value: 'debt-asc', child: Text('Công nợ thấp đến cao')),
                      DropdownMenuItem(value: 'debt-desc', child: Text('Công nợ cao đến thấp')),
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
                itemCount: filteredTransporters.length,
                itemBuilder: (context, index) {
                  final transporter = filteredTransporters[index];
                  final debt = transporter['debt'] as num? ?? 0;
                  final debtText = debt != 0 ? '${formatNumber(debt)} VND' : '0 VND';

                  return Card(
                    elevation: 2,
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: ListTile(
                      title: Text(transporter['name']?.toString() ?? ''),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Điện thoại: ${transporter['phone']?.toString() ?? ''}'),
                          Text('Công nợ: $debtText'),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit, color: Colors.orange),
                            onPressed: () => _showEditTransporterDialog(transporter),
                          ),
                          IconButton(
                            icon: const Icon(Icons.visibility, color: Colors.blue),
                            onPressed: () => _showTransporterDetails(transporter),
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
    );
  }
}

class EditTransporterDialog extends StatefulWidget {
  final Map<String, dynamic> transporter;
  final Function(Map<String, dynamic>) onSave;

  const EditTransporterDialog({super.key, required this.transporter, required this.onSave});

  @override
  _EditTransporterDialogState createState() => _EditTransporterDialogState();
}

class _EditTransporterDialogState extends State<EditTransporterDialog> {
  late TextEditingController nameController;
  late TextEditingController phoneController;
  late TextEditingController addressController;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.transporter['name']?.toString() ?? '');
    phoneController = TextEditingController(text: widget.transporter['phone']?.toString() ?? '');
    addressController = TextEditingController(text: widget.transporter['address']?.toString() ?? '');
  }

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sửa Thông Tin Đơn Vị Vận Chuyển'),
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
            final updatedTransporter = {
              'name': nameController.text,
              'phone': phoneController.text,
              'address': addressController.text,
            };
            widget.onSave(updatedTransporter);
            Navigator.pop(context);
          },
          child: const Text('Lưu'),
        ),
      ],
    );
  }
}

class TransporterDetailsDialog extends StatefulWidget {
  final Map<String, dynamic> transporter;
  final SupabaseClient tenantClient;

  const TransporterDetailsDialog({
    super.key,
    required this.transporter,
    required this.tenantClient,
  });

  @override
  _TransporterDetailsDialogState createState() => _TransporterDetailsDialogState();
}

class _TransporterDetailsDialogState extends State<TransporterDetailsDialog> {
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
      final transporterName = widget.transporter['name']?.toString() ?? '';
      final start = currentPage * pageSize;
      final end = start + pageSize - 1;

      final transporterOrdersQuery = widget.tenantClient
          .from('transporter_orders')
          .select('*, product_id')
          .eq('transporter', transporterName)
          .eq('iscancelled', false)
          .order('created_at', ascending: false)
          .range(start, end);

      final financialOrdersQuery = widget.tenantClient
          .from('financial_orders')
          .select()
          .eq('partner_type', 'transporters')
          .eq('partner_name', transporterName)
          .eq('iscancelled', false)
          .order('created_at', ascending: false)
          .range(start, end);

      final saleOrdersQuery = widget.tenantClient
          .from('sale_orders')
          .select('*, product_id')
          .eq('transporter', transporterName)
          .eq('iscancelled', false)
          .order('created_at', ascending: false)
          .range(start, end);

      final reimportOrdersQuery = widget.tenantClient
          .from('reimport_orders')
          .select('*, product_id')
          .eq('account', 'COD Hoàn')
          .eq('iscancelled', false)
          .order('created_at', ascending: false)
          .range(start, end);

      final results = await Future.wait([
        transporterOrdersQuery,
        financialOrdersQuery,
        saleOrdersQuery,
        reimportOrdersQuery,
      ]);

      final transporterOrders = (results[0] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((order) => {
                ...order,
                'type': order['type'] == 'chuyển kho quốc tế'
                    ? 'Phiếu Chuyển Kho Quốc Tế'
                    : order['type'] == 'chuyển kho nội địa'
                        ? 'Phiếu Chuyển Kho Nội Địa'
                        : order['type'] == 'nhập kho vận chuyển'
                            ? 'Phiếu Nhập Kho Vận Chuyển'
                            : 'Vận Chuyển',
                'product_name': CacheUtil.getProductName(order['product_id']?.toString()),
              })
          .toList();

      final financialOrders = (results[1] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((order) => {...order, 'type': 'Chi Thanh Toán Đối Tác'})
          .toList();

      final saleOrders = (results[2] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((order) => {
                ...order,
                'type': 'Phiếu Bán Hàng',
                'product_name': CacheUtil.getProductName(order['product_id']?.toString()),
              })
          .toList();

      final reimportOrders = (results[3] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((order) => {
                ...order,
                'type': 'Phiếu Nhập Lại Hàng',
                'product_name': CacheUtil.getProductName(order['product_id']?.toString()),
              })
          .toList();

      final newTransactions = [...transporterOrders, ...financialOrders, ...saleOrders, ...reimportOrders];

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
        final transporterName = widget.transporter['name']?.toString() ?? '';

        final transporterOrdersFuture = widget.tenantClient
            .from('transporter_orders')
            .select('*, product_id')
            .eq('transporter', transporterName)
            .eq('iscancelled', false)
            .order('created_at', ascending: false);

        final financialOrdersFuture = widget.tenantClient
            .from('financial_orders')
            .select()
            .eq('partner_type', 'transporters')
            .eq('partner_name', transporterName)
            .eq('iscancelled', false)
            .order('created_at', ascending: false);

        final saleOrdersFuture = widget.tenantClient
            .from('sale_orders')
            .select('*, product_id')
            .eq('transporter', transporterName)
            .eq('iscancelled', false)
            .order('created_at', ascending: false);

        final reimportOrdersFuture = widget.tenantClient
            .from('reimport_orders')
            .select('*, product_id')
            .eq('account', 'COD Hoàn')
            .eq('iscancelled', false)
            .order('created_at', ascending: false);

        final results = await Future.wait([
          transporterOrdersFuture,
          financialOrdersFuture,
          saleOrdersFuture,
          reimportOrdersFuture,
        ]);

        final transporterOrders = (results[0] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map((order) => {
                  ...order,
                  'type': order['type'] == 'chuyển kho quốc tế'
                      ? 'Phiếu Chuyển Kho Quốc Tế'
                      : order['type'] == 'chuyển kho nội địa'
                          ? 'Phiếu Chuyển Kho Nội Địa'
                          : order['type'] == 'nhập kho vận chuyển'
                              ? 'Phiếu Nhập Kho Vận Chuyển'
                              : 'Vận Chuyển',
                  'product_name': CacheUtil.getProductName(order['product_id']?.toString()),
                })
            .toList();

        final financialOrders = (results[1] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map((order) => {...order, 'type': 'Chi Thanh Toán Đối Tác'})
            .toList();

        final saleOrders = (results[2] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map((order) => {
                  ...order,
                  'type': 'Phiếu Bán Hàng',
                  'product_name': CacheUtil.getProductName(order['product_id']?.toString()),
                })
            .toList();

        final reimportOrders = (results[3] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map((order) => {
                  ...order,
                  'type': 'Phiếu Nhập Lại Hàng',
                  'product_name': CacheUtil.getProductName(order['product_id']?.toString()),
                })
            .toList();

        exportTransactions = [...transporterOrders, ...financialOrders, ...saleOrders, ...reimportOrders];
        exportTransactions.sort((a, b) {
          final dateA = DateTime.tryParse(a['created_at']?.toString() ?? '1900-01-01') ?? DateTime(1900);
          final dateB = DateTime.tryParse(b['created_at']?.toString() ?? '1900-01-01') ?? DateTime(1900);
          return dateB.compareTo(dateA);
        });
      }

      var excel = Excel.createExcel();
      excel.delete('Sheet1');

      Sheet sheet = excel['GiaoDichDonViVanChuyen'];

      sheet.cell(CellIndex.indexByString("A1")).value = TextCellValue('Loại giao dịch');
      sheet.cell(CellIndex.indexByString("B1")).value = TextCellValue('Ngày');
      sheet.cell(CellIndex.indexByString("C1")).value = TextCellValue('Số tiền');
      sheet.cell(CellIndex.indexByString("D1")).value = TextCellValue('Đơn vị tiền');
      sheet.cell(CellIndex.indexByString("E1")).value = TextCellValue('Chi tiết');

      for (int i = 0; i < exportTransactions.length; i++) {
        final transaction = exportTransactions[i];
        final type = transaction['type'] as String;
        final createdAt = formatDate(transaction['created_at']?.toString());
        final amount = transaction['transport_fee'] ?? transaction['amount'] ?? transaction['price'] ?? 0;
        final currency = transaction['currency']?.toString() ?? 'VND';
        final formattedAmount = formatNumber(amount);
        final productName = transaction['product_name'] ?? 'Không xác định';
        final details = type == 'Phiếu Chuyển Kho Quốc Tế' ||
                type == 'Phiếu Chuyển Kho Nội Địa' ||
                type == 'Phiếu Nhập Kho Vận Chuyển'
            ? 'Sản phẩm: $productName, IMEI: ${transaction['imei']}'
            : type == 'Phiếu Bán Hàng'
                ? 'Sản phẩm: $productName, IMEI: ${transaction['imei']}'
                : type == 'Phiếu Nhập Lại Hàng'
                    ? 'Sản phẩm: $productName, IMEI: ${transaction['imei']}, Số lượng: ${transaction['quantity']}'
                    : type == 'Chi Thanh Toán Đối Tác'
                        ? 'Tài khoản: ${transaction['account']}, Ghi chú: ${transaction['note'] ?? ''}'
                        : '';

        sheet.cell(CellIndex.indexByString("A${i + 2}")).value = TextCellValue(type);
        sheet.cell(CellIndex.indexByString("B${i + 2}")).value = TextCellValue(createdAt);
        sheet.cell(CellIndex.indexByString("C${i + 2}")).value = TextCellValue(formattedAmount);
        sheet.cell(CellIndex.indexByString("D${i + 2}")).value = TextCellValue(currency);
        sheet.cell(CellIndex.indexByString("E${i + 2}")).value = TextCellValue(details);
      }

      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
        print('Sheet1 đã được xóa trước khi xuất file.');
      } else {
        print('Không tìm thấy Sheet1 sau khi tạo các sheet.');
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
      final transporterName = widget.transporter['name']?.toString() ?? 'Unknown';
      final fileName = 'Báo Cáo Giao Dịch Đơn Vị Vận Chuyển $transporterName ${now.day}_${now.month}_${now.year} ${now.hour}_${now.minute}_${now.second}.xlsx';
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
    final transporter = widget.transporter;
    final debt = transporter['debt'] as num? ?? 0;
    final debtText = debt != 0 ? '${formatNumber(debt)} VND' : '0 VND';

    return AlertDialog(
      title: const Text('Chi tiết đơn vị vận chuyển'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Tên: ${transporter['name']?.toString() ?? ''}'),
            const SizedBox(height: 8),
            Text('Số điện thoại: ${transporter['phone']?.toString() ?? ''}'),
            const SizedBox(height: 8),
            Text('Địa chỉ: ${transporter['address']?.toString() ?? ''}'),
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
              SizedBox(
                height: 300,
                child: ListView.builder(
                  controller: _scrollController,
                  itemCount: filteredTransactions.length + (isLoadingMore ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == filteredTransactions.length && isLoadingMore) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final transaction = filteredTransactions[index];
                    final type = transaction['type'] as String;
                    final createdAt = formatDate(transaction['created_at']?.toString());
                    final amount = transaction['transport_fee'] ?? transaction['amount'] ?? transaction['price'] ?? 0;
                    final currency = transaction['currency']?.toString() ?? 'VND';
                    final formattedAmount = formatNumber(amount);
                    final productName = transaction['product_name'] ?? 'Không xác định';
                    final details = type == 'Phiếu Chuyển Kho Quốc Tế' ||
                            type == 'Phiếu Chuyển Kho Nội Địa' ||
                            type == 'Phiếu Nhập Kho Vận Chuyển'
                        ? 'Sản phẩm: $productName, IMEI: ${transaction['imei']}'
                        : type == 'Phiếu Bán Hàng'
                            ? 'Sản phẩm: $productName, IMEI: ${transaction['imei']}'
                            : type == 'Phiếu Nhập Lại Hàng'
                                ? 'Sản phẩm: $productName, IMEI: ${transaction['imei']}, Số lượng: ${transaction['quantity']}'
                                : type == 'Chi Thanh Toán Đối Tác'
                                    ? 'Tài khoản: ${transaction['account']}, Ghi chú: ${transaction['note'] ?? ''}'
                                    : '';

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        title: Text('$type - $createdAt'),
                        subtitle: Text('$details\nSố tiền: $formattedAmount $currency'),
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