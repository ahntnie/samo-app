import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';

// Cache utility class
class CacheUtil {
  static final Map<String, String> productNameCache = {};
  static final Map<String, String> warehouseNameCache = {};

  static void cacheProductName(String id, String name) => productNameCache[id] = name;
  static void cacheWarehouseName(String id, String name) => warehouseNameCache[id] = name;
  static String getProductName(String? id) => id != null ? productNameCache[id] ?? 'Không xác định' : 'Không xác định';
  static String getWarehouseName(String? id) => id != null ? warehouseNameCache[id] ?? 'Không xác định' : 'Không xác định';
}

class OverviewScreen extends StatefulWidget {
  final List<String> permissions;
  final SupabaseClient tenantClient;

  const OverviewScreen({
    super.key,
    required this.permissions,
    required this.tenantClient,
  });

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String _selectedTimeFilter = '7 ngày qua';
  DateTime? _fromDate;
  DateTime? _toDate;
  int? _selectedCategoryId;
  List<Map<String, dynamic>> _categories = [];
  String? _selectedWarehouse = 'Tất cả chi nhánh';
  List<String> _warehouseOptions = ['Tất cả chi nhánh'];

  double revenue = 0;
  double profit = 0;
  double companyValue = 0;
  double totalIncome = 0;
  double totalExpense = 0;
  double totalSupplierDebt = 0;
  double totalCustomerDebt = 0;
  double totalFixerDebt = 0;
  double totalTransporterDebt = 0;
  double totalInventoryCost = 0;
  int soldProductsCount = 0;
  List<Map<String, dynamic>> accounts = [];
  Map<String, Map<String, int>> stockData = {};

  List<FlSpot> revenueSpots = [];
  List<FlSpot> profitSpots = [];
  List<FlSpot> incomeSpots = [];
  List<FlSpot> expenseSpots = [];
  List<String> timeLabels = [];

  String? selectedStatus;
  List<Map<String, dynamic>> productDistribution = [];
  final List<Color> chartColors = [
    Colors.blue,
    Colors.red,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.cyan,
    Colors.yellow,
    Colors.pink,
  ];

