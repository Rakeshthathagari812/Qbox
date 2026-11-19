import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'onboarding_draft.dart';
import 'pin_screen.dart';
import 'widgets/signup_route.dart';
import 'registration_options.dart';
import 'widgets/qbox_wave.dart';
import 'widgets/signup_column.dart';
import 'widgets/signup_motion.dart';

/// Page 3. Shows one registration form at a time, only for the roles
/// chosen on page 2, in the order business, customer, supplier.
class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({super.key});

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  OnboardingDraft? _draft;

  OnboardingDraft get _onboarding => _draft!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _draft ??= OnboardingScope.of(context);
    _onboarding.useVerifiedMobile(_onboarding.mobileNumber);
    final steps = _onboarding.orderedRoles();
    if (steps.isEmpty) {
      _onboarding.formIndex = 0;
    } else if (_onboarding.formIndex >= steps.length) {
      _onboarding.formIndex = steps.length - 1;
    }
  }

  void _back() {
    if (_onboarding.formIndex > 0) {
      setState(() => _onboarding.formIndex -= 1);
      return;
    }
    Navigator.of(context).pop();
  }

  void _next() {
    final last = _onboarding.orderedRoles().length - 1;
    if (_onboarding.formIndex < last) {
      setState(() => _onboarding.formIndex += 1);
      return;
    }
    Navigator.of(context).push(signupRoute(const PinScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final steps = _onboarding.orderedRoles();
    if (steps.isEmpty) {
      return const Scaffold(body: SizedBox.shrink());
    }
    final index = _onboarding.formIndex;
    final role = steps[index];

    return Scaffold(
      backgroundColor: const Color(0xFFF7F4FF),
      body: Stack(
        children: [
          const Align(
            alignment: Alignment.bottomCenter,
            child: QboxWaveFooter(),
          ),
          SafeArea(
            bottom: false,
            child: SignupMotionHost(
              child: Column(
              children: [
                RiseIn(
                  index: 0,
                  child: _RegistrationHeader(
                  count: steps.length,
                  index: index,
                  onBack: _back,
                ),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: Duration.zero,
                    child: KeyedSubtree(
                    key: ValueKey(role),
                    child: switch (role) {
                      QboxRole.business => _ShopForm(
                          data: _onboarding.shop,
                          onValid: _next,
                        ),
                      QboxRole.customer => _CustomerForm(
                          data: _onboarding.customer,
                          onValid: _next,
                        ),
                      QboxRole.supplier => _SupplierForm(
                          data: _onboarding.supplier,
                          onValid: _next,
                        ),
                    },
                  ),
                  ),
                ),
              ],
            ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RegistrationHeader extends StatelessWidget {
  const _RegistrationHeader({
    required this.count,
    required this.index,
    required this.onBack,
  });

  final int count;
  final int index;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 20, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: onBack,
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFFF1EDF8),
              foregroundColor: _ink,
              fixedSize: const Size(42, 42),
            ),
            icon: const Icon(Icons.arrow_back, size: 20),
          ),
          Expanded(
            child: Center(
              child: _Progress(count: count, index: index),
            ),
          ),
          const SizedBox(width: 42),
        ],
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final dots = <Widget>[];
    for (var step = 0; step < count; step++) {
      final done = step < index;
      final current = step == index;
      final size = current || done ? 22.0 : 10.0;
      dots.add(
        AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: done || current ? _purple : const Color(0xFFD9CCF5),
            shape: BoxShape.circle,
          ),
          child: done
              ? const Icon(Icons.check, size: 14, color: Colors.white)
              : null,
        ),
      );
      if (step < count - 1) {
        dots.add(
          Container(
            width: 36,
            height: 3,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFD9CCF5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }
    }
    return Row(mainAxisSize: MainAxisSize.min, children: dots);
  }
}

mixin _KeepsFields<T extends StatefulWidget> on State<T> {
  bool get fieldsSubmitted;

  void keep(TextEditingController controller, void Function(String value) write) {
    controller.addListener(() {
      write(controller.text);
      if (fieldsSubmitted && mounted) setState(() {});
    });
  }
}

class _ShopForm extends StatefulWidget {
  const _ShopForm({required this.data, required this.onValid});

  final ShopRegistration data;
  final VoidCallback onValid;

  @override
  State<_ShopForm> createState() => _ShopFormState();
}

class _ShopFormState extends State<_ShopForm> with _KeepsFields {
  late final TextEditingController _name;
  late final TextEditingController _address;
  late final TextEditingController _phone;
  late final TextEditingController _typeDetail;
  late final TextEditingController _categoryDetail;
  bool _submitted = false;

  @override
  bool get fieldsSubmitted => _submitted;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.data.shopName);
    _address = TextEditingController(text: widget.data.address);
    _phone = TextEditingController(
      text: _groupedMobile(widget.data.contactNumber),
    );
    _typeDetail = TextEditingController(text: widget.data.businessTypeDetail);
    _categoryDetail = TextEditingController(
      text: widget.data.shopCategoryDetail,
    );
    keep(_name, (value) => widget.data.shopName = value);
    keep(_address, (value) => widget.data.address = value);
    keep(_phone, (value) => widget.data.contactNumber = _mobileDigits(value));
    keep(_typeDetail, (value) => widget.data.businessTypeDetail = value);
    keep(_categoryDetail, (value) => widget.data.shopCategoryDetail = value);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _showVerifiedMobile(context, _phone);
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _phone.dispose();
    _typeDetail.dispose();
    _categoryDetail.dispose();
    super.dispose();
  }

  String? _required(String value, String message) {
    if (!_submitted) return null;
    return value.trim().isEmpty ? message : null;
  }

  void _continue() {
    setState(() => _submitted = true);
    final phoneOk = _isMobile(widget.data.contactNumber);
    final ready = widget.data.shopName.trim().isNotEmpty &&
        _choiceReady(
          widget.data.businessType,
          widget.data.businessTypeDetail,
        ) &&
        _choiceReady(
          widget.data.shopCategory,
          widget.data.shopCategoryDetail,
        ) &&
        widget.data.address.trim().isNotEmpty &&
        phoneOk;
    if (ready) widget.onValid();
  }

  @override
  Widget build(BuildContext context) {
    return _FormBody(
      title: 'Tell us about your shop',
      subtitle: 'Register your shop to start using\nQBOX for your business.',
      art: const _RoleArt('assets/images/art_shop.png'),
      onContinue: _continue,
      children: [
        _TextCard(
          fieldKey: const Key('shop-name'),
          icon: Icons.storefront_outlined,
          label: 'Shop Name *',
          hint: 'Enter shop name',
          controller: _name,
          error: _required(widget.data.shopName, 'Enter shop name'),
        ),
        _ChoiceCard(
          fieldKey: const Key('shop-type'),
          icon: Icons.work_outline,
          label: 'Business Type *',
          hint: 'Select business type',
          value: widget.data.businessType,
          options: businessTypes,
          error: _required(widget.data.businessType, 'Select business type'),
          detailController: _typeDetail,
          detailKey: const Key('shop-type-other'),
          detailHint: 'Enter your business type',
          detailError: _otherError(
            _submitted,
            widget.data.businessType,
            widget.data.businessTypeDetail,
            'Enter your business type',
          ),
          onChanged: (value) => setState(() {
            widget.data.businessType = value;
          }),
        ),
        _ChoiceCard(
          fieldKey: const Key('shop-category'),
          icon: Icons.grid_view_rounded,
          label: 'Shop Category *',
          hint: 'Select category',
          value: widget.data.shopCategory,
          options: shopCategories,
          error: _required(widget.data.shopCategory, 'Select category'),
          detailController: _categoryDetail,
          detailKey: const Key('shop-category-other'),
          detailHint: 'Enter your shop category',
          detailError: _otherError(
            _submitted,
            widget.data.shopCategory,
            widget.data.shopCategoryDetail,
            'Enter your shop category',
          ),
          onChanged: (value) => setState(() {
            widget.data.shopCategory = value;
          }),
        ),
        _TextCard(
          fieldKey: const Key('shop-address'),
          icon: Icons.location_on_outlined,
          label: 'Shop Address *',
          hint: 'Enter shop address',
          controller: _address,
          error: _required(widget.data.address, 'Enter shop address'),
        ),
        _TextCard(
          fieldKey: const Key('shop-phone'),
          icon: Icons.phone_outlined,
          label: 'Contact Number *',
          hint: 'Enter mobile number',
          controller: _phone,
          keyboard: TextInputType.phone,
          digitsOnly: true,
          error: _phoneError(widget.data.contactNumber, _submitted),
        ),
      ],
    );
  }
}

class _CustomerForm extends StatefulWidget {
  const _CustomerForm({required this.data, required this.onValid});

  final CustomerRegistration data;
  final VoidCallback onValid;

  @override
  State<_CustomerForm> createState() => _CustomerFormState();
}

class _CustomerFormState extends State<_CustomerForm> with _KeepsFields {
  late final TextEditingController _name;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _address;
  bool _submitted = false;

  @override
  bool get fieldsSubmitted => _submitted;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.data.fullName);
    _phone = TextEditingController(text: _groupedMobile(widget.data.mobileNumber));
    _email = TextEditingController(text: widget.data.email);
    _address = TextEditingController(text: widget.data.address);
    keep(_name, (value) => widget.data.fullName = value);
    keep(_phone, (value) => widget.data.mobileNumber = _mobileDigits(value));
    keep(_email, (value) => widget.data.email = value);
    keep(_address, (value) => widget.data.address = value);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _showVerifiedMobile(context, _phone);
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    super.dispose();
  }

  void _continue() {
    setState(() => _submitted = true);
    final email = widget.data.email.trim();
    final emailOk = email.isEmpty || email.contains('@');
    final ready = widget.data.fullName.trim().isNotEmpty &&
        _isMobile(widget.data.mobileNumber) &&
        emailOk;
    if (ready) widget.onValid();
  }

  @override
  Widget build(BuildContext context) {
    final email = widget.data.email.trim();
    return _FormBody(
      title: 'Tell us about yourself',
      subtitle: 'Register as a customer to enjoy\nQBOX services.',
      art: const _RoleArt('assets/images/art_customer.png'),
      onContinue: _continue,
      children: [
        _TextCard(
          fieldKey: const Key('customer-name'),
          icon: Icons.person_outline,
          label: 'Full Name *',
          hint: 'Enter your name',
          controller: _name,
          error: _submitted && widget.data.fullName.trim().isEmpty
              ? 'Enter your name'
              : null,
        ),
        _TextCard(
          fieldKey: const Key('customer-phone'),
          icon: Icons.phone_outlined,
          label: 'Mobile Number *',
          hint: 'Enter mobile number',
          controller: _phone,
          keyboard: TextInputType.phone,
          digitsOnly: true,
          error: _phoneError(widget.data.mobileNumber, _submitted),
        ),
        _TextCard(
          fieldKey: const Key('customer-email'),
          icon: Icons.mail_outline,
          label: 'Email Address (Optional)',
          hint: 'Enter email address',
          controller: _email,
          keyboard: TextInputType.emailAddress,
          error: _submitted && email.isNotEmpty && !email.contains('@')
              ? 'Enter a valid email'
              : null,
        ),
        _TextCard(
          fieldKey: const Key('customer-address'),
          icon: Icons.home_outlined,
          label: 'Address (Optional)',
          hint: 'Enter address',
          controller: _address,
        ),
        _AadhaarCard(
          requested: widget.data.aadhaarLinkRequested,
          onTap: () => setState(() {
            widget.data.aadhaarLinkRequested =
                !widget.data.aadhaarLinkRequested;
          }),
        ),
      ],
    );
  }
}

