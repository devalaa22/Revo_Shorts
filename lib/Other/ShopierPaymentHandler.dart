import 'package:dio/dio.dart';
import 'package:dramix/services/ApiEndpoints.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:dramix/services/api_service.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class ShopierPaymentHandler extends StatefulWidget {
  final int userId;
  final String userEmail;
  final int currentCoins;

  const ShopierPaymentHandler({
    super.key,
    required this.userId,
    required this.userEmail,
    required this.currentCoins,
  });

  @override
  State<ShopierPaymentHandler> createState() => _ShopierPaymentHandlerState();
}

class _ShopierPaymentHandlerState extends State<ShopierPaymentHandler> {
  List<dynamic> packages = [];
  bool isLoading = true;
  int _userCoins = 0;
  int _selectedIndex = -1;
  late final WebViewController _controller;
  bool _isWebViewLoading = false;
  bool _paymentCompleted = false;
  String _countryCode = 'US';
  String _currencyCode = 'USD';
  double _exchangeRate = 1.0;
  bool _locationPermissionGranted = false;
  bool _isConvertingCurrency = false;
  bool _isLocationDetermined = false;

  @override
  void initState() {
    super.initState();
    _userCoins = widget.currentCoins;
    _initializeWebViewController();
    _initLocationAndCurrency();
    _fetchPackages();
    _loadUserCoins();
  }

