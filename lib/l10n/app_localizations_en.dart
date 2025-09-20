// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Mingle Me';

  @override
  String get home => 'Home';

  @override
  String get discover => 'Discover';

  @override
  String get favorites => 'Favorites';

  @override
  String get profile => 'Profile';

  @override
  String get description => 'Number of episodes';

  @override
  String episodesCount(Object count) {
    return '$count episodes';
  }

  @override
  String get videoSettings => 'Video Settings';

  @override
  String get playbackSpeed => 'Playback Speed';

  @override
  String get rewards => 'Rewards';

  @override
  String get guestName => 'Guest';

  @override
  String get guestEmail => 'guest@mingleme.app';

  @override
  String get guestId => 'Fake UID';

  @override
  String get login => 'Login';

  @override
  String get watchHistory => 'Watch History';

  @override
  String get chargeNow => 'Charge Now';

  @override
  String get myWallet => 'My Wallet';

  @override
  String get myCoins => '🪙 120';

  @override
  String get rewardsCenter => 'Rewards Center';

  @override
  String get language => 'Language';

  @override
  String get languageArabic => 'Arabic';

  @override
  String get offlineDownload => 'Offline Download';

  @override
  String get gift => 'Gift';

  @override
  String get onlineSupport => 'Online Support';

  @override
  String get settings => 'Settings';

  @override
  String get userIdPrefix => 'ID';
}
