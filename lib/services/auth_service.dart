import 'dart:convert';
import 'package:dramix/services/ApiEndpoints.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email'],
    signInOption: SignInOption.standard,
    serverClientId:
        "307918412670-tb11fjtom4di7ar9p28h42tqp29fghcu.apps.googleusercontent.com",
  );

  Future<Map<String, dynamic>> signInWithGoogle() async {
    try {
      // //final integrityToken = await _loadDeploymentCert();
      // if (integrityToken == null) {
      //throw Exception('فشل التحقق من سلامة التطبيق. لا يمكن تسجيل الدخول.');
      //}
      await _googleSignIn.signOut();

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) throw Exception('User cancelled sign in');

      debugPrint('Google sign in successful: ${googleUser.email}');

      final Map<String, dynamic> userData = {
        'email': googleUser.email,
        'name': googleUser.displayName ?? googleUser.email.split('@')[0],
        'google_id': googleUser.id,
        'photo_url': googleUser.photoUrl ?? '',
      };

      debugPrint('Sending to server: $userData');

      final response = await http
          .post(
            Uri.parse(ApiEndpoints.login),
            headers: {
              'Content-Type': 'application/json; charset=UTF-8',
              'Accept': 'application/json',
            },
            body: jsonEncode(userData),
          )
          .timeout(const Duration(seconds: 30));

      debugPrint('Server response: ${response.statusCode} - ${response.body}');

      if (response.statusCode == 200) {
        final result = jsonDecode(response.body);

        if (result['status'] != 'success') {
          throw Exception(result['message'] ?? 'Login failed');
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', result['token'] ?? '');
        await prefs.setString('uid', result['user']['id'].toString());
        await prefs.setString('email', result['user']['email'] ?? '');
        await prefs.setString('name', result['user']['name'] ?? '');
        await prefs.setString('photo_url', googleUser.photoUrl ?? '');
        await prefs.setInt('coins', result['user']['coins'] ?? 0);

        return {
          'success': true,
          'user': result['user'],
          'photo_url': googleUser.photoUrl,
        };
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Sign in error: $e');
      await _googleSignIn.signOut();

      if (e.toString().contains('ApiException') &&
          e.toString().contains('10')) {
        throw Exception(
          'يبدو أن هناك مشكلة في إعدادات تسجيل الدخول بجوجل. '
          'يرجى التأكد من إضافة بصمة التطبيق في Firebase Console.',
        );
      }

      rethrow;
    }
  }

  Future<bool> isSignedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token') != null && prefs.getString('uid') != null;
  }

  Future<Map<String, dynamic>> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'id': prefs.getString('uid'),
      'email': prefs.getString('email'),
      'name': prefs.getString('name'),
      'photo_url': prefs.getString('photo_url'),
      'coins': prefs.getInt('coins') ?? 0,
    };
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('uid');
    await prefs.remove('email');
    await prefs.remove('name');
    await prefs.remove('photo_url');
    await prefs.remove('coins');
    await _googleSignIn.signOut();
  }
}