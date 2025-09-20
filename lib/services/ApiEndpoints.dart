class ApiEndpoints {
  static const String baseUrl = "https://dramaxbox.bbs.tr/";
  static const String baseUrl2 = "https://revo-shorts.dramaxbox.bbs.tr/";

  static const String bascreatePYEeUrl = "https://dramaxbox.bbs.tr/";
  static const String login = "${baseUrl}auth_api.php";
  static const String updateUserCoins = "${baseUrl}update_user_coins.php";
  static const String delete_user = "${baseUrl}delete_user.php";
  static const String getUserCoins = "${baseUrl}get_user_coins.php";
  static const String unlockEpisodeWithCoins ="${baseUrl}unlock_episode_with_coins.php";
  static const String getCoinPackages = "${baseUrl}get_coin_packages.php";
  static const String createPayment ="${bascreatePYEeUrl}dramabox/createPYE.php";
  static const String checkVipStatus = "${baseUrl}VIP/check_vip_status.php";
  static const String updateVipStatus = "${baseUrl}VIP/update_vip_status.php";
  static const String getVipPackages = "${baseUrl}VIP/get_vip_packages.php";
  static const String getDailyGifts = "${baseUrl}ads/get_Dailygifts.php";
  static const String updateDailyGift = "${baseUrl}ads/update_dailygift.php";
  static const String getAllSeries = "${baseUrl}get_series.php";
  static const String getEpisodesBySeries = "${baseUrl}get_episodes.php";
  static const String getRecommendations = "${baseUrl}get_recommendations.php";
  static const String viewsLikesApi = "${baseUrl}views_likes_api.php";
  static const String getAdMob = "${baseUrl2}ads/get_admob.php";
  static const String getAdWatchData = "${baseUrl}ads/get_ad_watch_data.php";
  static const String updateAdWatchCount ="${baseUrl}ads/update_ad_watch_count.php";
   static const String getGooglePlayProducts = '$baseUrl/google-play-products.php';
  static const String verifyGooglePlayPurchase = '$baseUrl/verify-purchase.php';









}
