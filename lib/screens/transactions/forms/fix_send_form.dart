import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:intl/intl.dart';
import 'fix_send_summary.dart';
import 'dart:math' as math;

// Cache utility class
class CacheUtil {
  static final Map<String, String> productNameCache = {};

  static void cacheProductName(dynamic id, dynamic products) {
    if (id != null && products != null) {
      final String productId = id.toString();
      final String productName = products.toString();
      productNameCache[productId] = productName;
    }
  }

  static String getProductName(String? id) {
    return id != null ? productNameCache[id] ?? 'Không xác định' : 'Không xác định';
  }
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

class FixSendForm extends StatefulWidget {
  final SupabaseClient tenantClient;
  final String? initialFixer;
  final String? initialProductId;
  final String? initialImei;
  final String? initialNote;
  final List<Map<String, dynamic>> ticketItems;
  final int? editIndex;

  const FixSendForm({
    super.key,
    required this.tenantClient,
    this.initialFixer,
    this.initialProductId,
    this.initialImei,
    this.initialNote,
    this.ticketItems = const [],
    this.editIndex,
  });

  @override
  State<FixSendForm> createState() => _FixSendFormState();
}

class _FixSendFormState extends State<FixSendForm> {
  String? fixer;
  String? productId;
  String? imei = '';
  List<String> imeiList = [];
  String? note;
  List<Map<String, dynamic>> ticketItems = [];

  List<String> fixers = [];
  List<String> imeiSuggestions = [];
  Map<String, String> productMap = {};
  bool isLoading = true;
  String? errorMessage;
  String? imeiError;

  final TextEditingController imeiController = TextEditingController();
  final TextEditingController productController = TextEditingController();
  final NumberFormat numberFormat = NumberFormat.decimalPattern('vi_VN');

  @override
  void initState() {
    super.initState();
    fixer = widget.initialFixer;
    productId = widget.initialProductId;
    imei = widget.initialImei ?? '';
    note = widget.initialNote;
    ticketItems = List.from(widget.ticketItems);

    imeiController.text = imei ?? '';
    if (widget.initialImei != null && widget.initialImei!.isNotEmpty) {
      imeiList = widget.initialImei!.split(',').where((e) => e.trim().isNotEmpty).toList();
    }

    _fetchInitialData();
  }

  @override
  void dispose() {
    imeiController.dispose();
    productController.dispose();
    super.dispose();
  }

  Future<void> _fetchInitialData() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final supabase = widget.tenantClient;

      final fixerResponse = await retry(
        () => supabase.from('fix_units').select('name'),
        operation: 'Fetch fixers',
      );
      final fixerList = fixerResponse
          .map((e) => e['name'] as String?)
          .whereType<String>()
          .toList()
        ..sort();

      final productResponse = await retry(
        () => supabase.from('products_name').select('id, products'),
        operation: 'Fetch products',
      );
      final productList = productResponse
          .map((e) => {'id': e['id'].toString(), 'name': e['products'] as String})
          .toList()
        ..sort((a, b) => (a['name'] as String).toLowerCase().compareTo((b['name'] as String).toLowerCase()));

