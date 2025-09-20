import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:dramix/services/api_service.dart';


class Coinsscreen extends StatefulWidget {
  final int userId;
  final String userEmail;
  final int currentCoins;

  const Coinsscreen({
    super.key,
    required this.userId,
    required this.userEmail,
    required this.currentCoins,
  });

  @override
  _CoinsscreenState createState() => _CoinsscreenState();
}

class _CoinsscreenState extends State<Coinsscreen> {
  List<dynamic> packages = [];
  bool isLoading = true;
  int _userCoins = 0;
  int _selectedIndex = -1;
  
  Null get fff => null;

  @override
  void initState() {
    super.initState();
    _userCoins = widget.currentCoins;
    _fetchPackages();
    _loadUserCoins();
  }

  Future<void> _loadUserCoins() async {
    try {
      final response = await ApiService().getUserCoins();
      if (response['status'] == 'success' && mounted) {
        setState(() => _userCoins = safeParse(response['coins']));
      }
    } catch (e) {
      debugPrint('Error loading coins: $e');
    }
  }

  int safeParse(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  Future<void> _fetchPackages() async {
    try {
      final response = await Dio().get(
        'https://mingleme.site/get_coin_packages.php',
        options: Options(headers: {'Accept': 'application/json'}),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['success'] == true) {
          setState(() {
            packages = data['data'];
            isLoading = false;
          });
          return;
        }
      }
      throw Exception('Failed to load packages');
    } catch (e) {
      setState(() => isLoading = false);
      _showSnackBar('فشل تحميل الباقات، يرجى المحاولة لاحقاً', isError: true);
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

  Future<void> _handlePayment(Map<String, dynamic> package, int index) async {
    try {
      setState(() => _selectedIndex = index);

      final dio = Dio();
      final paymentIntentResponse = await dio.post(
        "https://api.stripe.com/v1/payment_intents",
        options: Options(
          headers: {
            "Authorization": "Bearer $fff",
            "Content-Type": "application/x-www-form-urlencoded",
          },
        ),
        data: {
          "amount": (double.parse(package['price'].toString()) * 100)
              .toInt()
              .toString(),
          "currency": "usd",
          "payment_method_types[]": "card",
        },
      );

      final clientSecret = paymentIntentResponse.data['client_secret'];

      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: 'My App',
        ),
      );

      await Stripe.instance.presentPaymentSheet();

      final updateResponse = await ApiService().updateUserCoins(
        widget.userId,
        int.parse(package['coin_amount'].toString()),
      );

      if (updateResponse['status'] == 'success') {
        _showSnackBar('تم شراء النقاط بنجاح');
        _loadUserCoins();
      } else {
        _showSnackBar('حدث خطأ أثناء تحديث النقاط', isError: true);
      }
    } on StripeException catch (_) {
      _showSnackBar('تم إلغاء عملية الشراء', isError: true);
    } catch (e) {
      _showSnackBar('فشل الدفع: $e', isError: true);
    } finally {
      setState(() => _selectedIndex = -1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        centerTitle: true,
        elevation: 0,
        title: const Text('شراء النقاط', style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    return isLoading
        ? _buildLoadingIndicator()
        : Column(children: [_buildBalanceCard(), _buildPackagesGrid()]);
  }

  Widget _buildLoadingIndicator() {
    return const Center(
      child: CircularProgressIndicator(color: Color(0xFFFF078F)),
    );
  }

  Widget _buildBalanceCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.grey.shade900, Colors.grey.shade800],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF078F).withOpacity(0.1),
            blurRadius: 10,
            spreadRadius: 2,
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
                style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
              ),
              const SizedBox(height: 4),
              const Text(
                'رصيدك الحالي',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          _buildCoinDisplay(),
        ],
      ),
    );
  }

  Widget _buildCoinDisplay() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amber.withOpacity(0.3), width: 1),
      ),
      child: Row(
        children: [
          Image.asset('assets/coin.png', width: 24, height: 24),
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
    );
  }

  Widget _buildPackagesGrid() {
    return Expanded(
      child: SafeArea(
        child: GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            childAspectRatio: 0.8,
          ),
          itemCount: packages.length,
          itemBuilder: (context, index) =>
              _buildPackageCard(packages[index], index),
        ),
      ),
    );
  }

  Widget _buildPackageCard(Map<String, dynamic> package, int index) {
    final isSelected = _selectedIndex == index;
    final price = double.parse(package['price'].toString());
    int.parse(package['coin_amount'].toString());

    return GestureDetector(
      onTap: () => _handlePayment(package, index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        transform: Matrix4.identity()..scale(isSelected ? 0.95 : 1.0),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.grey.shade900, Colors.grey.shade800],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? const Color(0xFFFF078F) : Colors.transparent,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    children: [
                      Text(
                        '${package['coin_amount']}',
                        style: const TextStyle(
                          color: Color(0xFFFF078F),
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text(
                        'نقطة',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ],
                  ),
                  _buildCoinIcon(),
                  Column(
                    children: [
                      Text(
                        '\$$price',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  _buildBuyButton(isSelected),
                ],
              ),
            ),
            if (isSelected) _buildSelectedIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _buildCoinIcon() {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [Colors.amber.shade600, Colors.amber.shade300],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withOpacity(0.3),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Center(
        child: Image.asset('assets/coin.png', width: 50, height: 50),
      ),
    );
  }

  Widget _buildBuyButton(bool isSelected) {
    return isSelected
        ? const CircularProgressIndicator(color: Color(0xFFFF078F))
        : Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            width: double.infinity,
          );
  }

  Widget _buildSelectedIndicator() {
    return Positioned(
      top: 8,
      right: 8,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: const BoxDecoration(
          color: Color(0xFFFF078F),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.check, color: Colors.white, size: 16),
      ),
    );
  }
}
