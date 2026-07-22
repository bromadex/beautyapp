class AppConfig {
  // BeauTap takes NO commission — providers keep 100% of booking payments.
  // Platform revenue comes from provider subscriptions only:
  //   $3 activation (includes first month) → $5/month after.
  static const double providerActivationFee = 3.00;
  static const double providerMonthlyFee = 5.00;
  static const double clientActivationFee = 1.00;

  static const String webBaseUrl = 'https://beautyapp-swart.vercel.app';
}