      if (mounted) {
        setState(() {
          fixers = fixerList;
          isLoading = false;

          productMap = {
            for (var product in productList)
              product['id'] as String: product['name'] as String
          };

          for (var product in productList) {
            CacheUtil.cacheProductName(product['id'], product['name']);
          }
        });
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
          .where((imei) => !imeiList.contains(imei))
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

  void addFixerDialog() async {
    String name = '';
    String phone = '';
    String address = '';
    String note = '';
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Thêm đơn vị sửa'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: const InputDecoration(labelText: 'Tên đơn vị'),
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
                decoration: const InputDecoration(labelText: 'Ghi chú'),
                onChanged: (val) => note = val,
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
                    content: const Text('Tên đơn vị không được để trống!'),
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
                  () => widget.tenantClient.from('fix_units').insert({
                    'name': name,
                    'phone': phone,
                    'address': address,
                    'note': note,
                    'debt_vnd': 0,
                    'debt_cny': 0,
                    'debt_usd': 0,
                  }),
                  operation: 'Insert fix unit',
                );
                if (mounted) {
                  setState(() {
                    fixers.add(name);
                    fixers.sort();
                    fixer = name;
                  });
                  Navigator.pop(context);
                }
              } catch (e) {
                await showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Thông báo'),
                    content: Text('Lỗi khi thêm đơn vị sửa: $e'),
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

  String? _checkDuplicateImeis(String input) {
    if (imeiList.contains(input.trim())) {
      return 'IMEI "$input" đã được nhập!';
    }
    return null;
  }

  Future<String?> _checkInventoryStatus(String input) async {
    if (productId == null) return 'Vui lòng chọn sản phẩm!';
    if (input.trim().isEmpty) return null;

    try {
      final supabase = widget.tenantClient;
      final productResponse = await retry(
        () => supabase
            .from('products')
            .select('status, product_id')
            .eq('imei', input.trim())
            .eq('product_id', productId!)
            .maybeSingle(),
        operation: 'Check inventory status',
      );

      if (productResponse == null || productResponse['status'] != 'Tồn kho') {
        final productName = CacheUtil.getProductName(productId);
        return 'IMEI "$input" không tồn tại, không thuộc sản phẩm "$productName", hoặc không ở trạng thái Tồn kho!';
      }
      return null;
    } catch (e) {
      return 'Lỗi khi kiểm tra IMEI "$input": $e';
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
          imei = scannedData;
          imeiController.text = scannedData;
        });

        final duplicateError = _checkDuplicateImeis(scannedData);
        if (duplicateError != null) {
          setState(() {
            imeiError = duplicateError;
          });
          return;
        }

        final inventoryError = await _checkInventoryStatus(scannedData);
        setState(() {
          imeiError = inventoryError;
        });
        if (inventoryError == null) {
          setState(() {
            imeiList.add(scannedData);
            imei = '';
            imeiController.text = '';
            imeiError = null;
          });
          _fetchAvailableImeis('');
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

  void addToTicket(BuildContext scaffoldContext) async {
    if (fixer == null || productId == null || imeiList.isEmpty) {
      if (mounted) {
        showDialog(
          context: scaffoldContext,
          builder: (context) => AlertDialog(
            title: const Text('Thông báo'),
            content: const Text('Vui lòng điền đầy đủ thông tin và nhập ít nhất một IMEI!'),
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
        showDialog(
          context: scaffoldContext,
          builder: (context) => AlertDialog(
            title: const Text('Thông báo'),
            content: Text('Số lượng IMEI (${formatNumberLocal(imeiList.length)}) vượt quá giới hạn ${formatNumberLocal(maxImeiQuantity)}. Vui lòng chia thành nhiều phiếu.'),
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

    String? inventoryError;
    for (int i = 0; i < imeiList.length; i += batchSize) {
      final batchImeis = imeiList.sublist(i, math.min(i + batchSize, imeiList.length));
      for (var imei in batchImeis) {
        inventoryError = await _checkInventoryStatus(imei);
        if (inventoryError != null) break;
      }
      if (inventoryError != null) break;
    }

    if (inventoryError != null) {
      if (mounted) {
        showDialog(
          context: scaffoldContext,
          builder: (context) => AlertDialog(
            title: const Text('Thông báo'),
            content: Text(inventoryError ?? 'Lỗi không xác định'),
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

    final item = {
      'fixer': fixer!,
      'product_id': productId!,
      'product_name': CacheUtil.getProductName(productId),
      'imei': imeiList.join(','),
      'quantity': imeiList.length,
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
        builder: (context) => FixSendSummary(
          tenantClient: widget.tenantClient,
          ticketItems: ticketItems,
        ),
      ),
    );
  }

  String formatNumberLocal(num value) {
    return NumberFormat('#,###', 'vi_VN').format(value).replaceAll(',', '.');
  }

  Widget wrapField(Widget child, {bool isImeiField = false, bool isFixerField = false, bool isImeiList = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      margin: const EdgeInsets.symmetric(vertical: 4),
      height: isImeiField ? 48 : isImeiList ? 120 : isFixerField ? 56 : 48,
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

  Widget _buildProductField() {
    return Autocomplete<String>(
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
            productController.text = selection;
            imei = '';
            imeiController.text = '';
            imeiError = null;
            imeiList = [];
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
                imei = '';
                imeiController.text = '';
                imeiError = null;
                imeiList = [];
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
    );
  }

  Widget _buildImeiField() {
    return Row(
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
              
              final error = _checkDuplicateImeis(selection);
              if (error != null) {
                setState(() {
                  imeiError = error;
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

                  final error = _checkDuplicateImeis(value);
                  if (error != null) {
                    setState(() {
                      imeiError = error;
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
        title: const Text('Phiếu gửi sửa', style: TextStyle(color: Colors.white)),
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
            onPressed: ticketItems.isEmpty
                ? null
                : () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (context) => FixSendSummary(
                          tenantClient: widget.tenantClient,
                          ticketItems: ticketItems,
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
            Row(
              children: [
                Expanded(
                  child: wrapField(
                    Autocomplete<String>(
                      optionsBuilder: (TextEditingValue textEditingValue) {
                        final query = textEditingValue.text.toLowerCase();
                        if (query.isEmpty) return fixers.take(10).toList();
                        final filtered = fixers
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
                        return filtered.isNotEmpty ? filtered.take(10).toList() : ['Không tìm thấy đơn vị sửa'];
                      },
                      onSelected: (String selection) {
                        if (selection == 'Không tìm thấy đơn vị sửa') return;
                        setState(() {
                          fixer = selection;
                        });
                      },
                      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
                          onChanged: (value) {
                            setState(() {
                              fixer = value.isNotEmpty ? value : null;
                            });
                          },
                          decoration: const InputDecoration(
                            labelText: 'Đơn vị sửa',
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 8, horizontal: 0),
                            floatingLabelBehavior: FloatingLabelBehavior.auto,
                            labelStyle: TextStyle(fontSize: 14),
                          ),
                        );
                      },
                    ),
                    isFixerField: true,
                  ),
                ),
                IconButton(
                  onPressed: addFixerDialog,
                  icon: const Icon(Icons.add_circle_outline),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            wrapField(
              _buildProductField(),
            ),
            wrapField(
              _buildImeiField(),
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
  _QRCodeScannerScreenState createState() => _QRCodeScannerScreenState();
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
              child: Text(
                'Quét QR code để lấy IMEI',
                style: const TextStyle(fontSize: 18, color: Colors.black),
              ),
            ),
          ),
        ],
      ),
    );
  }
}