  List<String> filters = ['Hôm nay', '7 ngày qua', '30 ngày qua', 'Tùy chọn'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: widget.permissions.contains('view_finance') ? 3 : 2, vsync: this);
    _initCaches().then((_) => fetchAllData());
  }

  Future<void> _initCaches() async {
    try {
      final productResponse = await widget.tenantClient.from('products_name').select('id, products');
      for (var product in productResponse) {
        CacheUtil.cacheProductName(product['id'].toString(), product['products'] as String);
      }

      final warehouseResponse = await widget.tenantClient.from('warehouses').select('id, name');
      List<String> warehouseNames = ['Tất cả chi nhánh'];
      for (var warehouse in warehouseResponse) {
        final id = warehouse['id'].toString();
        final name = warehouse['name'] as String;
        CacheUtil.cacheWarehouseName(id, name);
        warehouseNames.add(name);
      }
      setState(() {
        _warehouseOptions = warehouseNames;
      });
    } catch (e) {
      print('Error initializing caches: $e');
    }
  }

  Future<void> _selectDate(BuildContext context, bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _fromDate = picked;
        } else {
          _toDate = picked;
        }
        fetchAllData();
      });
    }
  }

  Widget _buildTimeFilter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            children: filters.map((f) {
              return ChoiceChip(
                label: Text(f),
                selected: _selectedTimeFilter == f,
                onSelected: (v) {
                  if (v) setState(() => _selectedTimeFilter = f);
                  fetchAllData();
                },
              );
            }).toList(),
          ),
          if (_selectedTimeFilter == 'Tùy chọn')
            Row(
              children: [
                TextButton(
                  onPressed: () => _selectDate(context, true),
                  child: Text(_fromDate != null ? DateFormat('dd/MM/yyyy').format(_fromDate!) : 'Từ ngày'),
                ),
                const Text(' - '),
                TextButton(
                  onPressed: () => _selectDate(context, false),
                  child: Text(_toDate != null ? DateFormat('dd/MM/yyyy').format(_toDate!) : 'Tới ngày'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildWarehouseFilter() {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: DropdownButtonFormField<String>(
          value: _selectedWarehouse,
          hint: const Text('Chi nhánh'),
          icon: const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Icon(Icons.arrow_drop_down),
          ),
          items: _warehouseOptions.map((option) {
            return DropdownMenuItem(
              value: option,
              child: Text(option),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              _selectedWarehouse = value;
            });
            fetchAllData();
            fetchProductDistribution(selectedStatus);
          },
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          isExpanded: true,
        ),
      ),
    );
  }

  Widget _buildCategoryFilter() {
    return Flexible(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: DropdownButtonFormField<int>(
          value: _selectedCategoryId,
          items: [
            const DropdownMenuItem<int>(
              value: null,
              child: Text('Tất cả danh mục'),
            ),
            ..._categories.map((cat) => DropdownMenuItem<int>(
                  value: cat['id'],
                  child: Text(cat['name']),
                )),
          ],
          hint: const Text('Chọn danh mục'),
          onChanged: (val) {
            setState(() {
              _selectedCategoryId = val;
            });
            fetchProductDistribution(selectedStatus);
            fetchAllData();
          },
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
        ),
      ),
    );
  }

  DateTime get startDate {
    final now = DateTime.now();
    if (_selectedTimeFilter == 'Hôm nay') {
      return DateTime(now.year, now.month, now.day, 8);
    } else if (_selectedTimeFilter == '7 ngày qua') {
      return now.subtract(const Duration(days: 6));
    } else if (_selectedTimeFilter == '30 ngày qua') {
      return now.subtract(const Duration(days: 29));
    } else if (_fromDate != null) {
      return _fromDate!;
    }
    return now;
  }

  DateTime get endDate {
    final now = DateTime.now();
    if (_selectedTimeFilter == 'Tùy chọn' && _toDate != null) {
      return _toDate!;
    }
    return now;
  }

  List<DateTime> getTimePoints() {
    List<DateTime> points = [];
    if (_selectedTimeFilter == 'Hôm nay') {
      final today = DateTime.now();
      points = [
        DateTime(today.year, today.month, today.day, 8),
        DateTime(today.year, today.month, today.day, 12),
        DateTime(today.year, today.month, today.day, 14),
        DateTime(today.year, today.month, today.day, 16),
        DateTime(today.year, today.month, today.day, 18),
        DateTime(today.year, today.month, today.day, 24),
      ];
    } else if (_selectedTimeFilter == '7 ngày qua') {
      for (int i = 0; i < 7; i++) {
        points.add(startDate.add(Duration(days: i)));
      }
    } else if (_selectedTimeFilter == '30 ngày qua') {
      for (int i = 0; i < 30; i += 5) {
        points.add(startDate.add(Duration(days: i)));
      }
      points.add(endDate);
    } else if (_selectedTimeFilter == 'Tùy chọn' && _fromDate != null && _toDate != null) {
      final days = _toDate!.difference(_fromDate!).inDays + 1;
      int numPoints = days <= 7 ? days : (days <= 30 ? 6 : 7);
      int interval = (days / numPoints).ceil();
      for (int i = 0; i < days; i += interval) {
        points.add(_fromDate!.add(Duration(days: i)));
      }
      points.add(_toDate!);
    }
    return points;
  }

  Future<void> fetchAllData() async {
    try {
      final categoriesResponse = await widget.tenantClient.from('categories').select('id, name');
      setState(() {
        _categories = List<Map<String, dynamic>>.from(categoriesResponse);
      });

      var productsQuery = widget.tenantClient
          .from('products')
          .select('sale_price, profit, sale_date, status, category_id, cost_price, product_id, warehouse_id')
          .not('sale_date', 'is', null)
          .gte('sale_date', startDate.toIso8601String())
          .lte('sale_date', endDate.toIso8601String());

      if (_selectedCategoryId != null) {
        productsQuery = productsQuery.eq('category_id', _selectedCategoryId!);
      }
      if (_selectedWarehouse != 'Tất cả chi nhánh') {
        final warehouseId = CacheUtil.warehouseNameCache.entries
            .firstWhere((entry) => entry.value == _selectedWarehouse, orElse: () => MapEntry('', ''))
            .key;
        if (warehouseId.isNotEmpty) {
          productsQuery = productsQuery.eq('warehouse_id', warehouseId);
        }
      }

      final products = await productsQuery;

      final categories = Map.fromEntries(
        (categoriesResponse as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map((c) => MapEntry(c['id'] as int, c['name'] as String)),
      );

      final exchangeRateResponse = await widget.tenantClient
          .from('financial_orders')
          .select('rate_vnd_cny, rate_vnd_usd')
          .eq('type', 'exchange')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      double rateVndCny = 1.0;
      double rateVndUsd = 1.0;
      if (exchangeRateResponse != null) {
        rateVndCny = (exchangeRateResponse['rate_vnd_cny'] as num?)?.toDouble() ?? 1.0;
        rateVndUsd = (exchangeRateResponse['rate_vnd_usd'] as num?)?.toDouble() ?? 1.0;
      }

      final financialOrders = await widget.tenantClient
          .from('financial_orders')
          .select('type, amount, created_at, currency')
          .gte('created_at', startDate.toIso8601String())
          .lte('created_at', endDate.toIso8601String());

      final acc = await widget.tenantClient.from('financial_accounts').select();
      setState(() {
        accounts = List<Map<String, dynamic>>.from(acc);
      });

      double totalAccountBalance = 0;
      for (final account in accounts) {
        final balanceRaw = account['balance'];
        final balance = balanceRaw is String ? num.tryParse(balanceRaw)?.toDouble() ?? 0.0 : (balanceRaw as num?)?.toDouble() ?? 0.0;
        final currency = account['currency']?.toString() ?? 'VND';
        if (currency == 'VND') {
          totalAccountBalance += balance;
        } else if (currency == 'CNY') {
          totalAccountBalance += balance * rateVndCny;
        } else if (currency == 'USD') {
          totalAccountBalance += balance * rateVndUsd;
        }
      }

      double totalInventoryCostValue = 0;
      var allProductsQuery = widget.tenantClient.from('products').select('status, cost_price, product_id, category_id, warehouse_id');
      if (_selectedCategoryId != null) {
        allProductsQuery = allProductsQuery.eq('category_id', _selectedCategoryId!);
      }
      if (_selectedWarehouse != 'Tất cả chi nhánh') {
        final warehouseId = CacheUtil.warehouseNameCache.entries
            .firstWhere((entry) => entry.value == _selectedWarehouse, orElse: () => MapEntry('', ''))
            .key;
        if (warehouseId.isNotEmpty) {
          allProductsQuery = allProductsQuery.eq('warehouse_id', warehouseId);
        }
      }
      final allProducts = await allProductsQuery;
      for (final product in allProducts) {
        final status = product['status']?.toString() ?? '';
        if (status == 'Đã bán') continue;
        final costPriceRaw = product['cost_price'];
        final costPrice = costPriceRaw is String ? num.tryParse(costPriceRaw)?.toDouble() ?? 0.0 : (costPriceRaw as num?)?.toDouble() ?? 0.0;
        totalInventoryCostValue += costPrice;
      }

      double totalCustomerDebtValue = 0;
      final customers = await widget.tenantClient.from('customers').select('debt_vnd, debt_cny, debt_usd');
      for (final customer in customers) {
        final debtVnd = (customer['debt_vnd'] as num?)?.toDouble() ?? 0.0;
        final debtCny = (customer['debt_cny'] as num?)?.toDouble() ?? 0.0;
        final debtUsd = (customer['debt_usd'] as num?)?.toDouble() ?? 0.0;
        totalCustomerDebtValue += debtVnd + (debtCny * rateVndCny) + (debtUsd * rateVndUsd);
      }

      double totalSupplierDebtValue = 0;
      final suppliers = await widget.tenantClient.from('suppliers').select('debt_vnd, debt_cny, debt_usd');
      for (final supplier in suppliers) {
        final debtVnd = (supplier['debt_vnd'] as num?)?.toDouble() ?? 0.0;
        final debtCny = (supplier['debt_cny'] as num?)?.toDouble() ?? 0.0;
        final debtUsd = (supplier['debt_usd'] as num?)?.toDouble() ?? 0.0;
        totalSupplierDebtValue += debtVnd + (debtCny * rateVndCny) + (debtUsd * rateVndUsd);
      }

      double totalFixerDebtValue = 0;
      final fixers = await widget.tenantClient.from('fix_units').select('debt_vnd, debt_cny, debt_usd');
      for (final fixer in fixers) {
        final debtVnd = (fixer['debt_vnd'] as num?)?.toDouble() ?? 0.0;
        final debtCny = (fixer['debt_cny'] as num?)?.toDouble() ?? 0.0;
        final debtUsd = (fixer['debt_usd'] as num?)?.toDouble() ?? 0.0;
        totalFixerDebtValue += debtVnd + (debtCny * rateVndCny) + (debtUsd * rateVndUsd);
      }

      double totalTransporterDebtValue = 0;
      final transporters = await widget.tenantClient.from('transporters').select('debt');
      for (final transporter in transporters) {
        final debt = (transporter['debt'] as num?)?.toDouble() ?? 0.0;
        totalTransporterDebtValue += debt;
      }

      final timePoints = getTimePoints();
      timeLabels = timePoints.map((point) {
        if (_selectedTimeFilter == 'Hôm nay') {
          return DateFormat('HH').format(point);
        } else {
          return DateFormat('dd/MM').format(point);
        }
      }).toList();

      Map<int, double> revenueMap = {};
      Map<int, double> profitMap = {};
      Map<int, double> incomeMap = {};
      Map<int, double> expenseMap = {};
      double totalRev = 0;
      double totalProfit = 0;
      double totalInc = 0;
      double totalExp = 0;
      int soldCount = 0;

      for (final product in products) {
        final salePrice = (product['sale_price'] as num?)?.toDouble() ?? 0.0;
        final profitValue = (product['profit'] as num?)?.toDouble() ?? 0.0;
        final saleDate = DateTime.tryParse(product['sale_date']?.toString() ?? '');

        if (saleDate != null) {
          int pointIndex = -1;
          if (_selectedTimeFilter == 'Hôm nay') {
            for (int i = 0; i < timePoints.length - 1; i++) {
              if (saleDate.isAfter(timePoints[i]) && (saleDate.isBefore(timePoints[i + 1]) || saleDate.isAtSameMomentAs(timePoints[i + 1]))) {
                pointIndex = i;
                break;
              }
            }
            if (pointIndex == -1) {
              if (saleDate.isBefore(timePoints[0])) {
                pointIndex = 0;
              } else if (saleDate.isAfter(timePoints.last) || saleDate.isAtSameMomentAs(timePoints.last)) {
                pointIndex = timePoints.length - 1;
              }
            }
          } else {
            for (int i = 0; i < timePoints.length - 1; i++) {
              final nextPoint = i == timePoints.length - 2 ? endDate : timePoints[i + 1];
              if (saleDate.isAfter(timePoints[i]) && (saleDate.isBefore(nextPoint) || saleDate.isAtSameMomentAs(nextPoint))) {
                pointIndex = i;
                break;
              }
            }
            if (pointIndex == -1) {
              if (saleDate.isBefore(timePoints[0])) {
                pointIndex = 0;
              } else if (saleDate.isAfter(timePoints.last) || saleDate.isAtSameMomentAs(timePoints.last)) {
                pointIndex = timePoints.length - 1;
              }
            }
          }

          if (pointIndex != -1) {
            revenueMap[pointIndex] = (revenueMap[pointIndex] ?? 0) + salePrice;
            profitMap[pointIndex] = (profitMap[pointIndex] ?? 0) + profitValue;
          }
          totalRev += salePrice;
          totalProfit += profitValue;
          soldCount += 1;
        }
      }

      for (final transaction in financialOrders) {
        final amountRaw = transaction['amount'];
        final amount = amountRaw is String ? num.tryParse(amountRaw)?.toDouble() ?? 0.0 : (amountRaw as num?)?.toDouble() ?? 0.0;
        final currency = transaction['currency']?.toString() ?? 'VND';
        final dt = DateTime.tryParse(transaction['created_at']?.toString() ?? '');
        final type = transaction['type']?.toString().toLowerCase() ?? '';

        double amountInVnd = amount;
        if (currency == 'CNY') {
          amountInVnd = amount * rateVndCny;
        } else if (currency == 'USD') {
          amountInVnd = amount * rateVndUsd;
        }

        if (dt != null) {
          if (type == 'receive') {
            totalInc += amountInVnd;
          } else if (type == 'payment') {
            totalExp += amountInVnd;
          }

          int pointIndex = -1;
          if (_selectedTimeFilter == 'Hôm nay') {
            for (int i = 0; i < timePoints.length - 1; i++) {
              if (dt.isAfter(timePoints[i]) && (dt.isBefore(timePoints[i + 1]) || dt.isAtSameMomentAs(timePoints[i + 1]))) {
                pointIndex = i;
                break;
              }
            }
            if (pointIndex == -1) {
              if (dt.isBefore(timePoints[0])) {
                pointIndex = 0;
              } else if (dt.isAfter(timePoints.last) || dt.isAtSameMomentAs(timePoints.last)) pointIndex = timePoints.length - 1;
            }
          } else {
            for (int i = 0; i < timePoints.length - 1; i++) {
              final nextPoint = i == timePoints.length - 2 ? endDate : timePoints[i + 1];
              if (dt.isAfter(timePoints[i]) && (dt.isBefore(nextPoint) || dt.isAtSameMomentAs(nextPoint))) {
                pointIndex = i;
                break;
              }
            }
            if (pointIndex == -1) {
              if (dt.isBefore(timePoints[0])) {
                pointIndex = 0;
              } else if (dt.isAfter(timePoints.last) || dt.isAtSameMomentAs(timePoints.last)) pointIndex = timePoints.length - 1;
            }
          }

          if (pointIndex != -1) {
            if (type == 'receive') {
              incomeMap[pointIndex] = (incomeMap[pointIndex] ?? 0) + amountInVnd;
            } else if (type == 'payment') {
              expenseMap[pointIndex] = (expenseMap[pointIndex] ?? 0) + amountInVnd;
            }
          }
        }
      }

      Map<String, Map<String, int>> stock = {};
      for (final p in allProducts) {
        final status = p['status']?.toString() ?? '';
        final categoryId = p['category_id'] as int?;
        if (status.isEmpty || categoryId == null || status == 'Đã bán') continue;

        final categoryName = categories[categoryId] ?? 'Không xác định';
        final categoryShort = categoryName == 'điện thoại' ? 'ĐT' : categoryName == 'phụ kiện' ? 'PK' : categoryName;

        stock[status] ??= {};
        stock[status]![categoryShort] = (stock[status]![categoryShort] ?? 0) + 1;
      }

      setState(() {
        revenue = totalRev;
        profit = totalProfit;
        totalIncome = totalInc;
        totalExpense = totalExp;
        totalSupplierDebt = totalSupplierDebtValue;
        totalCustomerDebt = totalCustomerDebtValue;
        totalFixerDebt = totalFixerDebtValue;
        totalTransporterDebt = totalTransporterDebtValue;
        totalInventoryCost = totalInventoryCostValue;
        soldProductsCount = soldCount;
        stockData = stock;

        revenueSpots = List.generate(timeLabels.length, (i) => FlSpot(i.toDouble(), revenueMap[i] ?? 0));
        profitSpots = List.generate(timeLabels.length, (i) => FlSpot(i.toDouble(), profitMap[i] ?? 0));
        incomeSpots = List.generate(timeLabels.length, (i) => FlSpot(i.toDouble(), incomeMap[i] ?? 0));
        expenseSpots = List.generate(timeLabels.length, (i) => FlSpot(i.toDouble(), expenseMap[i] ?? 0));

        companyValue = totalAccountBalance +
            totalInventoryCost +
            totalCustomerDebt -
            (totalSupplierDebt + totalFixerDebt + totalTransporterDebt);

        if (selectedStatus != null && !stockData.containsKey(selectedStatus)) {
          selectedStatus = null;
        }
      });

      await fetchProductDistribution(selectedStatus);
    } catch (e) {
      print('Error fetching data: $e');
      setState(() {
        revenue = 0;
        profit = 0;
        soldProductsCount = 0;
        companyValue = 0;
      });
    }
  }

  Future<void> fetchProductDistribution(String? status) async {
    try {
      var query = widget.tenantClient
          .from('products')
          .select('product_id, status, category_id, warehouse_id')
          .neq('status', 'Đã bán');

      if (status != null) {
        query = query.eq('status', status);
      }
      if (_selectedCategoryId != null) {
        query = query.eq('category_id', _selectedCategoryId!);
      }
      if (_selectedWarehouse != 'Tất cả chi nhánh') {
        final warehouseId = CacheUtil.warehouseNameCache.entries
            .firstWhere((entry) => entry.value == _selectedWarehouse, orElse: () => MapEntry('', ''))
            .key;
        if (warehouseId.isNotEmpty) {
          query = query.eq('warehouse_id', warehouseId);
        }
      }

      final products = await query;

      Map<String, int> productCounts = {};
      for (final product in products) {
        final productName = CacheUtil.getProductName(product['product_id']?.toString());
        productCounts[productName] = (productCounts[productName] ?? 0) + 1;
      }

      List<MapEntry<String, int>> sortedProducts = productCounts.entries.toList()
        ..sort((a, b) => a.key.compareTo(b.key));

      List<Map<String, dynamic>> distribution = [];
      int index = 0;
      for (var entry in sortedProducts) {
        distribution.add({
          'name': entry.key,
          'count': entry.value,
          'color': chartColors[index % chartColors.length],
        });
        index++;
      }

      setState(() {
        productDistribution = distribution;
      });
    } catch (e) {
      print('Error fetching product distribution: $e');
      setState(() {
        productDistribution = [];
      });
    }
  }

  String formatMoney(num value, {String currency = 'VND'}) {
    if (currency == 'CNY') {
      return NumberFormat('#,###', 'vi_VN').format(value);
    }
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(2)}tr';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(0)}k';
    } else {
      return value.toStringAsFixed(0);
    }
  }

  String formatStock(String status, Map<String, int> categories) {
    final dtCount = categories['ĐT'] ?? 0;
    final pkCount = categories['PK'] ?? 0;
    if (dtCount > 0 && pkCount > 0) {
      return '$dtCount ĐT | $pkCount PK';
    } else if (dtCount > 0) {
      return '$dtCount ĐT';
    } else if (pkCount > 0) {
      return '$pkCount PK';
    }
    return '0';
  }

  Widget _buildHeaderTile(String label, String value, Color color, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          border: Border.all(color: color),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: 16, color: color, fontWeight: FontWeight.bold)),
            Text(value, style: TextStyle(fontSize: 16, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildLineChart(String title, List<FlSpot> spots1, Color color1, {List<FlSpot>? spots2, Color? color2}) {
    if ((spots1.isEmpty || spots1.every((spot) => spot.y == 0)) &&
        (spots2 == null || spots2.isEmpty || spots2.every((spot) => spot.y == 0))) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Center(child: Text('Không có dữ liệu để hiển thị $title', style: const TextStyle(color: Colors.grey))),
      );
    }

    double maxY = spots1.map((e) => e.y).fold(0.0, (a, b) => max(a, b));
    if (spots2 != null) {
      maxY = max(maxY, spots2.map((e) => e.y).fold(0.0, (a, b) => max(a, b)));
    }
    maxY = maxY * 1.5;
    if (maxY == 0) maxY = 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        AspectRatio(
          aspectRatio: 1.6,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: LineChart(
              LineChartData(
                maxY: maxY,
                minY: 0,
                lineBarsData: [
                  LineChartBarData(
                    spots: spots1,
                    isCurved: true,
                    color: color1,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                  ),
                  if (spots2 != null && color2 != null)
                    LineChartBarData(
                      spots: spots2,
                      isCurved: true,
                      color: color2,
                      barWidth: 2,
                      dotData: const FlDotData(show: false),
                    ),
                ],
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: maxY / 5,
                      getTitlesWidget: (val, _) => Text(formatMoney(val), style: const TextStyle(fontSize: 10)),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 1,
                      getTitlesWidget: (val, _) {
                        int idx = val.toInt();
                        if (idx >= 0 && idx < timeLabels.length) {
                          return Text(timeLabels[idx], style: const TextStyle(fontSize: 10));
                        }
                        return const Text('');
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: true),
                gridData: const FlGridData(show: true),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPieChart() {
    if (productDistribution.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Center(child: Text('Không có dữ liệu để hiển thị', style: TextStyle(color: Colors.grey))),
      );
    }

    return Column(
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: PieChart(
            PieChartData(
              sections: productDistribution.asMap().entries.map((entry) {
                final index = entry.key;
                final data = entry.value;
                return PieChartSectionData(
                  value: data['count'].toDouble(),
                  color: data['color'],
                  radius: 80,
                  title: '${data['count']}',
                  titleStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                );
              }).toList(),
              sectionsSpace: 2,
              centerSpaceRadius: 40,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            children: List.generate(
              (productDistribution.length + 1) ~/ 2,
              (index) {
                final leftIndex = index * 2;
                final rightIndex = leftIndex + 1;
                final leftData = productDistribution[leftIndex];
                final rightData = rightIndex < productDistribution.length ? productDistribution[rightIndex] : null;

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            width: 16,
                            height: 16,
                            color: leftData['color'],
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${leftData['name']} : ${leftData['count']}sp',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: rightData != null
                          ? Row(
                              children: [
                                Container(
                                  width: 16,
                                  height: 16,
                                  color: rightData['color'],
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${rightData['name']} : ${rightData['count']}sp',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ],
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBusinessTab() {
    return ListView(
      children: [
        _buildTimeFilter(),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(4),
            ),
            child: DropdownButtonFormField<String>(
              value: _selectedWarehouse,
              hint: const Text('Chi nhánh'),
              items: _warehouseOptions.map((option) {
                return DropdownMenuItem(
                  value: option,
                  child: Text(option),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedWarehouse = value;
                });
                fetchAllData();
              },
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
          ),
        ),
        if (widget.permissions.contains('view_company_value'))
          _buildHeaderTile('Giá trị công ty', '${formatMoney(companyValue)} VND', Colors.purple),
        _buildHeaderTile('Doanh số', '$soldProductsCount sp / ${formatMoney(revenue)} VND', Colors.green),
        if (widget.permissions.contains('view_profit'))
          _buildHeaderTile('Lợi nhuận', '${formatMoney(profit)} VND', Colors.orange),
        _buildLineChart('Doanh số và lợi nhuận theo thời gian', revenueSpots, Colors.green, spots2: profitSpots, color2: Colors.orange),
      ],
    );
  }

  Widget _buildFinanceTab() {
    return ListView(
      children: [
        _buildTimeFilter(),
        ...accounts.map((e) {
          final currency = e['currency']?.toString() ?? 'VND';
          final balance = (e['balance'] is String ? num.tryParse(e['balance'])?.toDouble() : (e['balance'] as num?)?.toDouble()) ?? 0.0;
          return _buildHeaderTile(
            e['name'],
            '${formatMoney(balance, currency: currency)} $currency',
            Colors.blue,
          );
        }),
        _buildHeaderTile('Công nợ nhà cung cấp', '${formatMoney(totalSupplierDebt)} VND', Colors.orange),
        _buildHeaderTile('Công nợ khách hàng', '${formatMoney(totalCustomerDebt)} VND', Colors.orange),
        _buildHeaderTile('Công nợ đơn vị fix lỗi', '${formatMoney(totalFixerDebt)} VND', Colors.orange),
        _buildHeaderTile('Công nợ đơn vị vận chuyển', '${formatMoney(totalTransporterDebt)} VND', Colors.orange),
        _buildHeaderTile('Tổng tiền hàng tồn', '${formatMoney(totalInventoryCost)} VND', Colors.orange),
        _buildHeaderTile('Tổng thu', '${formatMoney(totalIncome)} VND', Colors.green),
        _buildHeaderTile('Tổng chi', '${formatMoney(totalExpense)} VND', Colors.red),
        _buildLineChart('Tổng thu và chi theo thời gian', incomeSpots, Colors.green, spots2: expenseSpots, color2: Colors.red),
      ],
    );
  }

  Widget _buildInventoryTab() {
    List<Widget> stockWidgets = [];
    final statuses = stockData.keys.toList();

    for (final status in statuses) {
      final categories = stockData[status] ?? {};
      stockWidgets.add(
        _buildHeaderTile(
          status,
          formatStock(status, categories),
          Colors.blue,
          onTap: () async {
            setState(() {
              selectedStatus = status;
            });
            await fetchProductDistribution(status);
          },
        ),
      );
    }

    if (stockWidgets.isEmpty) {
      stockWidgets.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 20),
          child: Center(child: Text('Không có dữ liệu hàng hóa', style: TextStyle(color: Colors.grey))),
        ),
      );
    }

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              _buildCategoryFilter(),
              _buildWarehouseFilter(),
            ],
          ),
        ),
        ...stockWidgets,
        _buildPieChart(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: widget.permissions.contains('view_finance') ? 3 : 2,
      child: Scaffold(
        appBar: AppBar(
          iconTheme: const IconThemeData(color: Colors.white),
          title: const Text('Tổng quan', style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.black,
          bottom: TabBar(
            controller: _tabController,
            labelColor: Colors.amber,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.amber,
            tabs: [
              const Tab(text: 'Hiệu quả'),
              const Tab(text: 'Hàng hóa'),
              if (widget.permissions.contains('view_finance')) const Tab(text: 'Tài chính'),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildBusinessTab(),
            _buildInventoryTab(),
            if (widget.permissions.contains('view_finance')) _buildFinanceTab(),
          ],
        ),
      ),
    );
  }
}