import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:intl/intl.dart';
import 'sale_summary.dart';
import 'dart:math' as math;

// Cache utility class
class CacheUtil {
  static final Map<String, String> productNameCache = {};

  static void cacheProductName(String id, String name) => productNameCache[id] = name;
  static String getProductName(String? id) => id != null ? productNameCache[id] ?? 'Không xác định' : 'Không xác định';
}

// Constants for IMEI handling
const int maxImeiQuantity = 100000;
const int warnImeiQuantity = 10000;
const int batchSize = 1000;
const int displayImeiLimit = 100;

class SaleForm extends StatefulWidget {
  final SupabaseClient tenantClient;
  final String? initialCustomer;
  final String? initialProductId;
  final String? initialProductName;
  final String? initialPrice;
  final String? initialImei;
  final String? initialNote;
  final String? initialSalesman;
  final List<Map<String, dynamic>> ticketItems;
  final int? editIndex;

  const SaleForm({
    super.key,
    required this.tenantClient,
    this.initialCustomer,
    this.initialProductId,
    this.initialProductName,
    this.initialPrice,
    this.initialImei,
    this.initialNote,
    this.initialSalesman,
    this.ticketItems = const [],
    this.editIndex,
  });

  @override
  State<SaleForm> createState() => _SaleFormState();
}

class _SaleFormState extends State<SaleForm> {
  String? customer;
  String? productId;
  String? productName;
  String? imei = '';
  List<String> imeiList = [];
  int quantity = 0;
  String? price;
  String? currency;
  String? note;
  String? salesman;
  List<Map<String, dynamic>> ticketItems = [];
  List<String> customers = [];
  List<String> currencies = [];
  List<String> salesmen = [];
  List<String> imeiSuggestions = [];
  Map<String, String> productMap = {};
  bool isLoading = true;
  String? errorMessage;
  String? imeiError;
  double customerDebt = 0;

  final TextEditingController imeiController = TextEditingController();
  final TextEditingController customerController = TextEditingController();
  final TextEditingController productController = TextEditingController();
  final TextEditingController priceController = TextEditingController();
  final TextEditingController salesmanController = TextEditingController();
  final TextEditingController quantityController = TextEditingController();

  final NumberFormat numberFormat = NumberFormat.decimalPattern('vi_VN');

  @override
  void initState() {
    super.initState();
    customer = widget.initialCustomer;
    productId = widget.initialProductId;
    productName = widget.initialProductName;
    price = widget.initialPrice; // Giá trị ban đầu là số thực (không định dạng)
    imei = widget.initialImei ?? '';
    note = widget.initialNote;
    salesman = widget.initialSalesman;
    currency = 'VND';
    ticketItems = List.from(widget.ticketItems);

    customerController.text = customer ?? '';
    productController.text = productName ?? '';
    // Định dạng giá trị giá hiển thị trong priceController
    priceController.text = price != null ? numberFormat.format(double.parse(price!)) : '';
    imeiController.text = imei ?? '';
    salesmanController.text = salesman ?? '';
    quantityController.text = quantity.toString();

    if (widget.initialImei != null && widget.initialImei!.isNotEmpty) {
      imeiList = widget.initialImei!.split(',').where((e) => e.trim().isNotEmpty).toList();
      quantity = imeiList.length;
      quantityController.text = quantity.toString();
    }

    _fetchInitialData();
  }

  @override
  void dispose() {
    imeiController.dispose();
    customerController.dispose();
    productController.dispose();
    priceController.dispose();
    salesmanController.dispose();
    quantityController.dispose();
    super.dispose();
  }

  Future<void> _fetchInitialData() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final supabase = widget.tenantClient;

      final customerResponse = await supabase.from('customers').select('name');
      final customerList = customerResponse
          .map((e) => e['name'] as String?)
          .whereType<String>()
          .toList()
        ..sort();

      final productResponse = await supabase.from('products_name').select('id, products');
      final productList = productResponse
          .map((e) => {'id': e['id'].toString(), 'name': e['products'] as String})
          .toList()
        ..sort((a, b) => (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase()));

