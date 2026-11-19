import 'package:flutter/widgets.dart';

import 'models/qbox_user.dart';

enum QboxRole { business, customer, supplier }

/// Choices made during sign-up. Kept above the pages so Back does not
/// clear them, and the next onboarding step can read them later.
/// After login it also holds the logged-in [user].
class OnboardingDraft {
  final Set<QboxRole> roles = <QboxRole>{};
  int formIndex = 0;
  String mobileNumber = '';

  /// Proof from the backend that [mobileNumber] passed the OTP check.
  String verificationToken = '';

  /// Filled after login (or when the app reopens while logged in).
  QboxUser? user;

  var shop = ShopRegistration();
  var customer = CustomerRegistration();
  var supplier = SupplierRegistration();

  /// Copies the logged-in user's roles and names into the draft, so the
  /// role chooser and home screens show the account's real details.
  void applyUser(QboxUser account) {
    user = account;
    mobileNumber = account.mobile;
    roles
      ..clear()
      ..addAll(account.roles);
    shop.shopName = account.shop?.shopName ?? '';
    customer.fullName = account.customer?.fullName ?? '';
    supplier.supplierName = account.supplier?.supplierName ?? '';
  }

  /// Forgets everything, for log out.
  void clear() {
    roles.clear();
    formIndex = 0;
    mobileNumber = '';
    verificationToken = '';
    user = null;
    shop = ShopRegistration();
    customer = CustomerRegistration();
    supplier = SupplierRegistration();
  }

  /// Copies the verified mobile into each role form that still has that
  /// number, or no number yet. A number the user typed themselves stays.
  void useVerifiedMobile(String number, {String previous = ''}) {
    final next = number.replaceAll(RegExp(r'\D'), '');
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(next)) return;
    final prior = previous.replaceAll(RegExp(r'\D'), '');
    mobileNumber = next;
    void carry(String current, void Function(String value) write) {
      final digits = current.replaceAll(RegExp(r'\D'), '');
      if (digits.isEmpty || (prior.isNotEmpty && digits == prior)) {
        write(next);
      }
    }

    carry(shop.contactNumber, (value) => shop.contactNumber = value);
    carry(customer.mobileNumber, (value) => customer.mobileNumber = value);
    carry(supplier.contactNumber, (value) => supplier.contactNumber = value);
  }

  List<QboxRole> orderedRoles() {
    const order = [
      QboxRole.business,
      QboxRole.customer,
      QboxRole.supplier,
    ];
    return [
      for (final role in order)
        if (roles.contains(role)) role,
    ];
  }
}

class ShopRegistration {
  String shopName = '';
  String businessType = '';
  String businessTypeDetail = '';
  String shopCategory = '';
  String shopCategoryDetail = '';
  String address = '';
  String contactNumber = '';
}

class CustomerRegistration {
  String fullName = '';
  String mobileNumber = '';
  String email = '';
  String address = '';
  bool aadhaarLinkRequested = false;
}

class SupplierRegistration {
  String supplierName = '';
  String businessType = '';
  String businessTypeDetail = '';
  String productsSupplied = '';
  String contactNumber = '';
  String address = '';
}

class OnboardingScope extends InheritedWidget {
  const OnboardingScope({
    required this.draft,
    required super.child,
    super.key,
  });

  final OnboardingDraft draft;

  static OnboardingDraft of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<OnboardingScope>();
    assert(scope != null, 'OnboardingScope is missing above this screen');
    return scope!.draft;
  }

  @override
  bool updateShouldNotify(OnboardingScope oldWidget) =>
      oldWidget.draft != draft;
}