class _SupplierForm extends StatefulWidget {
  const _SupplierForm({required this.data, required this.onValid});

  final SupplierRegistration data;
  final VoidCallback onValid;

  @override
  State<_SupplierForm> createState() => _SupplierFormState();
}

class _SupplierFormState extends State<_SupplierForm> with _KeepsFields {
  late final TextEditingController _name;
  late final TextEditingController _products;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  late final TextEditingController _typeDetail;
  bool _submitted = false;

  @override
  bool get fieldsSubmitted => _submitted;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.data.supplierName);
    _products = TextEditingController(text: widget.data.productsSupplied);
    _phone = TextEditingController(
      text: _groupedMobile(widget.data.contactNumber),
    );
    _address = TextEditingController(text: widget.data.address);
    _typeDetail = TextEditingController(text: widget.data.businessTypeDetail);
    keep(_name, (value) => widget.data.supplierName = value);
    keep(_products, (value) => widget.data.productsSupplied = value);
    keep(_phone, (value) => widget.data.contactNumber = _mobileDigits(value));
    keep(_address, (value) => widget.data.address = value);
    keep(_typeDetail, (value) => widget.data.businessTypeDetail = value);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _showVerifiedMobile(context, _phone);
  }

  @override
  void dispose() {
    _name.dispose();
    _products.dispose();
    _phone.dispose();
    _address.dispose();
    _typeDetail.dispose();
    super.dispose();
  }

  void _continue() {
    setState(() => _submitted = true);
    final ready = widget.data.supplierName.trim().isNotEmpty &&
        _choiceReady(
          widget.data.businessType,
          widget.data.businessTypeDetail,
        ) &&
        widget.data.productsSupplied.trim().isNotEmpty &&
        _isMobile(widget.data.contactNumber) &&
        widget.data.address.trim().isNotEmpty;
    if (ready) widget.onValid();
  }

  @override
  Widget build(BuildContext context) {
    return _FormBody(
      title: 'Tell us about your business',
      subtitle: 'Register as a supplier to connect\nwith merchants.',
      art: const _RoleArt('assets/images/art_supplier.png'),
      onContinue: _continue,
      children: [
        _TextCard(
          fieldKey: const Key('supplier-name'),
          icon: Icons.person_outline,
          label: 'Supplier Name *',
          hint: 'Enter supplier name',
          controller: _name,
          error: _submitted && widget.data.supplierName.trim().isEmpty
              ? 'Enter supplier name'
              : null,
        ),
        _ChoiceCard(
          fieldKey: const Key('supplier-type'),
          icon: Icons.work_outline,
          label: 'Business Type *',
          hint: 'Select business type',
          value: widget.data.businessType,
          options: businessTypes,
          error: _submitted && widget.data.businessType.isEmpty
              ? 'Select business type'
              : null,
          detailController: _typeDetail,
          detailKey: const Key('supplier-type-other'),
          detailHint: 'Enter your business type',
          detailError: _otherError(
            _submitted,
            widget.data.businessType,
            widget.data.businessTypeDetail,
            'Enter your business type',
          ),
          onChanged: (value) => setState(() {
            widget.data.businessType = value;
          }),
        ),
        _TextCard(
          fieldKey: const Key('supplier-products'),
          icon: Icons.inventory_2_outlined,
          label: 'Products Supplied *',
          hint: 'Enter products (e.g. FMCG)',
          controller: _products,
          error: _submitted && widget.data.productsSupplied.trim().isEmpty
              ? 'Enter products supplied'
              : null,
        ),
        _TextCard(
          fieldKey: const Key('supplier-phone'),
          icon: Icons.phone_outlined,
          label: 'Contact Number *',
          hint: 'Enter mobile number',
          controller: _phone,
          keyboard: TextInputType.phone,
          digitsOnly: true,
          error: _phoneError(widget.data.contactNumber, _submitted),
        ),
        _TextCard(
          fieldKey: const Key('supplier-address'),
          icon: Icons.location_on_outlined,
          label: 'Address *',
          hint: 'Enter address',
          controller: _address,
          error: _submitted && widget.data.address.trim().isEmpty
              ? 'Enter address'
              : null,
        ),
      ],
    );
  }
}

