import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../notification_service.dart';

// Cache utility class
class CacheUtil {
  static final Map<String, String> productNameCache = {};
  static final Map<String, String> warehouseNameCache = {};

  static void cacheProductName(String id, String name) => productNameCache[id] = name;
  static void cacheWarehouseName(String id, String name) => warehouseNameCache[id] = name;
  static String getProductName(String? id) => id != null ? productNameCache[id] ?? 'Không xác định' : 'Không xác định';
  static String getWarehouseName(String? id) => id != null ? warehouseNameCache[id] ?? 'Không xác định' : 'Không xác định';
}

// Constants for IMEI handling
const int maxImeiQuantity = 100000;
const int warnImeiQuantity = 10000;
const int batchSize = 1000;
const int displayImeiLimit = 100;
const int maxRetries = 3;
const Duration retryDelay = Duration(seconds: 1);

/// Retries a function with exponential backoff
Future<T> retry<T>(Future<T> Function() fn, {String? operation}) async {
  for (int attempt = 0; attempt < maxRetries; attempt++) {
    try {
      return await fn();
    } catch (e) {
      if (attempt == maxRetries - 1) {
        throw Exception('${operation ?? 'Operation'} failed after $maxRetries attempts: $e');
      }
      await Future.delayed(retryDelay * math.pow(2, attempt));
    }
  }
  throw Exception('Retry failed');
}

class ThousandsFormatterLocal extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    String newText = newValue.text.replaceAll('.', '').replaceAll(',', '');
    if (newText.isEmpty) return newValue;
    
    final doubleValue = double.tryParse(newText);
    if (doubleValue == null) return oldValue;
    
    final formatted = NumberFormat('#,###', 'vi_VN').format(doubleValue).replaceAll(',', '.');
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

String formatNumberLocal(num value) {
  return NumberFormat('#,###', 'vi_VN').format(value).replaceAll(',', '.');
}

class ImportForm extends StatefulWidget {
  final SupabaseClient tenantClient;

  const ImportForm({super.key, required this.tenantClient});

  @override
  State<ImportForm> createState() => _ImportFormState();
}

class _ImportFormState extends State<ImportForm> {
  int? categoryId;
  String? categoryName;
  String? supplier;
  String? productId;
  String? productName;
  String? imei = '';
  int quantity = 1;
  String? imeiPrefix;
  String? price;
  String? currency;
  String? account;
  String? note;
  String? warehouseId;
  String? warehouseName;
  bool isAccessory = false;
  String? imeiError;
  bool isProcessing = false;
  final Set<String> confirmedImeis = {};

  List<Map<String, dynamic>> categories = [];
  List<String> suppliers = [];
  List<Map<String, dynamic>> products = [];
  List<String> currencies = [];
  List<Map<String, dynamic>> accounts = [];
  List<String> accountNames = [];
  List<Map<String, dynamic>> warehouses = [];
  bool isLoading = true;
  String? errorMessage;

