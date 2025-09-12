import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:math';
import 'package:mobile_scanner/mobile_scanner.dart';

class ThousandsFormatterLocal extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    String newText = newValue.text.replaceAll('.', '').replaceAll(',', '');
    if (newText.isEmpty) return newValue;
    final intValue = int.tryParse(newText);
    if (intValue == null) return newValue;
    final formatted = NumberFormat('#,###', 'vi_VN').format(intValue).replaceAll(',', '.');
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

String formatNumberLocal(num value) {
  return NumberFormat('#,###', 'vi_VN').format(value).replaceAll(',', '.');
}

class InitialDataScreen extends StatefulWidget {
  final SupabaseClient tenantClient;

  const InitialDataScreen({super.key, required this.tenantClient});

  @override
  _InitialDataScreenState createState() => _InitialDataScreenState();
}

class _InitialDataScreenState extends State<InitialDataScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Biến cho tab "Thêm sản phẩm"
  int? categoryId;
  String? categoryName;
  String? product;
  String? imei = '';
  int quantity = 1;
  String? imeiPrefix;
  String? price;
  String? currency;
  String? warehouse;
  bool isAccessory = false;
  String? imeiError;
  List<Map<String, dynamic>> categories = [];
  List<String> products = [];
  List<String> currencies = ['VND', 'CNY', 'USD'];
  List<String> warehouses = [];
  bool isLoadingProducts = true;
  String? errorMessageProducts;

  // Biến cho tab "Thêm công nợ"
  String selectedPartnerType = 'supplier';
  final List<Map<String, String>> partnerTypeOptions = [
    {'value': 'supplier', 'display': 'Nhà Cung Cấp'},
    {'value': 'customer', 'display': 'Khách Hàng'},
    {'value': 'fixer', 'display': 'Đơn Vị Fix Lỗi'},
    {'value': 'transporter', 'display': 'Đơn Vị Vận Chuyển'},
  ];
  String? partnerName;
  final TextEditingController partnerDebtController = TextEditingController();
  String partnerCurrency = 'VND';
  List<String> partnerNames = [];
  bool isLoadingPartners = true;
  String? errorMessagePartners;

  // Controller cho TextField IMEI và Số tiền
  final TextEditingController imeiController = TextEditingController();
  final TextEditingController priceController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchProductData();
    _fetchPartnerData();
    imeiController.text = imei ?? '';
    priceController.text = price ?? '';
  }

  @override
  void dispose() {
    imeiController.dispose();
    priceController.dispose();
    partnerDebtController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchProductData() async {
    setState(() {
      isLoadingProducts = true;
      errorMessageProducts = null;
    });

    try {
      final categoryResponse = await widget.tenantClient.from('categories').select('id, name');
      final categoryList = (categoryResponse as List<dynamic>)
          .map((e) => {
                'id': e['id'] as int,
                'name': e['name'] as String,
              })
          .toList();

      final productResponse = await widget.tenantClient.from('products_name').select('products');
      final productList = (productResponse as List<dynamic>)
          .map((e) => e['products'] as String?)
          .where((e) => e != null)
          .cast<String>()
          .toSet()
          .toList();

      final warehouseResponse = await widget.tenantClient.from('warehouses').select('name');
      final warehouseList = (warehouseResponse as List<dynamic>)
          .map((e) => e['name'] as String?)
          .where((e) => e != null)
          .cast<String>()
          .toList();

      setState(() {
        categories = categoryList;
        products = productList;
        warehouses = warehouseList;
        isLoadingProducts = false;
      });
    } catch (e) {
      setState(() {
        errorMessageProducts = 'Không thể tải dữ liệu sản phẩm: $e';
        isLoadingProducts = false;
      });
    }
  }

  Future<void> _fetchPartnerData() async {
    setState(() {
      isLoadingPartners = true;
      errorMessagePartners = null;
    });

    try {
      List<String> partnerList = [];

      if (selectedPartnerType == 'supplier') {
        final response = await widget.tenantClient.from('suppliers').select('name');
        partnerList = (response as List<dynamic>)
            .map((e) => e['name'] as String?)
            .where((e) => e != null)
            .cast<String>()
            .toList();
      } else if (selectedPartnerType == 'customer') {
        final response = await widget.tenantClient.from('customers').select('name');
        partnerList = (response as List<dynamic>)
            .map((e) => e['name'] as String?)
            .where((e) => e != null)
            .cast<String>()
            .toList();
      } else if (selectedPartnerType == 'fixer') {
        final response = await widget.tenantClient.from('fix_units').select('name');
        partnerList = (response as List<dynamic>)
            .map((e) => e['name'] as String?)
            .where((e) => e != null)
            .cast<String>()
            .toList();
      } else if (selectedPartnerType == 'transporter') {
        final response = await widget.tenantClient.from('transporters').select('name');
        partnerList = (response as List<dynamic>)
            .map((e) => e['name'] as String?)
            .where((e) => e != null)
            .cast<String>()
            .toList();
      }

      setState(() {
        partnerNames = partnerList;
        isLoadingPartners = false;
      });
    } catch (e) {
      setState(() {
        errorMessagePartners = 'Không thể tải dữ liệu đối tác: $e';
        isLoadingPartners = false;
      });
    }
  }

  Future<num> _getExchangeRate(String currency) async {
    try {
      final response = await widget.tenantClient
          .from('financial_orders')
          .select('rate_vnd_cny, rate_vnd_usd')
          .eq('type', 'exchange')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) return 1;
      if (currency == 'CNY' && response['rate_vnd_cny'] != null) {
        return (response['rate_vnd_cny'] as num) ?? 1;
      } else if (currency == 'USD' && response['rate_vnd_usd'] != null) {
        return (response['rate_vnd_usd'] as num) ?? 1;
      }
      return 1;
    } catch (e) {
      return 1;
    }
  }

  String? _checkDuplicateImeis(String input) {
    final lines = input.split('\n').where((e) => e.trim().isNotEmpty).toList();
    final seen = <String>{};
    for (var line in lines) {
      if (seen.contains(line)) return 'IMEI "$line" đã được nhập ở dòng trước!';
      seen.add(line);
    }
    return null;
  }

  Future<String?> _checkProductStatus(String input) async {
    final lines = input.split('\n').where((e) => e.trim().isNotEmpty).toList();

    for (var line in lines) {
      try {
        final productResponse = await widget.tenantClient
            .from('products')
            .select('name, status')
            .eq('imei', line)
            .maybeSingle();

        if (productResponse != null) {
          final productName = productResponse['name'] as String;
          final status = productResponse['status'] as String;
          if (warehouses.contains(status) || status == 'Đang sửa' || status == 'đang vận chuyển' || status == 'Tồn kho') {
            return 'Sản phẩm $productName IMEI $line đã tồn tại!';
          }
        }
      } catch (e) {
        return 'Lỗi khi kiểm tra IMEI "$line": $e';
      }
    }
    return null;
  }

  Future<void> _scanQRCode() async {
    try {
      final scannedData = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => const QRCodeScannerScreen(),
        ),
      );

      if (scannedData != null && scannedData is String) {
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
          await _checkProductStatus(imei!).then((error) {
            setState(() {
              imeiError = error;
            });
          });
        }
      }
    } catch (e) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Lỗi'),
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

  Future<void> addCategoryDialog() async {
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
              if (name.isNotEmpty) {
                try {
                  final response = await widget.tenantClient
                      .from('categories')
                      .insert({'name': name})
                      .select('id, name')
                      .single();

                  final newCategory = {
                    'id': response['id'] as int,
                    'name': response['name'] as String,
                  };

                  setState(() {
                    categories.add(newCategory);
                    categoryId = newCategory['id'] as int;
                    categoryName = newCategory['name'] as String;
                    isAccessory = categoryName == 'Linh phụ kiện';
                  });
                  Navigator.pop(context);
                } catch (e) {
                  await showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Lỗi'),
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
              } else {
                await showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Lỗi'),
                    content: const Text('Tên chủng loại không được để trống!'),
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

  Future<void> addProductDialog() async {
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
                    title: const Text('Lỗi'),
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
                    title: const Text('Lỗi'),
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
                await widget.tenantClient.from('products_name').insert({
                  'products': name,
                  'category_id': categoryId,
                });
                setState(() {
                  products.add(name);
                  product = name;
                });
                Navigator.pop(context);
                await showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Thành công'),
                    content: const Text('Đã thêm sản phẩm thành công'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Đóng'),
                      ),
                    ],
                  ),
                );
              } catch (e) {
                await showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Lỗi'),
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

  Future<void> addWarehouseDialog() async {
    String name = '';
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Thêm kho hàng'),
        content: TextField(
          decoration: const InputDecoration(labelText: 'Tên kho hàng'),
          onChanged: (val) => name = val,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () async {
              if (name.isNotEmpty) {
                try {
                  await widget.tenantClient.from('warehouses').insert({'name': name});
                  setState(() {
                    warehouses.add(name);
                    warehouse = name;
                  });
                  Navigator.pop(context);
                  await showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Thành công'),
                      content: const Text('Đã thêm kho hàng thành công'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Đóng'),
                        ),
                      ],
                    ),
                  );
                } catch (e) {
                  await showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Lỗi'),
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
              } else {
                await showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Lỗi'),
                    content: const Text('Tên kho hàng không được để trống!'),
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

  Future<void> addPartnerDialog() async {
    String name = '';
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Thêm ${partnerTypeOptions.firstWhere((opt) => opt['value'] == selectedPartnerType)['display']}'),
        content: TextField(
          decoration: const InputDecoration(labelText: 'Tên đối tác'),
          onChanged: (val) => name = val,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Hủy')),
          ElevatedButton(
            onPressed: () async {
              if (name.isNotEmpty) {
                try {
                  final table = selectedPartnerType == 'supplier'
                      ? 'suppliers'
                      : selectedPartnerType == 'customer'
                          ? 'customers'
                          : selectedPartnerType == 'fixer'
                              ? 'fix_units'
                              : 'transporters';

                  await widget.tenantClient.from(table).insert(
                        selectedPartnerType == 'transporter'
                            ? {'name': name, 'debt': 0}
                            : {
                                'name': name,
                                'debt_vnd': 0,
                                'debt_cny': 0,
                                'debt_usd': 0,
                              },
                      );

                  setState(() {
                    partnerNames.add(name);
                    partnerName = name;
                  });
                  Navigator.pop(context);
                  await showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Thành công'),
                      content: const Text('Đã thêm đối tác thành công'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Đóng'),
                        ),
                      ],
                    ),
                  );
                } catch (e) {
                  await showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Lỗi'),
                      content: Text('Lỗi khi thêm đối tác: $e'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Đóng'),
                        ),
                      ],
                    ),
                  );
                }
              } else {
                await showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Lỗi'),
                    content: const Text('Tên đối tác không được để trống!'),
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

  Future<void> saveProduct() async {
    if (categoryId == null ||
        product == null ||
        warehouse == null ||
        priceController.text.isEmpty ||
        currency == null ||
        (isAccessory == false &&
            imei!.isEmpty &&
            (quantity <= 0 || imeiPrefix == null || imeiPrefix!.isEmpty))) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Lỗi'),
          content: const Text('Vui lòng điền đầy đủ thông tin!'),
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

    if (imeiError != null) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Lỗi'),
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

    // Kiểm tra warehouse_id và warehouse_name
    final warehouseResponse = await widget.tenantClient
        .from('warehouses')
        .select('id')
        .eq('name', warehouse!)
        .maybeSingle();
    if (warehouseResponse == null) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Lỗi'),
          content: Text('Kho "$warehouse" không tồn tại!'),
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
    final warehouseId = warehouseResponse['id'];

    // Kiểm tra product_id
    final productResponse = await widget.tenantClient
        .from('products_name')
        .select('id')
        .eq('products', product!)
        .maybeSingle();
    if (productResponse == null) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Lỗi'),
          content: Text('Sản phẩm "$product" không tồn tại trong products_name!'),
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
    final productId = productResponse['id'];

    List<String> imeiList = [];
    if (isAccessory) {
      if (quantity > 0) {
        final prefix = imeiPrefix?.isNotEmpty == true ? imeiPrefix! : 'PK';
        for (int i = 0; i < quantity; i++) {
          final randomNumbers = Random().nextInt(10000000).toString().padLeft(7, '0');
          imeiList.add('$prefix$randomNumbers');
        }
      } else {
        imeiList.add('PK-${now.millisecondsSinceEpoch}${Random().nextInt(1000)}');
      }
    } else {
      if (imei != null && imei!.isNotEmpty) {
        imeiList = imei!.split('\n').where((e) => e.trim().isNotEmpty).toList();
      } else if (quantity > 0 && imeiPrefix != null && imeiPrefix!.isNotEmpty) {
        final prefix = imeiPrefix!;
        for (int i = 0; i < quantity; i++) {
          final randomNumbers = Random().nextInt(10000000).toString().padLeft(7, '0');
          imeiList.add('$prefix$randomNumbers');
        }
      }
    }

    if (imeiList.isEmpty) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Lỗi'),
          content: const Text('Vui lòng nhập ít nhất một IMEI hoặc sinh IMEI tự động!'),
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

    final totalAmount = amount * imeiList.length;

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xác nhận sản phẩm'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Chủng loại: $categoryName'),
              Text('Kho: $warehouse'),
              Text('Sản phẩm: $product'),
              const Text('Danh sách IMEI / Mã:'),
              ...imeiList.map((imei) => Text('- $imei')),
              Text('Số lượng: ${imeiList.length}'),
              Text('Số tiền: ${formatNumberLocal(amount)} $currency'),
              Text('Tổng tiền: ${formatNumberLocal(totalAmount)} $currency'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Sửa lại')),
          ElevatedButton(
            onPressed: () async {
              try {
                final exchangeRate = await _getExchangeRate(currency!);
                if (exchangeRate == 1 && currency != 'VND') {
                  throw Exception('Vui lòng tạo 1 phiếu đổi tiền để cập nhật tỉ giá do giá nhập bằng ngoại tệ.');
                }

                num costPrice = amount;
                if (currency == 'CNY') {
                  costPrice = amount * exchangeRate;
                } else if (currency == 'USD') {
                  costPrice = amount * exchangeRate;
                }

                for (var generatedIMEI in imeiList) {
                  final existingProduct = await widget.tenantClient
                      .from('products')
                      .select('imei')
                      .eq('imei', generatedIMEI)
                      .maybeSingle();

                  if (existingProduct != null) {
                    throw Exception('Sản phẩm với IMEI $generatedIMEI đã tồn tại!');
                  }

                  await widget.tenantClient.from('products').insert({
                    'name': product,
                    'category_id': categoryId,
                    'imei': generatedIMEI,
                    'import_price': amount,
                    'import_currency': currency,
                    'import_date': now.toIso8601String(),
                    'status': 'Tồn kho',
                    'cost_price': costPrice,
                    'warehouse_id': warehouseId,
                    'warehouse_name': warehouse,
                    'product_id': productId,
                  });
                }

                setState(() {
                  categoryId = null;
                  categoryName = null;
                  product = null;
                  imei = '';
                  imeiController.text = '';
                  quantity = 1;
                  imeiPrefix = null;
                  price = null;
                  priceController.text = '';
                  currency = null;
                  warehouse = null;
                  isAccessory = false;
                  imeiError = null;
                });

                await _fetchProductData();

                Navigator.pop(dialogContext);
                await showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Thành công'),
                    content: const Text('Đã thêm sản phẩm thành công'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Đóng'),
                      ),
                    ],
                  ),
                );
              } catch (e) {
                Navigator.pop(dialogContext);
                await showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Lỗi'),
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
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
  }

  Future<void> saveDebt() async {
    if (partnerName == null || partnerDebtController.text.isEmpty || partnerCurrency.isEmpty) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Lỗi'),
          content: const Text('Vui lòng điền đầy đủ thông tin!'),
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

    final debtAmount = double.tryParse(partnerDebtController.text.replaceAll('.', '')) ?? 0;
    if (debtAmount <= 0) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Lỗi'),
          content: const Text('Số tiền công nợ phải lớn hơn 0!'),
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

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xác nhận công nợ'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'Loại đối tác: ${partnerTypeOptions.firstWhere((opt) => opt['value'] == selectedPartnerType)['display']}'),
              Text('Tên đối tác: $partnerName'),
              Text('Số tiền: ${formatNumberLocal(debtAmount)} $partnerCurrency'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Sửa lại')),
          ElevatedButton(
            onPressed: () async {
              try {
                final table = selectedPartnerType == 'supplier'
                    ? 'suppliers'
                    : selectedPartnerType == 'customer'
                        ? 'customers'
                        : selectedPartnerType == 'fixer'
                            ? 'fix_units'
                            : 'transporters';

                final existingPartner = await widget.tenantClient
                    .from(table)
                    .select()
                    .eq('name', partnerName!)
                    .maybeSingle();

                if (existingPartner == null) {
                  await widget.tenantClient.from(table).insert(
                        selectedPartnerType == 'transporter'
                            ? {'name': partnerName, 'debt': 0}
                            : {
                                'name': partnerName,
                                'debt_vnd': 0,
                                'debt_cny': 0,
                                'debt_usd': 0,
                              },
                      );
                }

                final debtColumn = selectedPartnerType == 'transporter'
                    ? 'debt'
                    : partnerCurrency == 'VND'
                        ? 'debt_vnd'
                        : partnerCurrency == 'CNY'
                            ? 'debt_cny'
                            : 'debt_usd';

                final currentDebt = existingPartner != null
                    ? double.tryParse(existingPartner[debtColumn].toString()) ?? 0
                    : 0;
                final updatedDebt = currentDebt + debtAmount;

                await widget.tenantClient
                    .from(table)
                    .update({debtColumn: updatedDebt})
                    .eq('name', partnerName!);

                setState(() {
                  partnerName = null;
                  partnerDebtController.clear();
                  partnerCurrency = selectedPartnerType == 'transporter' ? 'VND' : 'VND';
                });

                await _fetchPartnerData();

                Navigator.pop(dialogContext);
                await showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Thành công'),
                    content: const Text('Đã thêm công nợ thành công'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Đóng'),
                      ),
                    ],
                  ),
                );
              } catch (e) {
                Navigator.pop(dialogContext);
                await showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Lỗi'),
                    content: Text('Lỗi khi thêm công nợ: $e'),
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
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );
  }

  Widget wrapField(Widget child) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: imeiError != null ? Colors.red : Colors.grey.shade300),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Nhập Dữ Liệu Đầu Kỳ', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
          bottom: TabBar(
            controller: _tabController,
            labelColor: Colors.amber,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.amber,
            tabs: const [
              Tab(text: 'Thêm sản phẩm'),
              Tab(text: 'Thêm công nợ'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            isLoadingProducts
                ? const Center(child: CircularProgressIndicator())
                : errorMessageProducts != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(errorMessageProducts!),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _fetchProductData,
                              child: const Text('Thử lại'),
                            ),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
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
                                        final selectedCategory = categories.firstWhere((e) => e['id'] == val);
                                        setState(() {
                                          categoryId = val;
                                          categoryName = selectedCategory['name'] as String;
                                          isAccessory = categoryName == 'Linh phụ kiện';
                                        });
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
                                        return products
                                            .where((e) => e.toLowerCase().contains(query))
                                            .toList()
                                          ..sort((a, b) => a.toLowerCase().indexOf(query).compareTo(b.toLowerCase().indexOf(query)))
                                          ..take(3);
                                      },
                                      onSelected: (val) {
                                        setState(() {
                                          product = val;
                                        });
                                      },
                                      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                                        return TextField(
                                          controller: controller,
                                          focusNode: focusNode,
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
                                    Autocomplete<String>(
                                      optionsBuilder: (textEditingValue) {
                                        final query = textEditingValue.text.toLowerCase();
                                        return warehouses
                                            .where((e) => e.toLowerCase().contains(query))
                                            .toList()
                                          ..sort((a, b) => a.toLowerCase().indexOf(query).compareTo(b.toLowerCase().indexOf(query)))
                                          ..take(3);
                                      },
                                      onSelected: (val) => setState(() => warehouse = val),
                                      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                                        return TextField(
                                          controller: controller,
                                          focusNode: focusNode,
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
                                      child: SizedBox(
                                        height: 80,
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
                                                setState(() {
                                                  imeiError = error;
                                                });
                                              });
                                            }
                                          },
                                          decoration: InputDecoration(
                                            labelText: 'IMEI (mỗi dòng 1)',
                                            border: InputBorder.none,
                                            isDense: true,
                                            errorText: imeiError,
                                          ),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: _scanQRCode,
                                      icon: const Icon(Icons.qr_code_scanner),
                                    ),
                                  ],
                                ),
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
                                const SizedBox(width: 12),
                                Expanded(
                                  child: wrapField(
                                    TextFormField(
                                      onChanged: (val) => setState(() {
                                        imeiPrefix = val;
                                      }),
                                      decoration: const InputDecoration(
                                        labelText: 'Đầu mã IMEI',
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
                            wrapField(
                              DropdownButtonFormField<String>(
                                value: currency,
                                items: currencies.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                                decoration: const InputDecoration(
                                  labelText: 'Đơn vị tiền',
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                                onChanged: (val) => setState(() => currency = val),
                              ),
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: saveProduct,
                              child: const Text('Xác nhận'),
                            ),
                          ],
                        ),
                      ),
            isLoadingPartners
                ? const Center(child: CircularProgressIndicator())
                : errorMessagePartners != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(errorMessagePartners!),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _fetchPartnerData,
                              child: const Text('Thử lại'),
                            ),
                          ],
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            wrapField(
                              DropdownButtonFormField<String>(
                                value: selectedPartnerType,
                                items: partnerTypeOptions
                                    .map((opt) => DropdownMenuItem(
                                          value: opt['value'],
                                          child: Text(opt['display']!),
                                        ))
                                    .toList(),
                                decoration: const InputDecoration(
                                  labelText: 'Loại đối tác',
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                                onChanged: (val) {
                                  setState(() {
                                    selectedPartnerType = val ?? 'supplier';
                                    partnerName = null;
                                    partnerCurrency = selectedPartnerType == 'transporter' ? 'VND' : 'VND';
                                  });
                                  _fetchPartnerData();
                                },
                              ),
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: wrapField(
                                    Autocomplete<String>(
                                      optionsBuilder: (textEditingValue) {
                                        final query = textEditingValue.text.toLowerCase();
                                        return partnerNames
                                            .where((e) => e.toLowerCase().contains(query))
                                            .toList()
                                          ..sort((a, b) => a.toLowerCase().indexOf(query).compareTo(b.toLowerCase().indexOf(query)))
                                          ..take(3);
                                      },
                                      onSelected: (val) => setState(() => partnerName = val),
                                      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
                                        return TextField(
                                          controller: controller,
                                          focusNode: focusNode,
                                          decoration: const InputDecoration(
                                            labelText: 'Tên đối tác',
                                            border: InputBorder.none,
                                            isDense: true,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: addPartnerDialog,
                                  icon: const Icon(Icons.add_circle_outline),
                                ),
                              ],
                            ),
                            wrapField(
                              TextFormField(
                                controller: partnerDebtController,
                                keyboardType: TextInputType.number,
                                inputFormatters: [ThousandsFormatterLocal()],
                                decoration: const InputDecoration(
                                  labelText: 'Số tiền',
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                              ),
                            ),
                            wrapField(
                              DropdownButtonFormField<String>(
                                value: partnerCurrency,
                                items: (selectedPartnerType == 'transporter'
                                        ? ['VND']
                                        : ['VND', 'CNY', 'USD'])
                                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                                    .toList(),
                                decoration: const InputDecoration(
                                  labelText: 'Loại tiền tệ',
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                                onChanged: (val) => setState(() => partnerCurrency = val ?? 'VND'),
                              ),
                            ),
                            const SizedBox(height: 20),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                              onPressed: saveDebt,
                              child: const Text('Xác nhận'),
                            ),
                          ],
                        ),
                      ),
          ],
        ),
      ),
    );
  }
}

class QRCodeScannerScreen extends StatefulWidget {
  const QRCodeScannerScreen({super.key});

  @override
  _QRCodeScannerScreenState createState() => _QRCodeScannerScreenState();
}

class _QRCodeScannerScreenState extends State<QRCodeScannerScreen> {
  MobileScannerController controller = MobileScannerController(
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
        title: const Text('Quét QR Code', style: TextStyle(color: Colors.white)),
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
        children: <Widget>[
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
                'Quét QR code để lấy IMEI',
                style: TextStyle(fontSize: 18, color: Colors.black),
              ),
            ),
          ),
        ],
      ),
    );
  }
}