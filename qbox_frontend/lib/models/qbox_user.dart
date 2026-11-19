import '../onboarding_draft.dart';

/// The logged-in user, as returned by the backend (GET /api/me).
class QboxUser {
  const QboxUser({
    required this.id,
    required this.mobile,
    required this.roles,
    this.shop,
    this.customer,
    this.supplier,
  });

  final int id;
  final String mobile;
  final Set<QboxRole> roles;
  final ShopProfile? shop;
  final CustomerProfile? customer;
  final SupplierProfile? supplier;

  factory QboxUser.fromJson(Map<String, dynamic> json) {
    final shop = json['shop'] as Map<String, dynamic>?;
    final customer = json['customer'] as Map<String, dynamic>?;
    final supplier = json['supplier'] as Map<String, dynamic>?;
    return QboxUser(
      id: (json['id'] as num).toInt(),
      mobile: json['mobile'] as String,
      roles: {
        for (final code in (json['roles'] as List<dynamic>? ?? const []))
          ?roleFromCode(code as String),
      },
      shop: shop == null
          ? null
          : ShopProfile(
              qboxId: shop['qboxId'] as String,
              shopName: shop['shopName'] as String,
            ),
      customer: customer == null
          ? null
          : CustomerProfile(
              qboxId: customer['qboxId'] as String,
              fullName: customer['fullName'] as String,
            ),
      supplier: supplier == null
          ? null
          : SupplierProfile(
              qboxId: supplier['qboxId'] as String,
              supplierName: supplier['supplierName'] as String,
            ),
    );
  }

  /// Same shape as the backend sends, so [QboxUser.fromJson] can read it back.
  /// Used to keep a copy on the phone for opening the app offline.
  Map<String, dynamic> toJson() => {
        'id': id,
        'mobile': mobile,
        'roles': [
          for (final role in QboxRole.values)
            if (roles.contains(role)) roleCode(role),
        ],
        'shop': shop == null
            ? null
            : {'qboxId': shop!.qboxId, 'shopName': shop!.shopName},
        'customer': customer == null
            ? null
            : {'qboxId': customer!.qboxId, 'fullName': customer!.fullName},
        'supplier': supplier == null
            ? null
            : {
                'qboxId': supplier!.qboxId,
                'supplierName': supplier!.supplierName,
              },
      };
}

class ShopProfile {
  const ShopProfile({required this.qboxId, required this.shopName});

  final String qboxId;
  final String shopName;
}

class CustomerProfile {
  const CustomerProfile({required this.qboxId, required this.fullName});

  final String qboxId;
  final String fullName;
}

class SupplierProfile {
  const SupplierProfile({required this.qboxId, required this.supplierName});

  final String qboxId;
  final String supplierName;
}

/// The backend writes roles in capitals: BUSINESS, CUSTOMER, SUPPLIER.
String roleCode(QboxRole role) => switch (role) {
      QboxRole.business => 'BUSINESS',
      QboxRole.customer => 'CUSTOMER',
      QboxRole.supplier => 'SUPPLIER',
    };

QboxRole? roleFromCode(String code) => switch (code) {
      'BUSINESS' => QboxRole.business,
      'CUSTOMER' => QboxRole.customer,
      'SUPPLIER' => QboxRole.supplier,
      _ => null,
    };
