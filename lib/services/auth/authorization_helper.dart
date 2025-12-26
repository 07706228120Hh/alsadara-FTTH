import 'auth_context.dart';
import 'permissions_merger.dart';

class AuthorizationHelper {
  final AuthContext? ctx;
  final EffectivePermissions perms;
  final List<String> apiPermissions; // raw displayValues

  AuthorizationHelper(
      {required this.ctx, required this.perms, required this.apiPermissions});

  bool get canViewWallet =>
      perms['wallet_balance'] || (ctx?.hasRole('ZoneAdmin') ?? false);
  bool get canManageZones =>
      (ctx?.hasRole('ZoneAdmin') ?? false) ||
      _hasApi('Can Manage Zones') ||
      perms['zones'];
  bool get canExport => perms['export'] || (ctx?.hasRole('ZoneAdmin') ?? false);
  bool get canViewAccounts =>
      perms['accounts'] || (ctx?.hasRole('ZoneAdmin') ?? false);
  bool get canViewAccountRecords => perms['account_records'] || canViewAccounts;
  bool get canQuickSearch => perms['quick_search'] || perms['users'];
  bool get canSeeExpiring => perms['expiring_soon'] || perms['subscriptions'];
  bool get isContractorMember => ctx?.hasRole('ContractorMember') ?? false;
  bool get isZoneAdmin => ctx?.hasRole('ZoneAdmin') ?? false;

  bool _hasApi(String k) => apiPermissions.any((p) => p.contains(k));
}
