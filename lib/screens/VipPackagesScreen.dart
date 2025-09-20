import 'dart:async';
import 'package:dio/dio.dart';
import 'package:dramix/services/ApiEndpoints.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dramix/services/api_service.dart';
import 'package:intl/intl.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

class VipPackagesScreen extends StatefulWidget {
  final int userId;
  final String userEmail;
  final bool isVip;
  final String? vipExpiry;

  const VipPackagesScreen({
    super.key,
    required this.userId,
    required this.userEmail,
    required this.isVip,
    this.vipExpiry,
  });

  @override
  State<VipPackagesScreen> createState() => _VipPackagesScreenState();
}

class _VipPackagesScreenState extends State<VipPackagesScreen> {
  List<dynamic> packages = [];
  bool isLoading = true;
  int _selectedIndex = -1;

  // Google Play Billing
  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  late StreamSubscription<List<PurchaseDetails>> _subscription;
  bool _isAvailable = false;
  final Map<String, ProductDetails> _products = {}; // تخزين منتجات Google Play

  @override
  void initState() {
    super.initState();
    _initInAppPurchase();
    _fetchPackages();
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  void _initInAppPurchase() async {
    _isAvailable = await _inAppPurchase.isAvailable();

    if (!_isAvailable) {
      return;
    }

    _subscription = _inAppPurchase.purchaseStream.listen(
      _handlePurchaseUpdate,
      onDone: () => _subscription.cancel(),
      onError: (error) =>
          _showSnackBar('خطأ: ${error.toString()}', isError: true),
    );
  }

  // دالة جديدة: جلب أسعار المنتجات من Google Play
  Future<void> _loadProducts() async {
    if (!_isAvailable || packages.isEmpty) return;

    final productIds = packages
        .map<String>((p) => p['google_play_product_id'].toString())
        .toList();

    final ProductDetailsResponse response = 
        await _inAppPurchase.queryProductDetails(Set<String>.from(productIds));

    if (response.notFoundIDs.isNotEmpty) {
      debugPrint('المنتجات غير موجودة في Google Play: ${response.notFoundIDs}');
    }

    setState(() {
      for (var product in response.productDetails) {
        _products[product.id] = product;
      }
    });
  }

  Future<void> _handlePurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.purchased) {
        await _processPurchase(purchase);
      } else if (purchase.status == PurchaseStatus.error) {
        _showSnackBar(
          'فشلت عملية الدفع: ${purchase.error?.message}',
          isError: true,
        );
      }

