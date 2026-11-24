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

  /// The ref of their photo in [role] (null = none).
  String? photoFor(QboxRole role) => switch (role) {
    QboxRole.business => shop?.photo,
    QboxRole.customer => customer?.photo,
    QboxRole.supplier => supplier?.photo,
  };

  String? qboxIdFor(QboxRole role) => switch (role) {
    QboxRole.business => shop?.qboxId,
    QboxRole.customer => customer?.qboxId,
    QboxRole.supplier => supplier?.qboxId,
  };

  String nameFor(QboxRole role) => switch (role) {
    QboxRole.business => shop?.shopName,
    QboxRole.customer => customer?.fullName,
    QboxRole.supplier => supplier?.supplierName,
  } ?? '';

  factory QboxUser.fromJson(Map<String, dynamic> json) {
    final shop = json['shop'];
    final customer = json['customer'];
    final supplier = json['supplier'];
    return QboxUser(
      id: (json['id'] as num).toInt(),
      mobile: json['mobile'] as String,
      roles: {
        for (final code in (json['roles'] as List<dynamic>? ?? const []))
          ?roleFromCode(code as String),
      },
      shop: shop is Map<String, dynamic> ? ShopProfile.fromJson(shop) : null,
      customer: customer is Map<String, dynamic> ? CustomerProfile.fromJson(customer) : null,
      supplier: supplier is Map<String, dynamic> ? SupplierProfile.fromJson(supplier) : null,
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
    'shop': shop?.toJson(),
    'customer': customer?.toJson(),
    'supplier': supplier?.toJson(),
  };
}

String _text(Object? v) => v is String ? v : '';

String? _orNull(Object? v) => v is String && v.isNotEmpty ? v : null;

class ShopProfile {
  const ShopProfile({
    required this.qboxId,
    required this.shopName,
    this.businessType = '',
    this.businessTypeDetail = '',
    this.shopCategory = '',
    this.shopCategoryDetail = '',
    this.address = '',
    this.contactNumber = '',
    this.photo,
  });

  factory ShopProfile.fromJson(Map<String, dynamic> json) => ShopProfile(
    qboxId: json['qboxId'] as String,
    shopName: json['shopName'] as String,
    businessType: _text(json['businessType']),
    businessTypeDetail: _text(json['businessTypeDetail']),
    shopCategory: _text(json['shopCategory']),
    shopCategoryDetail: _text(json['shopCategoryDetail']),
    address: _text(json['address']),
    contactNumber: _text(json['contactNumber']),
    photo: _orNull(json['photo']),
  );

  final String qboxId;
  final String shopName;
  final String businessType;
  final String businessTypeDetail;
  final String shopCategory;
  final String shopCategoryDetail;
  final String address;
  final String contactNumber;
  final String? photo;

  Map<String, dynamic> toJson() => {
    'qboxId': qboxId,
    'shopName': shopName,
    'businessType': businessType,
    'businessTypeDetail': businessTypeDetail,
    'shopCategory': shopCategory,
    'shopCategoryDetail': shopCategoryDetail,
    'address': address,
    'contactNumber': contactNumber,
    'photo': photo,
  };
}

class CustomerProfile {
  const CustomerProfile({
    required this.qboxId,
    required this.fullName,
    this.mobileNumber = '',
    this.email = '',
    this.address = '',
    this.photo,
  });

  factory CustomerProfile.fromJson(Map<String, dynamic> json) => CustomerProfile(
    qboxId: json['qboxId'] as String,
    fullName: json['fullName'] as String,
    mobileNumber: _text(json['mobileNumber']),
    email: _text(json['email']),
    address: _text(json['address']),
    photo: _orNull(json['photo']),
  );

  final String qboxId;
  final String fullName;
  final String mobileNumber;
  final String email;
  final String address;
  final String? photo;

  Map<String, dynamic> toJson() => {
    'qboxId': qboxId,
    'fullName': fullName,
    'mobileNumber': mobileNumber,
    'email': email,
    'address': address,
    'photo': photo,
  };
}

class SupplierProfile {
  const SupplierProfile({
    required this.qboxId,
    required this.supplierName,
    this.businessType = '',
    this.businessTypeDetail = '',
    this.productsSupplied = '',
    this.contactNumber = '',
    this.address = '',
    this.photo,
  });

  factory SupplierProfile.fromJson(Map<String, dynamic> json) => SupplierProfile(
    qboxId: json['qboxId'] as String,
    supplierName: json['supplierName'] as String,
    businessType: _text(json['businessType']),
    businessTypeDetail: _text(json['businessTypeDetail']),
    productsSupplied: _text(json['productsSupplied']),
    contactNumber: _text(json['contactNumber']),
    address: _text(json['address']),
    photo: _orNull(json['photo']),
  );

  final String qboxId;
  final String supplierName;
  final String businessType;
  final String businessTypeDetail;
  final String productsSupplied;
  final String contactNumber;
  final String address;
  final String? photo;

  Map<String, dynamic> toJson() => {
    'qboxId': qboxId,
    'supplierName': supplierName,
    'businessType': businessType,
    'businessTypeDetail': businessTypeDetail,
    'productsSupplied': productsSupplied,
    'contactNumber': contactNumber,
    'address': address,
    'photo': photo,
  };
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