  void _initializeWebViewController() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _isWebViewLoading = true),
          onPageFinished: (_) => setState(() => _isWebViewLoading = false),
          onNavigationRequest: (request) {
            if (request.url.contains('success')) {
              _handlePaymentSuccess();
              return NavigationDecision.prevent;
            } else if (request.url.contains('fail')) {
              _handlePaymentFailure();
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );
  }

  Future<void> _initLocationAndCurrency() async {
    await _requestLocationPermission();
    if (_locationPermissionGranted) {
      await _determineUserLocation();
      await _fetchExchangeRate();
    }
    setState(() => _isLocationDetermined = true);
  }

  Future<void> _requestLocationPermission() async {
    final status = await Permission.location.status;
    if (status.isDenied) {
      final result = await Permission.location.request();
      setState(() => _locationPermissionGranted = result.isGranted);
    } else if (status.isGranted) {
      setState(() => _locationPermissionGranted = true);
    }
  }

  Future<void> _determineUserLocation() async {
    try {
      if (!_locationPermissionGranted) return;

      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );

      await _getCountryCodeFromAPI(position.latitude, position.longitude);
    } catch (e) {
      debugPrint('Error getting location: $e');
    }
  }

  Future<void> _getCountryCodeFromAPI(double lat, double lng) async {
    try {
      final response = await Dio().get(
        'https://api.bigdatacloud.net/data/reverse-geocode-client',
        queryParameters: {
          'latitude': lat,
          'longitude': lng,
          'localityLanguage': 'en',
        },
        options: Options(receiveTimeout: const Duration(seconds: 5)),
      );

      if (response.statusCode == 200) {
        setState(() {
          _countryCode = response.data['countryCode'] ?? 'US';
          _currencyCode = _getCurrencyCode(_countryCode);
        });
      }
    } catch (e) {
      debugPrint('Error getting country code: $e');
    }
  }

  String _getCurrencyCode(String countryCode) {
    const countryToCurrency = {
      'US': 'USD',
      'EG': 'EGP',
      'SA': 'SAR',
      'AE': 'AED',
      'KW': 'KWD',
      'QA': 'QAR',
      'OM': 'OMR',
      'BH': 'BHD',
      'JO': 'JOD',
      'LB': 'LBP',
      'SY': 'SYP',
      'IQ': 'IQD',
      'YE': 'YER',
      'DZ': 'DZD',
      'MA': 'MAD',
      'TN': 'TND',
      'LY': 'LYD',
      'SD': 'SDG',
      'SO': 'SOS',
      'DJ': 'DJF',
      'MR': 'MRU',
      'GB': 'GBP',
      'FR': 'EUR',
      'DE': 'EUR',
      'IT': 'EUR',
      'ES': 'EUR',
      'TR': 'TRY',
      'IN': 'INR',
      'PK': 'PKR',
      'CN': 'CNY',
      'JP': 'JPY',
      'KR': 'KRW',
      'RU': 'RUB',
    };
    return countryToCurrency[countryCode] ?? 'USD';
  }

  // اضف هذه الدالة هنا
  double _getBottomPadding(BuildContext context) {
    return MediaQuery.of(context).padding.bottom;
  }

  Future<void> _fetchExchangeRate() async {
    if (_currencyCode == 'USD') {
      setState(() => _exchangeRate = 1.0);
      return;
    }

    setState(() => _isConvertingCurrency = true);

    try {
      final response = await Dio().get(
        'https://api.exchangerate-api.com/v4/latest/USD',
        options: Options(receiveTimeout: const Duration(seconds: 5)),
      );

      if (response.statusCode == 200) {
        final rates = response.data['rates'];
        if (rates != null && rates[_currencyCode] != null) {
          setState(() {
            _exchangeRate = rates[_currencyCode].toDouble();
            _isConvertingCurrency = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error fetching exchange rate: $e');
      setState(() {
        _exchangeRate = 1.0;
        _isConvertingCurrency = false;
      });
    }
  }

  Future<void> _loadUserCoins() async {
    try {
      final response = await ApiService().getUserCoins();
      if (response['status'] == 'success' && mounted) {
        setState(() => _userCoins = safeParse(response['coins']));
      }
    } catch (_) {}
  }

  int safeParse(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  Future<void> _fetchPackages() async {
    try {
      final response = await Dio().get(
        ApiEndpoints.getCoinPackages,
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

  Future<void> _handlePaymentSuccess() async {
    if (_paymentCompleted) return;
    _paymentCompleted = true;

    _showLoadingDialog('جاري تحديث رصيدك...');

    try {
      final updateResponse = await ApiService().updateUserCoins(
        widget.userId,
        int.parse(packages[_selectedIndex]['coin_amount'].toString()),
      );

      if (mounted) {
        Navigator.pop(context);
        if (updateResponse['status'] == 'success') {
          await _loadUserCoins();
          _showSnackBar('تم شراء النقاط بنجاح');
        } else {
          _showSnackBar('حدث خطأ أثناء تحديث النقاط', isError: true);
        }
        setState(() => _selectedIndex = -1);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showSnackBar('حدث خطأ: ${e.toString()}', isError: true);
        setState(() => _selectedIndex = -1);
      }
    }
  }


  Future<void> _handlePaymentFailure() async {
    if (mounted) {
      setState(() => _selectedIndex = -1);
      _showSnackBar('فشلت عملية الدفع، حاول مرة أخرى', isError: true);
    }
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

  Future<void> _handlePayment(Map<String, dynamic> package, int index) async {
    if (!mounted) return;

    setState(() {
      _selectedIndex = index;
      _paymentCompleted = false;
    });

    try {
      final url = Uri.parse(ApiEndpoints.createPayment);

      // حساب السعر المحول
      final originalPrice = double.parse(package['price'].toString());
      final convertedPrice = originalPrice * _exchangeRate;

      final body = {
        'user_id': widget.userId,
        'user_name': 'Drama Box',
        'user_email': widget.userEmail,
        'amount': convertedPrice.toStringAsFixed(2),
        'original_amount': originalPrice.toStringAsFixed(2),
        'product_name': '${package['coin_amount']} Coin',
        'currency': _currencyCode,
        'exchange_rate': _exchangeRate.toStringAsFixed(6),
      };

      _showLoadingDialog('جاري توجيهك لصفحة الدفع...');
      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(body),
      );

      Navigator.pop(context);

      if (response.statusCode == 200) {
        setState(() => _isWebViewLoading = true);
        await _controller.loadHtmlString(response.body);
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _selectedIndex = -1);
        _showSnackBar('فشل الاتصال بالسيرفر: ${e.toString()}', isError: true);
      }
    }
  }

  String _formatPrice(double price) {
    final convertedPrice = price * _exchangeRate;
    final format = NumberFormat.currency(
      symbol: _getCurrencySymbol(_currencyCode),
      decimalDigits: 2,
    );
    return format.format(convertedPrice);
  }

  String _getCurrencySymbol(String currencyCode) {
    switch (currencyCode) {
      case 'USD':
        return '\$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      case 'JPY':
        return '¥';
      case 'SAR':
        return 'ر.س';
      case 'AED':
        return 'د.إ';
      case 'EGP':
        return 'ج.م';
      case 'KWD':
        return 'د.ك';
      case 'QAR':
        return 'ر.ق';
      case 'OMR':
        return 'ر.ع.';
      case 'BHD':
        return 'د.ب';
      case 'JOD':
        return 'د.ا';
      case 'LBP':
        return 'ل.ل';
      case 'TRY':
        return '₺';
      default:
        return currencyCode;
    }
  }

  Widget _buildLoadingIndicator() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: Color(0xFFFF078F)),
          const SizedBox(height: 20),
          Text(
            _isConvertingCurrency
                ? 'جاري تحويل العملة...'
                : 'جاري تحميل الباقات...',
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildBalanceCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4A00E0), Color(0xFF8E2DE2)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            spreadRadius: 2,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'مرحباً, ${widget.userEmail.split('@').first}',
                style: const TextStyle(color: Colors.white70),
              ),
              const Text(
                'رصيدك الحالي',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          Row(
            children: [
              Image.asset('assets/coin.png', width: 24),
              const SizedBox(width: 8),
              Text(
                _userCoins.toString(),
                style: const TextStyle(
                  color: Color(0xFFFFD700),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLocationWarning() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_off, color: Colors.blue, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'لم يتم السماح بالوصول إلى الموقع. سيتم عرض الأسعار بالدولار الأمريكي.',
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPackageItem(
    BuildContext context,
    Map<String, dynamic> package,
    int index,
  ) {
    final originalPrice = double.parse(package['price'].toString());
    final convertedPrice = _formatPrice(originalPrice);
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
                          '${package['coin_amount']} نقطة',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isSmallDevice ? 12 : 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Image.asset(
                        'assets/coin.png',
                        width: isSmallDevice ? 40 : 50,
                        height: isSmallDevice ? 40 : 50,
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      Text(
                        convertedPrice,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isSmallDevice ? 18 : 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (_currencyCode != 'USD')
                        Text(
                          '\$${originalPrice.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: isSmallDevice ? 10 : 12,
                            decoration: TextDecoration.lineThrough,
                          ),
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
                            onPressed: () => _handlePayment(package, index),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isPopular
                                  ? Colors.amber
                                  : Colors.white,
                              foregroundColor: isPopular
                                  ? Colors.black
                                  : Colors.purple[800],
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: EdgeInsets.symmetric(
                                vertical: isSmallDevice ? 10 : 12,
                              ),
                              elevation: 3,
                              minimumSize:
                                  Size.zero, // Important for small devices
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
        title: const Text('شراء النقاط', style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_locationPermissionGranted && _currencyCode != 'USD')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Text(
                    _currencyCode,
                    style: const TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.location_on, color: Colors.pink, size: 18),
                ],
              ),
            ),
        ],
      ),
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: _selectedIndex != -1
            ? Padding(
                padding: EdgeInsets.only(bottom: _getBottomPadding(context)),
                child: Stack(
                  children: [
                    WebViewWidget(controller: _controller),
                    if (_isWebViewLoading)
                      const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFFF078F),
                        ),
                      ),
                  ],
                ),
              )
            : Padding(
                padding: EdgeInsets.only(bottom: bottomPadding),
                child:
                    (!_isLocationDetermined ||
                        isLoading ||
                        _isConvertingCurrency)
                    ? _buildLoadingIndicator()
                    : Column(
                        children: [
                          _buildBalanceCard(),
                          if (!_locationPermissionGranted)
                            _buildLocationWarning(),
                          Expanded(
                            child: GridView.builder(
                              padding: const EdgeInsets.all(8),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: mediaQuery.size.width > 600
                                        ? 3
                                        : 2,
                                    crossAxisSpacing: 8,
                                    mainAxisSpacing: 16,
                                    childAspectRatio: isSmallDevice
                                        ? 0.75
                                        : 0.8,
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