      if (purchase.pendingCompletePurchase) {
        await _inAppPurchase.completePurchase(purchase);
      }
    }
    setState(() => _selectedIndex = -1);
  }

  Future<void> _processPurchase(PurchaseDetails purchase) async {
    try {
      _showLoadingDialog('جاري معالجة عملية الشراء...');

      final packageIndex = packages.indexWhere(
        (p) => p['google_play_product_id'] == purchase.productID,
      );

      if (packageIndex != -1) {
        final package = packages[packageIndex];

        final updateResponse = await ApiService().updateVipStatus(
          widget.userId,
          int.parse(package['duration'].toString()),
          int.parse(package['id'].toString()),
        );

        if (mounted) {
          Navigator.pop(context);
          if (updateResponse['status'] == 'success') {
            _showSnackBar('تم تفعيل الاشتراك VIP بنجاح! 🎉');
            Navigator.pop(context, {
              'success': true,
              'isVip': true,
              'vipExpiry': updateResponse['vip_expiry'],
              'packageName': package['name'],
            });
          } else {
            _showSnackBar('حدث خطأ أثناء تفعيل الاشتراك', isError: true);
          }
        }
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showSnackBar('خطأ في معالجة الشراء', isError: true);
    }
  }

  Future<void> _fetchPackages() async {
    try {
      final response = await Dio().get(
        ApiEndpoints.getVipPackages,
        options: Options(
          headers: {'Accept': 'application/json'},
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      if (response.statusCode == 200 &&
          response.data['success'] == true &&
          mounted) {
        setState(() {
          packages = response.data['data'];
          isLoading = false;
        });
        await _loadProducts(); // جلب الأسعار بعد تحميل الباقات
      }
    } catch (_) {
      if (mounted) {
        setState(() => isLoading = false);
        _showSnackBar('فشل تحميل الباقات', isError: true);
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textAlign: TextAlign.center),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(20),
      ),
    );
  }

  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.black87,
        content: Row(
          children: [
            const CircularProgressIndicator(color: Color(0xFFFF078F)),
            const SizedBox(width: 16),
            Expanded(
              child: Text(message, style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handlePayment(String productId, int index) async {
    if (!mounted || !_isAvailable) return;

    setState(() {
      _selectedIndex = index;
    });

    try {
      final product = _products[productId];
      if (product == null) {
        throw Exception('المنتج غير متوفر');
      }

      final PurchaseParam purchaseParam = PurchaseParam(
        productDetails: product,
      );

      await _inAppPurchase.buyConsumable(purchaseParam: purchaseParam);
    } catch (e) {
      if (mounted) {
        setState(() => _selectedIndex = -1);
        _showSnackBar('فشل عملية الدفع: ${e.toString()}', isError: true);
      }
    }
  }

  String _formatDate(String date) {
    try {
      final parsedDate = DateTime.parse(date);
      return DateFormat('yyyy-MM-dd').format(parsedDate);
    } catch (e) {
      return date;
    }
  }

  Widget _buildLoadingIndicator() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Color(0xFFFF078F)),
          const SizedBox(height: 20),
          const Text(
            'جاري تحميل الباقات...',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
        ],
      ),
    );
  }

Widget _buildVipStatusBanner() {
  return Container(
    padding: const EdgeInsets.all(12),
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [
          Colors.green.withOpacity(0.3),
          Colors.green.withOpacity(0.1),
        ],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.green),
    ),
    child: Row(
      children: [
        const Icon(Icons.verified, color: Colors.green, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'اشتراك VIP مفعل',
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'ينتهي في ${_formatDate(widget.vipExpiry ?? '')}',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
        ),
        const Icon(Icons.star, color: Colors.amber, size: 24),
      ],
    ),
  );
}


  Widget _buildPackageItem(
    BuildContext context,
    Map<String, dynamic> package,
    int index,
  ) {
    final productId = package['google_play_product_id'].toString();
    final product = _products[productId]; // المنتج من Google Play
    final isPopular = index == 1;
    final isSmallDevice = MediaQuery.of(context).size.width < 360;

    return Card(
      margin: const EdgeInsets.all(8),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: isPopular
                ? [const Color(0xFFFF416C), const Color(0xFFFF4B2B)]
                : [const Color(0xFF4A00E0), const Color(0xFF8E2DE2)],
          ),
        ),
        child: Stack(
          children: [
            if (isPopular)
              Positioned(
                top: 10,
                right: -30,
                child: Transform.rotate(
                  angle: 0.5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 5,
                    ),
                    color: Colors.amber,
                    child: Text(
                      'الأكثر مبيعاً',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: isSmallDevice ? 10 : 12,
                      ),
                    ),
                  ),
                ),
              ),
            Padding(
              padding: EdgeInsets.all(isSmallDevice ? 10 : 14),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          '${package['duration']} يوم',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isSmallDevice ? 12 : 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        package['name'],
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isSmallDevice ? 14 : 16,
                          fontWeight: FontWeight.bold,
                          height: 1.2,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      if (product != null)
                        Text(
                          product.price, // ← السعر直接从جوجل
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isSmallDevice ? 18 : 22,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      else
                        const CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                    ],
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: _selectedIndex == index
                        ? const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          )
                        : ElevatedButton(
                            onPressed: product != null
                                ? () => _handlePayment(productId, index)
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor:
                                  isPopular ? Colors.amber : Colors.white,
                              foregroundColor:
                                  isPopular ? Colors.black : Colors.purple[800],
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: EdgeInsets.symmetric(
                                vertical: isSmallDevice ? 10 : 12,
                              ),
                              elevation: 3,
                              minimumSize: Size.zero,
                            ),
                            child: Text(
                              'اشتري الآن',
                              style: TextStyle(
                                fontSize: isSmallDevice ? 12 : 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final bottomPadding = mediaQuery.padding.bottom;
    final isSmallDevice = mediaQuery.size.width < 360;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('باقات VIP', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomPadding),
          child: isLoading
              ? _buildLoadingIndicator()
              : Column(
                  children: [
                    if (widget.isVip) _buildVipStatusBanner(),
                    if (!_isAvailable)
                      Container(
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.red),
                        ),
                        child: const Text(
                          'متجر التطبيقات غير متاح على جهازك',
                          style: TextStyle(color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    Expanded(
                      child: GridView.builder(
                        padding: const EdgeInsets.all(8),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: mediaQuery.size.width > 600 ? 3 : 2,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 16,
                          childAspectRatio: isSmallDevice ? 0.75 : 0.8,
                        ),
                        itemCount: packages.length,
                        itemBuilder: (context, index) {
                          return _buildPackageItem(
                            context,
                            packages[index],
                            index,
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