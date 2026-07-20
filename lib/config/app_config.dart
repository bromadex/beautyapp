class AppConfig {
  // Platform takes 10%, provider gets 90%
  static const double platformFeePercent = 0.10;

  static double calculatePlatformFee(double amount) =>
      double.parse((amount * platformFeePercent).toStringAsFixed(2));

  static double calculateProviderEarnings(double amount) =>
      double.parse((amount * (1 - platformFeePercent)).toStringAsFixed(2));
}