  final TextEditingController imeiController = TextEditingController();
  final TextEditingController priceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
    imeiController.text = imei ?? '';
    priceController.text = price ?? '';
    confirmedImeis.clear();
  }

  @override
  void dispose() {
    imeiController.dispose();
    priceController.dispose();
    super.dispose();
  }

  Future<void> _fetchInitialData() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final supabase = widget.tenantClient;

      final categoryResponse = await retry(
        () => supabase.from('categories').select('id, name'),
        operation: 'Fetch categories',
      );
      final categoryList = categoryResponse
          .map((e) => {'id': e['id'] as int, 'name': e['name'] as String})
          .toList()
        ..sort((a, b) => (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase()));

      final supplierResponse = await retry(
        () => supabase.from('suppliers').select('name'),
        operation: 'Fetch suppliers',
      );
      final supplierList = supplierResponse
          .map((e) => e['name'] as String?)
          .whereType<String>()
          .toList()
        ..sort();

      final productResponse = await retry(
        () => supabase.from('products_name').select('id, products'),
        operation: 'Fetch products',
      );
      final productList = productResponse
          .map((e) {
            final id = e['id']?.toString();
            final products = e['products'] as String?;
            if (id != null && products != null) {
              CacheUtil.cacheProductName(id, products);
              return {'id': id, 'name': products};
            }
            return null;
          })
          .whereType<Map<String, dynamic>>()
          .toList()
        ..sort((a, b) => (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase()));

      final warehouseResponse = await retry(
        () => supabase.from('warehouses').select('id, name, type'),
        operation: 'Fetch warehouses',
      );
      final warehouseList = warehouseResponse
          .map((e) {
            final id = e['id']?.toString();
            final name = e['name'] as String?;
            final type = e['type'] as String?;
            if (id != null && name != null && type != null) {
              CacheUtil.cacheWarehouseName(id, name);
              return {'id': id, 'name': name, 'type': type};
            }
            return null;
          })
          .whereType<Map<String, dynamic>>()
          .toList()
        ..sort((a, b) => (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase()));

      final currencyResponse = await retry(
        () => supabase.from('financial_accounts').select('currency').neq('currency', ''),
        operation: 'Fetch currencies',
      );
      final uniqueCurrencies = currencyResponse
          .map((e) => e['currency'] as String?)
          .whereType<String>()
          .toSet()
          .toList();

      final accountResponse = await retry(
        () => supabase.from('financial_accounts').select('id, name, currency, balance'),
        operation: 'Fetch accounts',
      );
      final accountList = accountResponse
          .map((e) => {
                'id': e['id'].toString(),
                'name': e['name'] as String?,
                'currency': e['currency'] as String?,
                'balance': e['balance'] as num?,
              })
          .where((e) => e['name'] != null && e['currency'] != null)
          .toList();

      if (mounted) {
        setState(() {
          categories = categoryList;
          suppliers = supplierList;
          products = productList;
          warehouses = warehouseList;
          currencies = uniqueCurrencies;
          accounts = accountList;
          currency = null;
          accountNames = [];
          _updateAccountNames(null);
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = 'Không thể tải dữ liệu từ Supabase: $e';
          isLoading = false;
        });
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Thông báo'),
            content: Text('Lỗi khi tải dữ liệu: $e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Đóng'),
              ),
            ],
          ),
        );
      }
    }
  }

  void _updateAccountNames(String? selectedCurrency) {
    if (selectedCurrency == null) {
      setState(() {
        accountNames = [];
        account = null;
      });
      return;
    }

    final filteredAccounts = accounts
        .where((acc) => acc['currency'] == selectedCurrency)
        .map((acc) => acc['name'] as String)
        .toList();
    filteredAccounts.add('Công nợ');

    setState(() {
      accountNames = filteredAccounts;
      account = null;
    });
  }

  Future<num> _getExchangeRate(String currency) async {
    try {
      final supabase = widget.tenantClient;
      final response = await retry(
        () => supabase
            .from('financial_orders')
            .select('rate_vnd_cny, rate_vnd_usd')
            .eq('type', 'exchange')
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle(),
        operation: 'Fetch exchange rate',
      );

      if (response == null) return 1;

      if (currency == 'CNY' && response['rate_vnd_cny'] != null) {
        final rate = response['rate_vnd_cny'] as num;
        return rate != 0 ? rate : 1;
      } else if (currency == 'USD' && response['rate_vnd_usd'] != null) {
        final rate = response['rate_vnd_usd'] as num;
        return rate != 0 ? rate : 1;
      }
      return 1;
    } catch (e) {
      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Thông báo'),
            content: Text('Lỗi khi lấy tỷ giá: $e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Đóng'),
              ),
            ],
          ),
        );
      }
      return 1;
    }
  }

  String? _checkDuplicateImeis(String input) {
    final lines = input.split('\n').where((e) => e.trim().isNotEmpty).toList();
    final seen = <String>{};
    for (var line in lines) {
      if (seen.contains(line)) {
        return 'Line "$line" đã được nhập!';
      }
      seen.add(line);
    }
    return null;
  }

  Future<String?> _checkProductStatus(String input) async {
    final lines = input.split('\n').where((e) => e.trim().isNotEmpty).toList();
    if (lines.isEmpty) return null;
    final supabase = widget.tenantClient;

    try {
      for (int i = 0; i < lines.length; i += batchSize) {
        final batchImeis = lines.sublist(i, math.min(i + batchSize, lines.length));
        final imeisToCheck = batchImeis.where((imei) => !confirmedImeis.contains(imei)).toList();
        if (imeisToCheck.isEmpty) continue;

        final response = await retry(
          () => supabase
              .from('products')
              .select('imei, name, warehouse_id, status, return_date')
              .inFilter('imei', imeisToCheck),
          operation: 'Check product status batch ${i ~/ batchSize + 1}',
        );

        for (final product in response) {
          final imei = product['imei'] as String;
          final productName = product['name'] as String;
          final warehouseIdFromDb = product['warehouse_id']?.toString();
          final status = product['status'] as String;
          final returnDate = product['return_date'] as String?;
          final warehouseIds = warehouses.map((w) => w['id'] as String).toList();
          
          if (status == 'Đã trả ncc') {
            if (mounted) {
              final shouldImport = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Xác nhận nhập lại'),
                  content: Text('Sản phẩm $productName với mã "$imei" đã từng trả ncc ngày ${returnDate != null ? DateFormat('dd/MM/yyyy').format(DateTime.parse(returnDate)) : "không xác định"}. Bạn có đồng ý nhập tiếp không?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Hủy'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Đồng ý'),
                    ),
                  ],
                ),
              );
              if (shouldImport == false) {
                return 'Đã hủy nhập lại sản phẩm với mã "$imei"';
              }
              confirmedImeis.add(imei);
            }
            continue;
          }
          
          if (warehouseIdFromDb != null && warehouseIds.contains(warehouseIdFromDb) ||
              productName == 'Đang sửa' || productName == 'Đang chuyển Nhật') {
            return 'Sản phẩm $productName với mã "$imei" đã tồn tại!';
          }
        }
      }
      return null;
    } catch (e) {
      return 'Lỗi khi kiểm tra mã: $e';
    }
  }

  Future<void> _scanQRCode() async {
    try {
      final scannedData = await Navigator.push<String?>(
        context,
        MaterialPageRoute(builder: (context) => const QRCodeScannerScreen()),
      );

      if (scannedData != null && mounted) {
        setState(() {
          if (imei != null && imei!.isNotEmpty) {
            imei = '$imei\n$scannedData';
          } else {
            imei = scannedData;
          }
          imeiController.text = imei ?? '';
          imeiError = _checkDuplicateImeis(imei!);
        });

        if (imeiError == null) {
          final error = await _checkProductStatus(imei!);
          if (mounted) {
            setState(() => imeiError = error);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Thông báo'),
            content: Text('Lỗi khi quét QR code: $e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Đóng'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<Map<String, dynamic>> _createSnapshot(String ticketId, List<String> imeiList) async {
    final supabase = widget.tenantClient;
    final snapshotData = <String, dynamic>{};

    try {
      if (supplier != null) {
        final supplierData = await retry(
          () => supabase.from('suppliers').select().eq('name', supplier!).single(),
          operation: 'Fetch supplier data',
        );
        snapshotData['suppliers'] = supplierData;
      }

      if (account != null && account != 'Công nợ' && currency != null) {
        final accountData = await retry(
          () => supabase
              .from('financial_accounts')
              .select()
              .eq('name', account!)
              .eq('currency', currency!)
              .single(),
          operation: 'Fetch account data',
        );
        snapshotData['financial_accounts'] = accountData;
      }

      if (imeiList.isNotEmpty) {
        final productsData = await retry(
          () => supabase.from('products').select().inFilter('imei', imeiList),
          operation: 'Fetch products data',
        );
        snapshotData['products'] = productsData;
      }

      snapshotData['import_orders'] = [
        {
          'id': ticketId,
          'supplier': supplier,
          'warehouse_id': warehouseId,
          'warehouse_name': CacheUtil.getWarehouseName(warehouseId),
          'product_id': productId,
          'product_name': CacheUtil.getProductName(productId),
          'imei': imeiList.join(','),
          'quantity': imeiList.length,
          'price': double.tryParse(priceController.text.replaceAll('.', '')) ?? 0,
          'currency': currency,
          'account': account,
          'note': note,
          'total_amount': (double.tryParse(priceController.text.replaceAll('.', '')) ?? 0) * imeiList.length,
        }
      ];

      return snapshotData;
    } catch (e) {
      throw Exception('Failed to create snapshot: $e');
    }
  }

  void addCategoryDialog() async {
    String name = '';
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Thêm chủng loại sản phẩm'),
        content: TextField(
          decoration: const InputDecoration(labelText: 'Tên chủng loại'),
          onChanged: (val) => name = val,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () async {
              if (name.isEmpty) {
                await showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Thông báo'),
                    content: const Text('Tên chủng loại không được để trống!'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Đóng'),
                      ),
                    ],
                  ),
                );
                return;
              }
              try {
                final response = await retry(
                  () => widget.tenantClient
                      .from('categories')
                      .insert({'name': name})
                      .select('id, name')
                      .single(),
                  operation: 'Add category',
                );

                final newCategory = {
                  'id': response['id'] as int,
                  'name': response['name'] as String,
                };

                setState(() {
                  categories.add(newCategory);
                  categories.sort((a, b) => (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase()));
                  categoryId = newCategory['id'] as int;
                  categoryName = newCategory['name'] as String;
                  isAccessory = categoryName == 'Linh phụ kiện';
                });
                Navigator.pop(context);
              } catch (e) {
                await showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Thông báo'),
                    content: Text('Lỗi khi thêm chủng loại: $e'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Đóng'),
                      ),
                    ],
                  ),
                );
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  void addSupplierDialog() async {
    String name = '';
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Thêm nhà cung cấp'),
        content: TextField(
          decoration: const InputDecoration(labelText: 'Tên nhà cung cấp'),
          onChanged: (val) => name = val,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () async {
              if (name.isEmpty) {
                await showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Thông báo'),
                    content: const Text('Tên nhà cung cấp không được để trống!'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Đóng'),
                      ),
                    ],
                  ),
                );
                return;
              }
              try {
                await retry(
                  () => widget.tenantClient.from('suppliers').insert({
                    'name': name,
                    'debt_vnd': 0,
                    'debt_cny': 0,
                    'debt_usd': 0,
                  }),
                  operation: 'Add supplier',
                );
                setState(() {
                  suppliers.add(name);
                  suppliers.sort();
                  supplier = name;
                });
                Navigator.pop(context);
              } catch (e) {
                await showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Thông báo'),
                    content: Text('Lỗi khi thêm nhà cung cấp: $e'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Đóng'),
                      ),
                    ],
                  ),
                );
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  void addProductDialog() async {
    String name = '';
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Thêm sản phẩm'),
        content: TextField(
          decoration: const InputDecoration(labelText: 'Tên sản phẩm'),
          onChanged: (val) => name = val,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () async {
              if (name.isEmpty) {
                await showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Thông báo'),
                    content: const Text('Tên sản phẩm không được để trống!'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Đóng'),
                      ),
                    ],
                  ),
                );
                return;
              }
              if (categoryId == null) {
                await showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Thông báo'),
                    content: const Text('Vui lòng chọn chủng loại sản phẩm trước!'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Đóng'),
                      ),
                    ],
                  ),
                );
                return;
              }
              try {
                final response = await retry(
                  () => widget.tenantClient
                      .from('products_name')
                      .insert({'products': name})
                      .select('id, products')
                      .single(),
                  operation: 'Add product',
                );
                final newProductId = response['id']?.toString();
                if (newProductId != null) {
                  CacheUtil.cacheProductName(newProductId, name);
                  setState(() {
                    products.add({'id': newProductId, 'name': name});
                    products.sort((a, b) => (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase()));
                    productId = newProductId;
                    productName = name;
                  });
                  Navigator.pop(context);
                  await showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Thông báo'),
                      content: const Text('Đã thêm sản phẩm thành công'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Đóng'),
                        ),
                      ],
                    ),
                  );
                }
              } catch (e) {
                await showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Thông báo'),
                    content: Text('Lỗi khi thêm sản phẩm: $e'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Đóng'),
                      ),
                    ],
                  ),
                );
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  void addWarehouseDialog() async {
    String name = '';
    String type = 'nội địa';
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Thêm kho hàng'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              decoration: const InputDecoration(labelText: 'Tên kho hàng'),
              onChanged: (val) => name = val,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: type,
              items: const [
                DropdownMenuItem(value: 'nội địa', child: Text('Nội địa')),
                DropdownMenuItem(value: 'quốc tế', child: Text('Quốc tế')),
              ],
              onChanged: (val) => type = val!,
              decoration: const InputDecoration(
                labelText: 'Loại kho',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () async {
              if (name.isEmpty) {
                await showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Thông báo'),
                    content: const Text('Tên kho hàng không được để trống!'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Đóng'),
                      ),
                    ],
                  ),
                );
                return;
              }
              try {
                final response = await retry(
                  () => widget.tenantClient
                      .from('warehouses')
                      .insert({'name': name, 'type': type})
                      .select('id, name')
                      .single(),
                  operation: 'Add warehouse',
                );
                final newWarehouseId = response['id']?.toString();
                if (newWarehouseId != null) {
                  CacheUtil.cacheWarehouseName(newWarehouseId, name);
                  setState(() {
                    warehouses.add({'id': newWarehouseId, 'name': response['name'], 'type': type});
                    warehouses.sort((a, b) => (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase()));
                    warehouseId = newWarehouseId;
                    warehouseName = name;
                  });
                  Navigator.pop(context);
                }
              } catch (e) {
                await showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Thông báo'),
                    content: Text('Lỗi khi thêm kho hàng: $e'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Đóng'),
                      ),
                    ],
                  ),
                );
              }
            },
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  Future<void> showConfirmDialog(BuildContext scaffoldContext) async {
    if (categoryId == null ||
        supplier == null ||
        productId == null ||
        warehouseId == null ||
        priceController.text.isEmpty ||
        account == null ||
        currency == null ||
        (!isAccessory && (imei == null || imei!.isEmpty) && (quantity <= 0 || imeiPrefix == null || imeiPrefix!.isEmpty))) {
      if (mounted) {
        await showDialog(
          context: scaffoldContext,
          builder: (context) => AlertDialog(
            title: const Text('Thông báo'),
            content: const Text('Vui lòng điền đầy đủ thông tin!'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Đóng'),
              ),
            ],
          ),
        );
      }
      return;
    }

    if (imeiError != null && mounted) {
      await showDialog(
        context: scaffoldContext,
        builder: (context) => AlertDialog(
          title: const Text('Thông báo'),
          content: Text(imeiError!),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
      return;
    }

    final now = DateTime.now();
    final amount = double.tryParse(priceController.text.replaceAll('.', '')) ?? 0;

    List<String> imeiList = [];
    if (isAccessory) {
      if (quantity <= 1) {
        final prefix = imeiPrefix?.isNotEmpty == true ? imeiPrefix! : 'PK';
        imeiList.add('$prefix-${now.millisecondsSinceEpoch}${math.Random().nextInt(1000)}');
      } else {
        final prefix = imeiPrefix?.isNotEmpty == true ? imeiPrefix! : 'PK';
        for (int i = 0; i < quantity; i++) {
          final randomNumbers = math.Random().nextInt(10000000).toString().padLeft(7, '0');
          imeiList.add('$prefix$randomNumbers');
        }
      }
    } else {
      if (imei != null && imei!.isNotEmpty) {
        imeiList = imei!.split('\n').where((e) => e.trim().isNotEmpty).toList();
      } else if (quantity > 0 && imeiPrefix != null && imeiPrefix!.isNotEmpty) {
        final prefix = imeiPrefix!;
        for (int i = 0; i < quantity; i++) {
          final randomNumbers = math.Random().nextInt(10000000).toString().padLeft(7, '0');
          imeiList.add('$prefix$randomNumbers');
        }
      }
    }

    if (imeiList.isEmpty) {
      if (mounted) {
        await showDialog(
          context: scaffoldContext,
          builder: (context) => AlertDialog(
            title: const Text('Thông báo'),
            content: const Text('Vui lòng nhập ít nhất một mã hoặc sinh mã tự động!'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Đóng'),
              ),
            ],
          ),
        );
      }
      return;
    }

    if (imeiList.length > maxImeiQuantity) {
      if (mounted) {
        await showDialog(
          context: scaffoldContext,
          builder: (context) => AlertDialog(
            title: const Text('Thông báo'),
            content: Text('Số lượng mã (${formatNumberLocal(imeiList.length)}) vượt quá giới hạn ${formatNumberLocal(maxImeiQuantity)}. Vui lòng chia thành nhiều phiếu.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Đóng'),
              ),
            ],
          ),
        );
      }
      return;
    }

    if (imeiList.length >= warnImeiQuantity && mounted) {
      await showDialog(
        context: scaffoldContext,
        builder: (context) => AlertDialog(
          title: const Text('Cảnh báo'),
          content: Text('Danh sách mã đã vượt quá ${formatNumberLocal(warnImeiQuantity)} số. Nên chia thành nhiều phiếu nhỏ hơn để tối ưu hiệu suất.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Đã hiểu'),
            ),
          ],
        ),
      );
    }

    final totalAmount = amount * imeiList.length;

    if (mounted) {
      await showDialog(
        context: scaffoldContext,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Xác nhận phiếu nhập'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Chủng loại: ${categoryName ?? 'Không xác định'}'),
                Text('Nhà cung cấp: ${supplier ?? 'Không xác định'}'),
                Text('Kho: ${CacheUtil.getWarehouseName(warehouseId)}'),
                Text('Sản phẩm: ${CacheUtil.getProductName(productId)}'),
                const Text('Danh sách mã:'),
                ...imeiList.take(displayImeiLimit).map((imei) => Text('- $imei')),
                if (imeiList.length > displayImeiLimit)
                  Text('... và ${formatNumberLocal(imeiList.length - displayImeiLimit)} mã khác'),
                Text('Số lượng: ${formatNumberLocal(imeiList.length)}'),
                Text('Số tiền: ${formatNumberLocal(amount)} ${currency ?? ''}'),
                Text('Tổng tiền: ${formatNumberLocal(totalAmount)} ${currency ?? ''}'),
                Text('Tài khoản: ${account ?? 'Không xác định'}'),
                Text('Ghi chú: ${note ?? 'Không có'}'),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Sửa lại')),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(dialogContext);
                setState(() {
                  isProcessing = true;
                });

                try {
                  if (account != 'Công nợ') {
                    final selectedAccount = accounts.firstWhere((acc) => acc['name'] == account);
                    final currentBalance = selectedAccount['balance'] as num? ?? 0;
                    if (currentBalance < totalAmount) {
                      setState(() {
                        isProcessing = false;
                      });
                      if (mounted) {
                        await showDialog(
                          context: scaffoldContext,
                          builder: (context) => AlertDialog(
                            title: const Text('Thông báo'),
                            content: const Text('Tài khoản không đủ số dư để thanh toán!'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('Đóng'),
                              ),
                            ],
                          ),
                        );
                      }
                      return;
                    }
                  }

                  final supabase = widget.tenantClient;

                  for (int i = 0; i < imeiList.length; i += batchSize) {
                    final batchImeis = imeiList.sublist(i, math.min(i + batchSize, imeiList.length));
                    final existingProducts = await retry(
                      () => supabase
                          .from('products')
                          .select('imei, status, return_date')
                          .inFilter('imei', batchImeis),
                      operation: 'Check existing products batch ${i ~/ batchSize + 1}',
                    );

                    for (final product in existingProducts) {
                      final status = product['status'] as String;
                      if (status != 'Đã trả ncc') {
                        final duplicateImei = product['imei'] as String;
                        setState(() {
                          isProcessing = false;
                        });
                        if (mounted) {
                          await showDialog(
                            context: scaffoldContext,
                            builder: (context) => AlertDialog(
                              title: const Text('Thông báo'),
                              content: Text('Sản phẩm với mã "$duplicateImei" đã tồn tại!'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Đóng'),
                                ),
                              ],
                            ),
                          );
                        }
                        return;
                      }
                    }
                  }

                  final exchangeRate = await _getExchangeRate(currency!);
                  if (exchangeRate == 1 && currency != 'VND') {
                    throw Exception('Vui lòng tạo phiếu đổi tiền để cập nhật tỷ giá cho $currency.');
                  }

                  num costPrice = amount;
                  if (currency == 'CNY') {
                    costPrice *= exchangeRate;
                  } else if (currency == 'USD') {
                    costPrice *= exchangeRate;
                  }

                  final importOrderResponse = await retry(
                    () => supabase.from('import_orders').insert({
                      'product_id': productId,
                      'product_name': CacheUtil.getProductName(productId),
                      'warehouse_id': warehouseId,
                      'warehouse_name': CacheUtil.getWarehouseName(warehouseId),
                      'supplier': supplier,
                      'imei': imeiList.join(','),
                      'quantity': imeiList.length,
                      'price': amount,
                      'currency': currency,
                      'account': account,
                      'note': note,
                      'total_amount': totalAmount,
                      'created_at': now.toIso8601String(),
                    }).select('id').single(),
                    operation: 'Insert import order',
                  );

                  final ticketId = importOrderResponse['id']?.toString();
                  if (ticketId == null) {
                    throw Exception('Failed to get ticket ID');
                  }

                  final snapshotData = await retry(
                    () => _createSnapshot(ticketId, imeiList),
                    operation: 'Create snapshot',
                  );

                  await retry(
                    () => supabase.from('snapshots').insert({
                      'ticket_id': ticketId,
                      'ticket_table': 'import_orders',
                      'snapshot_data': snapshotData,
                      'created_at': now.toIso8601String(),
                    }),
                    operation: 'Save snapshot',
                  );

                  for (int i = 0; i < imeiList.length; i += batchSize) {
                    final batchImeis = imeiList.sublist(i, math.min(i + batchSize, imeiList.length));
                    
                    final existingProducts = await retry(
                      () => supabase
                          .from('products')
                          .select('imei, status')
                          .inFilter('imei', batchImeis)
                          .eq('status', 'Đã trả ncc'),
                      operation: 'Check returned products batch ${i ~/ batchSize + 1}',
                    );

                    final existingImeis = existingProducts.map((p) => p['imei'] as String).toSet();
                    final newImeis = batchImeis.where((imei) => !existingImeis.contains(imei)).toList();

                    if (existingImeis.isNotEmpty) {
                      await retry(
                        () => supabase.from('products').update({
                          'name': CacheUtil.getProductName(productId),
                          'category_id': categoryId,
                          'import_price': amount,
                          'import_currency': currency,
                          'supplier': supplier,
                          'import_date': now.toIso8601String(),
                          'warehouse_id': warehouseId,
                          'warehouse_name': CacheUtil.getWarehouseName(warehouseId),
                          'cost_price': costPrice,
                          'status': 'Tồn kho',
                        }).inFilter('imei', existingImeis.toList()),
                        operation: 'Update returned products batch ${i ~/ batchSize + 1}',
                      );
                    }

                    if (newImeis.isNotEmpty) {
                      await retry(
                        () => supabase.from('products').insert(newImeis.map((generatedIMEI) => {
                          'product_id': productId,
                          'name': CacheUtil.getProductName(productId),
                          'category_id': categoryId,
                          'imei': generatedIMEI,
                          'import_price': amount,
                          'import_currency': currency,
                          'supplier': supplier,
                          'import_date': now.toIso8601String(),
                          'warehouse_id': warehouseId,
                          'warehouse_name': CacheUtil.getWarehouseName(warehouseId),
                          'cost_price': costPrice,
                          'status': 'Tồn kho',
                        }).toList()),
                        operation: 'Insert new products batch ${i ~/ batchSize + 1}',
                      );
                    }
                  }

                  if (account == 'Công nợ') {
                    final currentSupplier = await retry(
                      () => supabase
                          .from('suppliers')
                          .select('debt_vnd, debt_cny, debt_usd')
                          .eq('name', supplier!)
                          .single(),
                      operation: 'Fetch supplier debt',
                    );

                    String debtColumn;
                    if (currency == 'VND') {
                      debtColumn = 'debt_vnd';
                    } else if (currency == 'CNY') {
                      debtColumn = 'debt_cny';
                    } else if (currency == 'USD') {
                      debtColumn = 'debt_usd';
                    } else {
                      throw Exception('Loại tiền tệ không được hỗ trợ: $currency');
                    }

                    final currentDebt = currentSupplier[debtColumn] as num? ?? 0;
                    final updatedDebt = currentDebt + totalAmount;

                    await retry(
                      () => supabase
                          .from('suppliers')
                          .update({debtColumn: updatedDebt})
                          .eq('name', supplier!),
                      operation: 'Update supplier debt',
                    );
                  } else {
                    final selectedAccount = accounts.firstWhere((acc) => acc['name'] == account);
                    final currentBalance = selectedAccount['balance'] as num? ?? 0;
                    final updatedBalance = currentBalance - totalAmount;

                    await retry(
                      () => supabase
                          .from('financial_accounts')
                          .update({'balance': updatedBalance})
                          .eq('name', account!)
                          .eq('currency', currency!),
                      operation: 'Update account balance',
                    );
                  }

                  final currentProductId = productId;
                  final currentImeiListLength = imeiList.length;

                  await NotificationService.showNotification(
                    132,
                    'Phiếu Nhập Hàng Đã Tạo',
                    'Đã nhập hàng "${CacheUtil.getProductName(currentProductId)}" số lượng ${formatNumberLocal(currentImeiListLength)} chiếc',
                    'import_created',
                  );

                  if (mounted) {
                    setState(() {
                      categoryId = null;
                      categoryName = null;
                      supplier = null;
                      productId = null;
                      productName = null;
                      imei = '';
                      imeiController.text = '';
                      quantity = 1;
                      imeiPrefix = null;
                      price = null;
                      priceController.text = '';
                      currency = null;
                      account = null;
                      note = null;
                      warehouseId = null;
                      warehouseName = null;
                      isAccessory = false;
                      accountNames = [];
                      imeiError = null;
                      isProcessing = false;
                      _updateAccountNames(null);
                    });

                    await _fetchInitialData();

                    ScaffoldMessenger.of(scaffoldContext).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Đã nhập hàng "${CacheUtil.getProductName(currentProductId)}" số lượng ${formatNumberLocal(currentImeiListLength)} chiếc',
                          style: const TextStyle(color: Colors.white),
                        ),
                        backgroundColor: Colors.black,
                        behavior: SnackBarBehavior.floating,
                        margin: const EdgeInsets.all(8),
                        duration: const Duration(seconds: 3),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    );
                  }
                } catch (e) {
                  setState(() {
                    isProcessing = false;
                  });
                  if (mounted) {
                    await showDialog(
                      context: scaffoldContext,
                      builder: (context) => AlertDialog(
                        title: const Text('Thông báo'),
                        content: Text('Lỗi khi tạo phiếu: $e'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Đóng'),
                          ),
                        ],
                      ),
                    );
                  }
                }
              },
              child: const Text('Tạo phiếu'),
            ),
          ],
        ),
      );
    }
  }

  Widget wrapField(Widget child, {bool isImeiField = false, bool isSupplierField = false, bool isImeiList = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      margin: const EdgeInsets.symmetric(vertical: 4),
      height: isImeiField ? 80 : isImeiList ? 120 : isSupplierField ? 56 : 48,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: imeiError != null && isImeiField ? Colors.red : Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
                onPressed: _fetchInitialData,
                child: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Phiếu nhập hàng', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: wrapField(
                        DropdownButtonFormField<int>(
                          value: categoryId,
                          items: categories.map((e) => DropdownMenuItem<int>(
                                value: e['id'] as int,
                                child: Text(e['name'] as String),
                              )).toList(),
                          decoration: const InputDecoration(
                            labelText: 'Chủng loại sản phẩm',
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          onChanged: (val) {
                            if (val != null) {
                              final selectedCategory = categories.firstWhere((e) => e['id'] == val);
                              setState(() {
                                categoryId = val;
                                categoryName = selectedCategory['name'] as String;
                                isAccessory = categoryName == 'Linh phụ kiện';
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: addCategoryDialog,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: wrapField(
                        Autocomplete<String>(
                          optionsBuilder: (textEditingValue) {
                            final query = textEditingValue.text.toLowerCase();
                            final filtered = suppliers
                                .where((e) => e.toLowerCase().contains(query))
                                .toList()
                              ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
                            return filtered.isNotEmpty ? filtered.take(10).toList() : ['Không tìm thấy nhà cung cấp'];
                          },
                          onSelected: (val) {
                            if (val != 'Không tìm thấy nhà cung cấp') {
                              setState(() => supplier = val);
                            }
                          },
                          fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                            controller.text = supplier ?? '';
                            return TextField(
                              controller: controller,
                              focusNode: focusNode,
                              onChanged: (val) => setState(() => supplier = val.isNotEmpty ? val : null),
                              decoration: const InputDecoration(
                                labelText: 'Nhà cung cấp',
                                border: InputBorder.none,
                                isDense: true,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: addSupplierDialog,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: wrapField(
                        Autocomplete<Map<String, dynamic>>(
                          optionsBuilder: (textEditingValue) {
                            final query = textEditingValue.text.toLowerCase();
                            final filtered = products
                                .where((e) => (e['name'] as String).toLowerCase().contains(query))
                                .toList()
                              ..sort((a, b) => (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase()));
                            return filtered.isNotEmpty ? filtered.take(10).toList() : [{'id': '', 'name': 'Không tìm thấy sản phẩm'}];
                          },
                          displayStringForOption: (option) => option['name'] as String,
                          onSelected: (val) {
                            if (val['id'].isNotEmpty) {
                              setState(() {
                                productId = val['id'] as String;
                                productName = val['name'] as String;
                              });
                            }
                          },
                          fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                            controller.text = productName ?? '';
                            return TextField(
                              controller: controller,
                              focusNode: focusNode,
                              onChanged: (val) => setState(() {
                                productId = null;
                                productName = val.isNotEmpty ? val : null;
                              }),
                              decoration: const InputDecoration(
                                labelText: 'Sản phẩm',
                                border: InputBorder.none,
                                isDense: true,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: addProductDialog,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: wrapField(
                        Autocomplete<Map<String, dynamic>>(
                          optionsBuilder: (textEditingValue) {
                            final query = textEditingValue.text.toLowerCase();
                            final filtered = warehouses
                                .where((e) => (e['name'] as String).toLowerCase().contains(query))
                                .toList()
                              ..sort((a, b) => (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase()));
                            return filtered.isNotEmpty ? filtered.take(10).toList() : [{'id': '', 'name': 'Không tìm thấy kho'}];
                          },
                          displayStringForOption: (option) => option['name'] as String,
                          onSelected: (val) {
                            if (val['id'].isNotEmpty) {
                              setState(() {
                                warehouseId = val['id'] as String;
                                warehouseName = val['name'] as String;
                              });
                            }
                          },
                          fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                            controller.text = warehouseName ?? '';
                            return TextField(
                              controller: controller,
                              focusNode: focusNode,
                              onChanged: (val) => setState(() {
                                warehouseId = null;
                                warehouseName = val.isNotEmpty ? val : null;
                              }),
                              decoration: const InputDecoration(
                                labelText: 'Kho hàng',
                                border: InputBorder.none,
                                isDense: true,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: addWarehouseDialog,
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
                if (!isAccessory)
                  wrapField(
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: imeiController,
                            maxLines: null,
                            onChanged: (val) {
                              setState(() {
                                imei = val;
                                imeiError = _checkDuplicateImeis(val);
                              });

                              if (imeiError == null) {
                                _checkProductStatus(val).then((error) {
                                  if (mounted) {
                                    setState(() => imeiError = error);
                                  }
                                });
                              }
                            },
                            decoration: InputDecoration(
                              labelText: 'Nhập imei hoặc quét QR (mỗi dòng 1)',
                              border: InputBorder.none,
                              isDense: true,
                              errorText: imeiError,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _scanQRCode,
                          icon: const Icon(Icons.qr_code_scanner),
                        ),
                      ],
                    ),
                    isImeiField: true,
                  ),
                Row(
                  children: [
                    Expanded(
                      child: wrapField(
                        TextFormField(
                          keyboardType: TextInputType.number,
                          onChanged: (val) => setState(() {
                            quantity = int.tryParse(val) ?? 1;
                          }),
                          decoration: const InputDecoration(
                            labelText: 'Số lượng',
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: wrapField(
                        TextFormField(
                          onChanged: (val) => setState(() {
                            imeiPrefix = val.isNotEmpty ? val : null;
                          }),
                          decoration: const InputDecoration(
                            labelText: 'Đầu mã bắt đầu',
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                wrapField(
                  TextFormField(
                    controller: priceController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [ThousandsFormatterLocal()],
                    onChanged: (val) => setState(() {
                      price = val.replaceAll('.', '');
                    }),
                    decoration: const InputDecoration(
                      labelText: 'Số tiền',
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: wrapField(
                        DropdownButtonFormField<String>(
                          value: currency,
                          hint: const Text('Loại tiền'),
                          items: currencies.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                          decoration: const InputDecoration(
                            labelText: 'Đơn vị tiền',
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          onChanged: (val) => setState(() {
                            currency = val;
                            _updateAccountNames(val);
                          }),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: wrapField(
                        DropdownButtonFormField<String>(
                          value: account,
                          items: accountNames.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                          decoration: const InputDecoration(
                            labelText: 'Tài khoản',
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          onChanged: (val) => setState(() => account = val),
                        ),
                      ),
                    ),
                  ],
                ),
                wrapField(
                  TextFormField(
                    decoration: const InputDecoration(
                      labelText: 'Ghi chú ý',
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onChanged: (val) => setState(() => note = val),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: isProcessing ? null : () => showConfirmDialog(context),
                  child: const Text('Xác nhận'),
                ),
              ],
            ),
          ),
          if (isProcessing)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class QRCodeScannerScreen extends StatefulWidget {
  const QRCodeScannerScreen({super.key});

  @override
  State<QRCodeScannerScreen> createState() => _QRCodeScannerScreenState();
}

class _QRCodeScannerScreenState extends State<QRCodeScannerScreen> {
  final MobileScannerController controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );
  bool scanned = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Quét mã QR', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () {
              controller.toggleTorch();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 5,
            child: MobileScanner(
              controller: controller,
              onDetect: (BarcodeCapture capture) {
                if (!scanned) {
                  final String? code = capture.barcodes.first.rawValue;
                  if (code != null) {
                    setState(() {
                      scanned = true;
                    });
                    Navigator.pop(context, code);
                  }
                }
              },
            ),
          ),
          Expanded(
            flex: 1,
            child: Center(
              child: const Text(
                'Quét mã QR để lấy mã số',
                style: TextStyle(fontSize: 18, color: Colors.black),
              ),
            ),
          ),
        ],
      ),
    );
  }
}