class _FormBody extends StatelessWidget {
  const _FormBody({
    required this.title,
    required this.subtitle,
    required this.art,
    required this.children,
    required this.onContinue,
  });

  final String title;
  final String subtitle;
  final Widget art;
  final List<Widget> children;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    return SignupMotionHost(
      child: SignupColumn(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
        RiseIn(
          index: 0,
          child: Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 24,
            height: 1.2,
            fontWeight: FontWeight.w700,
            color: _ink,
          ),
        ),
        ),
        const SizedBox(height: 8),
        RiseIn(
          index: 1,
          child: Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 14,
            height: 1.4,
            fontWeight: FontWeight.w500,
            color: _body,
          ),
        ),
        ),
        const SizedBox(height: 12),
        RiseIn(index: 2, child: art),
        const SizedBox(height: 8),
        for (var i = 0; i < children.length; i++) ...[
          RiseIn(index: 3 + i, child: children[i]),
          const SizedBox(height: 12),
        ],
        ],
        ),
        RiseIn(
          index: 3 + children.length,
          child: _ContinueButton(onPressed: onContinue),
        ),
      ],
    ),
    );
  }
}

class _TextCard extends StatelessWidget {
  const _TextCard({
    required this.fieldKey,
    required this.icon,
    required this.label,
    required this.hint,
    required this.controller,
    this.error,
    this.keyboard,
    this.digitsOnly = false,
  });

