import 'package:flutter/widgets.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

/// Ways a client can pay a pro directly. The money never passes through
/// BeauTap: clients send it themselves, then tell the pro they've paid.

/// Turns "+263 77 123 4567", "771234567" or "0771234567" into "0771234567".
/// Returns null for an empty value and '' for something that isn't a
/// Zimbabwe mobile number.
String? normalizeZimMobile(String input) {
  var d = input.replaceAll(RegExp(r'\D'), '');
  if (d.isEmpty) return null;
  if (d.startsWith('263')) d = d.substring(3);
  if (d.length == 9 && d.startsWith('7')) d = '0$d';
  return RegExp(r'^07\d{8}$').hasMatch(d) ? d : '';
}

/// "0771234567" -> "077 123 4567"
String prettyMobile(String n) =>
    n.length == 10 ? '${n.substring(0, 3)} ${n.substring(3, 6)} ${n.substring(6)}' : n;

String amountText(num v) => v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

class PayMethod {
  final String id; // ecocash | innbucks | onemoney | bank | cash
  final String label;
  final IconData icon;

  /// Number, merchant code or bank details to send to.
  final String? account;
  final String? accountName;
  final bool isMerchant;

  const PayMethod(this.id, this.label, this.icon,
      {this.account, this.accountName, this.isMerchant = false});

  bool get isTransfer => id != 'cash';

  /// USSD string that opens the EcoCash USD menu with number and amount
  /// already filled in. The client only enters their PIN.
  String? ussd(num amount) {
    if (id != 'ecocash' || account == null) return null;
    final amt = amountText(amount);
    return isMerchant ? '*153*2*2*$account*$amt#' : '*153*1*1*$account*$amt#';
  }

  String get displayAccount =>
      isMerchant ? 'merchant code $account' : (id == 'bank' ? (account ?? '') : prettyMobile(account ?? ''));
}

/// Methods a pro accepts, from their provider_profiles row. Transfers come
/// first (EcoCash leads), cash last.
List<PayMethod> payMethodsOf(Map<String, dynamic>? pp, {bool includeCash = true}) {
  if (pp == null) return includeCash ? const [PayMethod('cash', 'Cash', TablerIcons.cash)] : const [];
  String? s(String k) {
    final v = (pp[k] ?? '').toString().trim();
    return v.isEmpty ? null : v;
  }

  final name = s('ecocash_name');
  return [
    if (s('ecocash_number') != null)
      PayMethod('ecocash', 'EcoCash', TablerIcons.device_mobile, account: s('ecocash_number'), accountName: name)
    else if (s('ecocash_merchant') != null)
      PayMethod('ecocash', 'EcoCash', TablerIcons.device_mobile,
          account: s('ecocash_merchant'), accountName: name, isMerchant: true),
    if (s('innbucks_number') != null)
      PayMethod('innbucks', 'InnBucks', TablerIcons.wallet, account: s('innbucks_number')),
    if (s('onemoney_number') != null)
      PayMethod('onemoney', 'OneMoney', TablerIcons.device_mobile_dollar, account: s('onemoney_number')),
    if (s('bank_details') != null)
      PayMethod('bank', 'Bank transfer', TablerIcons.building_bank, account: s('bank_details')),
    if (includeCash && pp['accepts_cash'] != false) const PayMethod('cash', 'Cash', TablerIcons.cash),
  ];
}

String payMethodLabel(String? id) => switch (id) {
      'ecocash' => 'EcoCash',
      'innbucks' => 'InnBucks',
      'onemoney' => 'OneMoney',
      'bank' => 'Bank transfer',
      'paynow' => 'Card',
      _ => 'Cash',
    };
