import 'package:purchases_flutter/purchases_flutter.dart'
    show
        IntroductoryPrice,
        Offering,
        Offerings,
        Package,
        PackageType,
        PeriodUnit,
        PresentedOfferingContext,
        StoreProduct;

Package proPackage(
  String identifier,
  PackageType type, {
  required double price,
  required String priceString,
  String productId = 'pro_monthly',
  String currencyCode = 'USD',
  IntroductoryPrice? intro,
}) =>
    Package(
      identifier,
      type,
      StoreProduct(productId, 'Pro', 'Pro', price, priceString, currencyCode,
          introductoryPrice: intro),
      const PresentedOfferingContext('default', null, null),
    );

final Package proMonthlyPackage = proPackage(
  r'$rc_monthly',
  PackageType.monthly,
  price: 9.99,
  priceString: r'$9.99',
);

final Package proAnnualPackage = proPackage(
  r'$rc_annual',
  PackageType.annual,
  productId: 'pro_annual',
  price: 79.99,
  priceString: r'$79.99',
);

Offerings proOfferings(List<Package> packages) => Offerings(
      {'default': Offering('default', 'Pro', const {}, packages)},
      current: Offering('default', 'Pro', const {}, packages),
    );

const IntroductoryPrice sevenDayTrial =
    IntroductoryPrice(0, r'$0.00', 'P1W', 1, PeriodUnit.day, 7);

Package proAnnualWithIntro(IntroductoryPrice intro) => proPackage(
      r'$rc_annual',
      PackageType.annual,
      productId: 'pro_annual',
      price: 79.99,
      priceString: r'$79.99',
      intro: intro,
    );

Package proMonthlyWithIntro(IntroductoryPrice intro) => proPackage(
      r'$rc_monthly',
      PackageType.monthly,
      price: 9.99,
      priceString: r'$9.99',
      intro: intro,
    );