  final Key fieldKey;
  final IconData icon;
  final String label;
  final String hint;
  final TextEditingController controller;
  final String? error;
  final TextInputType? keyboard;
  final bool digitsOnly;

  @override
  Widget build(BuildContext context) {
    return _FieldShell(
      icon: icon,
      label: label,
      error: error,
      child: TextField(
        key: fieldKey,
        controller: controller,
        keyboardType: keyboard,
        inputFormatters: digitsOnly ? const [_RegistrationMobileFormatter()] : null,
        style: const TextStyle(
          fontFamily: 'Poppins',
          fontSize: 14,
          color: _ink,
        ),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          hintText: error == null ? hint : null,
          hintStyle: const TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            color: _hint,
          ),
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  const _ChoiceCard({
    required this.fieldKey,
    required this.icon,
    required this.label,
    required this.hint,
    required this.value,
    required this.options,
    required this.onChanged,
    this.error,
    this.detailController,
    this.detailKey,
    this.detailHint,
    this.detailError,
  });

  final Key fieldKey;
  final IconData icon;
  final String label;
  final String hint;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final String? error;
  final TextEditingController? detailController;
  final Key? detailKey;
  final String? detailHint;
  final String? detailError;

  Future<void> _open(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final picked = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: const Color(0x141C0E57),
      transitionDuration: Duration.zero,
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return _OptionMenu(
          options: options,
          selected: value,
          anchor: box.localToGlobal(Offset.zero),
          anchorSize: box.size,
          screenSize: MediaQuery.sizeOf(dialogContext),
        );
      },
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final showDetail = value == otherOption && detailController != null;
    final hasValue = value.isNotEmpty;
    return _FieldShell(
      icon: icon,
      label: label,
      error: error,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            key: fieldKey,
            onTap: () => _open(context),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      hasValue ? value : (error == null ? hint : ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: hasValue ? 14 : 13,
                        fontWeight: hasValue ? FontWeight.w600 : FontWeight.w500,
                        color: hasValue ? _ink : _hint,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: _purple,
                  ),
                ],
              ),
            ),
          ),
          if (showDetail) ...[
            const Divider(height: 16, color: Color(0xFFE7E4F0)),
            TextField(
              key: detailKey,
              controller: detailController,
              style: const TextStyle(
                fontFamily: 'Poppins',
                fontSize: 14,
                color: _ink,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: detailError == null ? detailHint : null,
                hintStyle: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  color: _hint,
                ),
                contentPadding: EdgeInsets.zero,
              ),
            ),
            if (detailError != null) ...[
              const SizedBox(height: 4),
              Text(
                detailError!,
                style: const TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFFC2414B),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _OptionMenu extends StatelessWidget {
  const _OptionMenu({
    required this.options,
    required this.selected,
    required this.anchor,
    required this.anchorSize,
    required this.screenSize,
  });

  final List<String> options;
  final String selected;
  final Offset anchor;
  final Size anchorSize;
  final Size screenSize;

  @override
  Widget build(BuildContext context) {
    const margin = 12.0;
    const maxHeight = 320.0;
    final below = screenSize.height - (anchor.dy + anchorSize.height) - margin;
    final above = anchor.dy - margin;
    final openBelow = below >= 160 || below >= above;
    final room = openBelow ? below : above;
    final height = room < maxHeight ? room : maxHeight;
    final top = openBelow
        ? anchor.dy + anchorSize.height + 6
        : anchor.dy - height - 6;
    var left = anchor.dx;
    final width = anchorSize.width;
    if (left + width > screenSize.width - margin) {
      left = screenSize.width - margin - width;
    }
    if (left < margin) left = margin;

    return Stack(
      children: [
        Positioned(
          left: left,
          top: top.clamp(margin, screenSize.height - height - margin),
          width: width,
          height: height,
          child: Theme(
            data: Theme.of(context).copyWith(
              hoverColor: const Color(0xFFF4EEFF),
              highlightColor: const Color(0xFFF4EEFF),
              splashColor: const Color(0x22651CE4),
            ),
            child: Material(
              color: Colors.white,
              elevation: 8,
              shadowColor: const Color(0x331C0E57),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFE7E4F0)),
              ),
              clipBehavior: Clip.antiAlias,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 6),
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options[index];
                  final isSelected = option == selected;
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: Material(
                      color: isSelected
                          ? const Color(0xFFF4EEFF)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(option),
                        borderRadius: BorderRadius.circular(10),
                        child: SizedBox(
                          height: 40,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    option,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontFamily: 'Poppins',
                                      fontSize: 14,
                                      fontWeight: isSelected
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: isSelected ? _purple : _ink,
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(
                                    Icons.check,
                                    color: _purple,
                                    size: 18,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AadhaarCard extends StatelessWidget {
  const _AadhaarCard({required this.requested, required this.onTap});

  final bool requested;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _FieldShell(
      icon: Icons.badge_outlined,
      label: 'Link with Aadhaar (Optional)',
      child: Material(
        color: const Color(0xFFF4EEFF),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  switchInCurve: Curves.easeOutBack,
                  transitionBuilder: (child, animation) {
                    return ScaleTransition(scale: animation, child: child);
                  },
                  child: Icon(
                    requested
                        ? Icons.check_circle
                        : Icons.verified_user_outlined,
                    key: ValueKey(requested),
                    size: 18,
                    color: _purple,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Verify Aadhaar',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _purple,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldShell extends StatelessWidget {
  const _FieldShell({
    required this.icon,
    required this.label,
    required this.child,
    this.error,
  });

  final IconData icon;
  final String label;
  final Widget child;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120E1B4D),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: _ink, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 2),
                child,
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topLeft,
                  child: error == null
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            error!,
                            style: const TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFFC2414B),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContinueButton extends StatelessWidget {
  const _ContinueButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          colors: [Color(0xFF7C4DFF), Color(0xFF5B21E6)],
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: const Key('registration-continue'),
          onTap: onPressed,
          borderRadius: BorderRadius.circular(28),
          child: const SizedBox(
            height: 52,
            width: double.infinity,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Continue',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward, color: Colors.white, size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleArt extends StatelessWidget {
  const _RoleArt(this.asset);

  final String asset;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 128,
      child: Image.asset(asset, fit: BoxFit.contain),
    );
  }
}

const _ink = Color(0xFF1C0E57);
const _body = Color(0xFF5C5872);
const _hint = Color(0xFFA39EB8);
const _purple = Color(0xFF651CE4);

bool _isMobile(String value) =>
    RegExp(r'^[6-9]\d{9}$').hasMatch(_mobileDigits(value));

String _mobileDigits(String value) => value.replaceAll(RegExp(r'\D'), '');

String _groupedMobile(String value) {
  var digits = _mobileDigits(value);
  if (digits.length > 10) digits = digits.substring(0, 10);
  if (digits.length <= 5) return digits;
  return '${digits.substring(0, 5)} ${digits.substring(5)}';
}

void _showVerifiedMobile(BuildContext context, TextEditingController phone) {
  final draft = OnboardingScope.of(context);
  draft.useVerifiedMobile(draft.mobileNumber);
  if (_mobileDigits(phone.text).isNotEmpty || !_isMobile(draft.mobileNumber)) {
    return;
  }
  final shown = _groupedMobile(draft.mobileNumber);
  phone.value = TextEditingValue(
    text: shown,
    selection: TextSelection.collapsed(offset: shown.length),
  );
}

class _RegistrationMobileFormatter extends TextInputFormatter {
  const _RegistrationMobileFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final shown = _groupedMobile(newValue.text);
    return TextEditingValue(
      text: shown,
      selection: TextSelection.collapsed(offset: shown.length),
    );
  }
}

bool _choiceReady(String value, String detail) {
  if (value.isEmpty) return false;
  if (value == otherOption) return detail.trim().isNotEmpty;
  return true;
}

String? _otherError(
  bool submitted,
  String value,
  String detail,
  String message,
) {
  if (!submitted || value != otherOption || detail.trim().isNotEmpty) {
    return null;
  }
  return message;
}

String? _phoneError(String value, bool submitted) {
  if (!submitted) return null;
  if (value.trim().isEmpty) return 'Enter mobile number';
  if (!_isMobile(value)) return 'Enter a 10-digit mobile number';
  return null;
}