      final currencyResponse = await supabase
          .from('financial_accounts')
          .select('currency')
          .neq('currency', '');
      final uniqueCurrencies = currencyResponse
          .map((e) => e['currency'] as String?)
          .whereType<String>()
          .toSet()
          .toList();

      final salesmanResponse = await supabase.from('sub_accounts').select('username');
      final salesmanList = salesmanResponse
          .map((e) => e['username'] as String?)
          .whereType<String>()
          .toList()
        ..sort();

      if (mounted) {
        setState(() {
          customers = customerList;
          currencies = uniqueCurrencies;
          salesmen = salesmanList;
          currency = uniqueCurrencies.contains('VND') ? 'VND' : uniqueCurrencies.isNotEmpty ? uniqueCurrencies.first : null;
          isLoading = false;

          productMap = {
            for (var product in productList)
              product['id'] as String: product['name'] as String
          };

          for (var product in productList) {
            CacheUtil.cacheProductName(product['id'] as String, product['name'] as String);
          }
        });
      }

      if (customer != null) {
        await _fetchCustomerDebt();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          errorMessage = 'Không thể tải dữ liệu: $e';
          isLoading = false;
        });
      }
    }
  }

  Future<void> _fetchCustomerDebt() async {
    if (customer == null) {
      setState(() {
        customerDebt = 0;
      });
      return;
    }

    try {
      final supabase = widget.tenantClient;
      final response = await supabase
          .from('customers')
          .select('debt_vnd')
          .eq('name', customer!)
          .single();

      final debt = double.tryParse(response['debt_vnd'].toString()) ?? 0;
      setState(() {
        customerDebt = debt < 0 ? -debt : 0;
      });
    } catch (e) {
      setState(() {
        customerDebt = 0;
      });
    }
  }

  Future<void> _fetchAvailableImeis(String query) async {
    if (productId == null || query.isEmpty) {
      setState(() {
        imeiSuggestions = [];
      });
      return;
    }

    try {
      final supabase = widget.tenantClient;
      final response = await supabase
          .from('products')
          .select('imei')
          .eq('product_id', productId!)
          .eq('status', 'Tồn kho')
          .ilike('imei', '%$query%')
          .limit(10);

      final filteredImeis = response
          .map((e) => e['imei'] as String?)
          .whereType<String>()
          .where((imei) => imei.trim().isNotEmpty && !imeiList.contains(imei)) // Lọc bỏ IMEI rỗng
          .toList()
        ..sort();

      if (mounted) {
        setState(() {
          imeiSuggestions = filteredImeis;
        });
      }
    } catch (e) {
      debugPrint('Lỗi khi tải gợi ý IMEI: $e');
      if (mounted) {
        setState(() {
          imeiSuggestions = [];
        });
      }
    }
  }

  Future<String?> _checkInventoryStatus(String input) async {
    if (productId == null) return 'Vui lòng chọn sản phẩm!';
    if (input.trim().isEmpty) return 'IMEI không được để trống!';

    try {
      final supabase = widget.tenantClient;
      final productResponse = await supabase
          .from('products')
          .select('status, product_id')
          .eq('imei', input)
          .eq('product_id', productId!)
          .maybeSingle();

      if (productResponse == null || productResponse['status'] != 'Tồn kho') {
        final product = CacheUtil.getProductName(productId);
        return 'IMEI "$input" không tồn tại, không thuộc sản phẩm "$product", hoặc không ở trạng thái Tồn kho!';
      }
      return null;
    } catch (e) {
      return 'Lỗi khi kiểm tra IMEI "$input": $e';
    }
  }

  Future<List<String>> _fetchImeisForQuantity(int quantity) async {
    if (productId == null || quantity <= 0) return [];

    try {
      final supabase = widget.tenantClient;
      final response = await supabase
          .from('products')
          .select('imei')
          .eq('product_id', productId!)
          .eq('status', 'Tồn kho')
          .limit(quantity);

      final imeiListFromDb = response
          .map((e) => e['imei'] as String?)
          .whereType<String>()
          .where((imei) => imei.trim().isNotEmpty && !imeiList.contains(imei)) // Lọc bỏ IMEI rỗng
          .toList()
        ..sort();

      return imeiListFromDb;
    } catch (e) {
      return [];
    }
  }

  Future<void> _scanQRCode() async {
    try {
      final scannedData = await Navigator.push<String?>(
        context,
        MaterialPageRoute(builder: (context) => const QRCodeScannerScreen()),
      );

      if (scannedData != null && scannedData.trim().isNotEmpty && mounted) {
        setState(() {
          imei = scannedData;
          imeiController.text = scannedData;
        });

        final error = await _checkInventoryStatus(scannedData);
        setState(() {
          imeiError = error;
        });
        if (error == null) {
          if (imeiList.contains(scannedData)) {
            setState(() {
              imeiError = 'IMEI "$scannedData" đã có trong danh sách!';
              imei = '';
              imeiController.text = '';
            });
          } else {
            setState(() {
              imeiList.insert(0, scannedData);
              imei = '';
              imeiController.text = '';
              imeiError = null;
            });
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

  void addCustomerDialog() async {
    String name = '';
    String phone = '';
    String address = '';
    String social = '';
    String note = '';
    String day = '';
    String month = '';
    String? birthdayError;

    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Thêm khách hàng'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  decoration: const InputDecoration(labelText: 'Tên khách hàng'),
                  onChanged: (val) => name = val,
                ),
                TextField(
                  decoration: const InputDecoration(labelText: 'SĐT'),
                  onChanged: (val) => phone = val,
                ),
                TextField(
                  decoration: const InputDecoration(labelText: 'Địa chỉ'),
                  onChanged: (val) => address = val,
                ),
                TextField(
                  decoration: const InputDecoration(labelText: 'Link MXH'),
                  onChanged: (val) => social = val,
                ),
                TextField(
                  decoration: const InputDecoration(labelText: 'Ghi chú'),
                  onChanged: (val) => note = val,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          labelText: 'Ngày sinh (1-31)',
                          hintText: 'VD: 15',
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (val) {
                          day = val;
                          final dayInt = int.tryParse(day);
                          if (dayInt == null || dayInt < 1 || dayInt > 31) {
                            setDialogState(() {
                              birthdayError = 'Ngày phải từ 1 đến 31';
                            });
                          } else {
                            setDialogState(() {
                              birthdayError = null;
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          labelText: 'Tháng sinh (1-12)',
                          hintText: 'VD: 3',
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (val) {
                          month = val;
                          final monthInt = int.tryParse(month);
                          if (monthInt == null || monthInt < 1 || monthInt > 12) {
                            setDialogState(() {
                              birthdayError = 'Tháng phải từ 1 đến 12';
                            });
                          } else {
                            setDialogState(() {
                              birthdayError = null;
                            });
                          }
                        },
                      ),
                    ),
                  ],
                ),
                if (birthdayError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      birthdayError!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
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
              onPressed: () async {
                if (name.isEmpty) {
                  await showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Thông báo'),
                      content: const Text('Tên khách hàng không được để trống!'),
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

                final dayInt = int.tryParse(day);
                final monthInt = int.tryParse(month);
                String? birthday;
                if (dayInt != null && monthInt != null) {
                  if (dayInt < 1 || dayInt > 31 || monthInt < 1 || monthInt > 12) return;
                  birthday = '${dayInt.toString().padLeft(2, '0')}-${monthInt.toString().padLeft(2, '0')}';
                }

                try {
                  await widget.tenantClient.from('customers').insert({
                    'name': name,
                    'phone': phone,
                    'address': address,
                    'social_link': social,
                    'note': note,
                    'debt_vnd': 0,
                    'debt_cny': 0,
                    'debt_usd': 0,
                    if (birthday != null) 'birthday': birthday,
                  });
                  setState(() {
                    customers.add(name);
                    customers.sort();
                    customer = name;
                    customerController.text = name;
                  });
                  await _fetchCustomerDebt();
                  Navigator.pop(context);
                } catch (e) {
                  await showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Thông báo'),
                      content: Text('Lỗi khi thêm khách hàng: $e'),
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
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Hủy'),
          ),
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
              try {
                final response = await widget.tenantClient
                    .from('products_name')
                    .insert({'products': name})
                    .select('id, products')
                    .single();
                setState(() {
                  final id = response['id'].toString();
                  productMap[id] = name;
                  productId = id;
                  productName = name;
                  productController.text = name;
                  imei = '';
                  imeiController.text = '';
                  imeiError = null;
                  imeiList = [];
                  quantity = 0;
                  quantityController.text = '0';
                });
                CacheUtil.cacheProductName(response['id'].toString(), name);
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

  void addToTicket(BuildContext scaffoldContext) async {
    if (customer == null ||
        productId == null ||
        price == null ||
        currency == null ||
        salesman == null) {
      await showDialog(
        context: scaffoldContext,
        builder: (context) => AlertDialog(
          title: const Text('Thông báo'),
          content: const Text('Vui lòng điền đầy đủ thông tin!'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
      return;
    }

    if (imeiList.isEmpty && quantity == 0) {
      await showDialog(
        context: scaffoldContext,
        builder: (context) => AlertDialog(
          title: const Text('Thông báo'),
          content: const Text('Vui lòng nhập ít nhất một IMEI hoặc chọn số lượng lớn hơn 0!'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
      return;
    }

    if (imeiList.length > maxImeiQuantity) {
      await showDialog(
        context: scaffoldContext,
        builder: (context) => AlertDialog(
          title: const Text('Thông báo'),
          content: Text('Số lượng IMEI (${formatNumberLocal(imeiList.length)}) vượt quá giới hạn cho phép (${formatNumberLocal(maxImeiQuantity)}).\nVui lòng chia thành nhiều phiếu nhỏ hơn.'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
      return;
    }

    // Lấy giá trị từ biến price (đã được lưu dạng số thực)
    final amount = double.tryParse(price!) ?? 0;
    final item = {
      'product_id': productId!,
      'product_name': productName!,
      'imei': imeiList.join(','),
      'price': amount, // Lưu giá trị số thực, không định dạng
      'currency': currency!,
      'note': note,
    };

    setState(() {
      if (widget.editIndex != null) {
        ticketItems[widget.editIndex!] = item;
      } else {
        ticketItems.add(item);
      }
    });

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => SaleSummary(
          tenantClient: widget.tenantClient,
          customer: customer!,
          ticketItems: ticketItems,
          salesman: salesman!,
          currency: currency!,
        ),
      ),
    );
  }

  String formatNumberLocal(num value) {
    return NumberFormat('#,###', 'vi_VN').format(value).replaceAll(',', '.');
  }

  Widget wrapField(Widget child, {bool isImeiField = false, bool isCustomerField = false, bool isImeiList = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      margin: const EdgeInsets.symmetric(vertical: 4),
      height: isImeiField ? 48 : isImeiList ? 120 : isCustomerField ? 56 : 48,
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

    final amount = double.tryParse(price ?? '0') ?? 0;
    final totalAmount = amount * imeiList.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Phiếu bán hàng', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: Transform.rotate(
            angle: math.pi,
            child: const Icon(Icons.arrow_forward_ios, color: Colors.white),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.arrow_forward_ios, color: Colors.white),
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (context) => SaleSummary(
                    tenantClient: widget.tenantClient,
                    customer: customer ?? '',
                    ticketItems: ticketItems,
                    salesman: salesman ?? '',
                    currency: currency ?? 'VND',
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            wrapField(
              Autocomplete<String>(
                optionsBuilder: (TextEditingValue textEditingValue) {
                  final query = textEditingValue.text.toLowerCase();
                  if (query.isEmpty) return salesmen.take(10).toList();
                  final filtered = salesmen
                      .where((option) => option.toLowerCase().contains(query))
                      .toList()
                    ..sort((a, b) {
                      final aLower = a.toLowerCase();
                      final bLower = b.toLowerCase();
                      final aStartsWith = aLower.startsWith(query);
                      final bStartsWith = bLower.startsWith(query);
                      if (aStartsWith != bStartsWith) {
                        return aStartsWith ? -1 : 1;
                      }
                      return aLower.compareTo(bLower);
                    });
                  return filtered.isNotEmpty ? filtered.take(10).toList() : ['Không tìm thấy nhân viên'];
                },
                onSelected: (String selection) {
                  if (selection == 'Không tìm thấy nhân viên') return;
                  setState(() {
                    salesman = selection;
                    salesmanController.text = selection;
                  });
                },
                fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                  controller.text = salesmanController.text;
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    onChanged: (value) {
                      setState(() {
                        salesmanController.text = value;
                        if (value.isEmpty) {
                          salesman = null;
                        }
                      });
                    },
                    decoration: const InputDecoration(
                      labelText: 'Nhân viên bán',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 0),
                      floatingLabelBehavior: FloatingLabelBehavior.auto,
                      labelStyle: TextStyle(fontSize: 14),
                    ),
                  );
                },
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: wrapField(
                    Autocomplete<String>(
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        final query = textEditingValue.text.toLowerCase();
                        if (query.isEmpty) return customers.take(10).toList();
                        final filtered = customers
                            .where((option) => option.toLowerCase().contains(query))
                            .toList()
                          ..sort((a, b) {
                            final aLower = a.toLowerCase();
                            final bLower = b.toLowerCase();
                            final aStartsWith = aLower.startsWith(query);
                            final bStartsWith = bLower.startsWith(query);
                            if (aStartsWith != bStartsWith) {
                              return aStartsWith ? -1 : 1;
                            }
                            return aLower.compareTo(bLower);
                          });
                        return filtered.isNotEmpty ? filtered.take(10).toList() : ['Không tìm thấy khách hàng'];
                      },
                      onSelected: (String selection) {
                        if (selection == 'Không tìm thấy khách hàng') return;
                        setState(() {
                          customer = selection;
                          customerController.text = selection;
                        });
                        _fetchCustomerDebt();
                      },
                      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                        controller.text = customerController.text;
                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
                          onChanged: (value) {
                            setState(() {
                              customerController.text = value;
                              if (value.isEmpty) {
                                customer = null;
                                customerDebt = 0;
                              }
                            });
                          },
                          decoration: const InputDecoration(
                            labelText: 'Khách hàng',
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 0),
                            floatingLabelBehavior: FloatingLabelBehavior.auto,
                            labelStyle: TextStyle(fontSize: 14),
                          ),
                        );
                      },
                    ),
                    isCustomerField: true,
                  ),
                ),
                IconButton(
                  onPressed: addCustomerDialog,
                  icon: const Icon(Icons.add_circle_outline),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            if (customerDebt > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Khách hàng đang dư ${formatNumberLocal(customerDebt)} VND',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: wrapField(
                    Autocomplete<String>(
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        final query = textEditingValue.text.toLowerCase();
                        if (query.isEmpty) {
                          return productMap.values.take(10).toList();
                        }
                        final filtered = productMap.entries
                            .where((entry) => entry.value.toLowerCase().contains(query))
                            .map((entry) => entry.value)
                            .toList()
                          ..sort((a, b) {
                            final aLower = a.toLowerCase();
                            final bLower = b.toLowerCase();
                            final aStartsWith = aLower.startsWith(query);
                            final bStartsWith = bLower.startsWith(query);
                            if (aStartsWith != bStartsWith) {
                              return aStartsWith ? -1 : 1;
                            }
                            final aIndex = aLower.indexOf(query);
                            final bIndex = bLower.indexOf(query);
                            if (aIndex != bIndex) {
                              return aIndex - bIndex;
                            }
                            return aLower.compareTo(bLower);
                          });
                        return filtered.isNotEmpty ? filtered.take(10).toList() : ['Không tìm thấy sản phẩm'];
                      },
                      onSelected: (String selection) {
                        if (selection == 'Không tìm thấy sản phẩm') return;
                        
                        final selectedEntry = productMap.entries.firstWhere(
                          (entry) => entry.value == selection,
                          orElse: () => MapEntry('', ''),
                        );
                        
                        if (selectedEntry.key.isNotEmpty) {
                          setState(() {
                            productId = selectedEntry.key;
                            productName = selection;
                            productController.text = selection;
                            imei = '';
                            imeiController.text = '';
                            imeiError = null;
                            imeiList = [];
                            quantity = 0;
                            quantityController.text = '0';
                          });
                          _fetchAvailableImeis('');
                        }
                      },
                      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                        controller.text = productController.text;
                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
                          onChanged: (value) {
                            setState(() {
                              productController.text = value;
                              if (value.isEmpty) {
                                productId = null;
                                productName = null;
                                imei = '';
                                imeiController.text = '';
                                imeiError = null;
                                imeiList = [];
                                quantity = 0;
                                quantityController.text = '0';
                              }
                            });
                          },
                          decoration: const InputDecoration(
                            labelText: 'Sản phẩm',
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 0),
                            floatingLabelBehavior: FloatingLabelBehavior.auto,
                            labelStyle: TextStyle(fontSize: 14),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                IconButton(
                  onPressed: addProductDialog,
                  icon: const Icon(Icons.add_circle_outline),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            wrapField(
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Autocomplete<String>(
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        final query = textEditingValue.text.toLowerCase();
                        if (productId == null) return ['Vui lòng chọn sản phẩm'];
                        if (query.isEmpty) return imeiSuggestions.take(10).toList();
                        final filtered = imeiSuggestions
                            .where((option) => option.toLowerCase().contains(query))
                            .toList()
                          ..sort((a, b) {
                            final aLower = a.toLowerCase();
                            final bLower = b.toLowerCase();
                            final aStartsWith = aLower.startsWith(query);
                            final bStartsWith = bLower.startsWith(query);
                            if (aStartsWith != bStartsWith) {
                              return aStartsWith ? -1 : 1;
                            }
                            return aLower.compareTo(bLower);
                          });
                        return filtered.isNotEmpty ? filtered.take(10).toList() : ['Không tìm thấy IMEI'];
                      },
                      onSelected: (String selection) async {
                        if (selection == 'Vui lòng chọn sản phẩm' || selection == 'Không tìm thấy IMEI') {
                          return;
                        }
                        
                        if (selection.trim().isEmpty) {
                          setState(() {
                            imeiError = 'IMEI không được để trống!';
                          });
                          return;
                        }

                        if (imeiList.contains(selection)) {
                          setState(() {
                            imeiError = 'IMEI "$selection" đã được nhập!';
                          });
                          return;
                        }

                        final inventoryError = await _checkInventoryStatus(selection);
                        if (inventoryError != null) {
                          setState(() {
                            imeiError = inventoryError;
                          });
                          return;
                        }

                        setState(() {
                          imeiList.add(selection);
                          imei = '';
                          imeiController.text = '';
                          imeiError = null;
                          quantity = imeiList.length;
                          quantityController.text = quantity.toString();
                        });
                        _fetchAvailableImeis('');
                      },
                      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                        controller.text = imeiController.text;
                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
                          enabled: productId != null,
                          onChanged: (value) {
                            setState(() {
                              imei = value;
                              imeiController.text = value;
                              imeiError = null;
                            });
                            _fetchAvailableImeis(value);
                          },
                          onSubmitted: (value) async {
                            if (value.isEmpty) return;

                            if (value.trim().isEmpty) {
                              setState(() {
                                imeiError = 'IMEI không được để trống!';
                              });
                              return;
                            }

                            if (imeiList.contains(value)) {
                              setState(() {
                                imeiError = 'IMEI "$value" đã được nhập!';
                              });
                              return;
                            }

                            final inventoryError = await _checkInventoryStatus(value);
                            if (inventoryError != null) {
                              setState(() {
                                imeiError = inventoryError;
                              });
                              return;
                            }

                            setState(() {
                              imeiList.add(value);
                              imei = '';
                              imeiController.text = '';
                              imeiError = null;
                              quantity = imeiList.length;
                              quantityController.text = quantity.toString();
                            });
                            _fetchAvailableImeis('');
                          },
                          decoration: InputDecoration(
                            labelText: 'IMEI',
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 0),
                            floatingLabelBehavior: FloatingLabelBehavior.auto,
                            labelStyle: const TextStyle(fontSize: 14),
                            errorText: imeiError,
                            hintText: productId == null ? 'Chọn sản phẩm trước' : null,
                          ),
                        );
                      },
                    ),
                  ),
                  IconButton(
                    onPressed: _scanQRCode,
                    icon: const Icon(Icons.qr_code_scanner),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              isImeiField: true,
            ),
            wrapField(
              SizedBox(
                height: 120,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Danh sách IMEI. Đã nhập ${formatNumberLocal(imeiList.length)} chiếc.',
                      style: const TextStyle(fontSize: 14, color: Colors.black54),
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: imeiList.isEmpty
                          ? const Center(
                              child: Text(
                                'Chưa có IMEI nào',
                                style: TextStyle(fontSize: 14, color: Colors.grey),
                              ),
                            )
                          : ListView.builder(
                              itemCount: math.min(imeiList.length, displayImeiLimit),
                              itemBuilder: (context, index) {
                                return Card(
                                  margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                                  elevation: 0,
                                  color: Colors.grey.shade300,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Container(
                                    height: 36,
                                    padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 8),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            imeiList[index],
                                            style: const TextStyle(fontSize: 14),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete, color: Colors.red, size: 18),
                                          onPressed: () {
                                            setState(() {
                                              imeiList.removeAt(index);
                                            });
                                          },
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    if (imeiList.length > displayImeiLimit)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '... và ${formatNumberLocal(imeiList.length - displayImeiLimit)} IMEI khác',
                          style: const TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                      ),
                  ],
                ),
              ),
              isImeiList: true,
            ),
            wrapField(
              TextFormField(
                controller: quantityController,
                keyboardType: TextInputType.number,
                enabled: imeiList.isEmpty,
                onChanged: (val) async {
                  final newQuantity = int.tryParse(val) ?? 0;
                  setState(() {
                    quantity = newQuantity;
                  });
                  if (newQuantity > 0) {
                    final fetchedImeis = await _fetchImeisForQuantity(newQuantity);
                    setState(() {
                      imeiList = fetchedImeis;
                    });
                  } else {
                    setState(() {
                      imeiList = [];
                    });
                  }
                },
                decoration: const InputDecoration(
                  labelText: 'Số lượng (tự động lấy IMEI nếu có)',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 0),
                  floatingLabelBehavior: FloatingLabelBehavior.auto,
                  labelStyle: TextStyle(fontSize: 14),
                ),
              ),
            ),
            wrapField(
              TextFormField(
                controller: priceController,
                keyboardType: TextInputType.number,
                onChanged: (val) {
                  final cleanedValue = val.replaceAll(RegExp(r'[^0-9]'), '');
                  if (cleanedValue.isNotEmpty) {
                    final parsedValue = double.tryParse(cleanedValue);
                    if (parsedValue != null) {
                      final formattedValue = numberFormat.format(parsedValue);
                      priceController.value = TextEditingValue(
                        text: formattedValue,
                        selection: TextSelection.collapsed(offset: formattedValue.length),
                      );
                      setState(() {
                        price = cleanedValue; // Lưu giá trị số thực
                      });
                    }
                  } else {
                    setState(() {
                      price = null;
                    });
                  }
                },
                decoration: const InputDecoration(
                  labelText: 'Số tiền',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 0),
                  floatingLabelBehavior: FloatingLabelBehavior.auto,
                  labelStyle: TextStyle(fontSize: 14),
                ),
              ),
            ),
            wrapField(
              DropdownButtonFormField<String>(
                value: currency,
                items: currencies.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                hint: const Text('Đơn vị tiền'),
                onChanged: (val) => setState(() {
                  currency = val;
                }),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 0),
                  floatingLabelBehavior: FloatingLabelBehavior.auto,
                  labelStyle: TextStyle(fontSize: 14),
                ),
              ),
            ),
            wrapField(
              TextFormField(
                onChanged: (val) => setState(() => note = val),
                decoration: const InputDecoration(
                  labelText: 'Ghi chú',
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 0),
                  floatingLabelBehavior: FloatingLabelBehavior.auto,
                  labelStyle: TextStyle(fontSize: 14),
                ),
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
              onPressed: () => addToTicket(context),
              child: Text(widget.editIndex != null ? 'Cập Nhật Sản Phẩm' : 'Thêm Vào Phiếu'),
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
            child: const Center(
              child: Text(
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