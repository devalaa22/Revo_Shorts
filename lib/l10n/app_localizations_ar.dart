// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'مينغل مي';

  @override
  String get home => 'الرئيسية';

  @override
  String get discover => 'اكتشف';

  @override
  String get favorites => 'المفضلة';

  @override
  String get profile => 'حسابي';

  @override
  String get description => 'عدد الحلقات';

  @override
  String episodesCount(Object count) {
    return '$count حلقات';
  }

  @override
  String get videoSettings => 'إعدادات الفيديو';

  @override
  String get playbackSpeed => 'إعدادات الفيديو';

  @override
  String get rewards => 'المكافآت';

  @override
  String get guestName => 'ضيف';

  @override
  String get guestEmail => 'guest@mingleme.app';

  @override
  String get guestId => 'UID وهمي';

  @override
  String get login => 'تسجيل الدخول';

  @override
  String get watchHistory => 'سجل المشاهدة';

  @override
  String get chargeNow => 'شحن الآن';

  @override
  String get myWallet => 'محفظتي';

  @override
  String get myCoins => '🪙 120';

  @override
  String get rewardsCenter => 'مركز الفوائد';

  @override
  String get language => 'اللغة';

  @override
  String get languageArabic => 'العربية';

  @override
  String get offlineDownload => 'تنزيل خارج الخط';

  @override
  String get gift => 'هدية';

  @override
  String get onlineSupport => 'الدعم عبر الإنترنت';

  @override
  String get settings => 'الإعدادات';

  @override
  String get userIdPrefix => 'ID';
}
