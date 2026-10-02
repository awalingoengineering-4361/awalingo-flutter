import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _kDevRoleOverrideKey = 'dev_role_override';

// TEMPORARY dev-only role override (see lib/widgets/dev_role_switcher.dart):
// user_roles has RLS that blocks a user from writing their own row (by
// design — role changes are only meant to happen through vetted
// server-side flows like promote_user_to_curator), so testing role-gated
// UI without a database change means overriding what fetchUserRole()
// *returns* instead of what's actually stored. Only takes effect in debug
// builds; remove alongside dev_role_switcher.dart once role-testing is done.
Future<void> setDevRoleOverride(String? role) async {
  if (!kDebugMode) return;
  final prefs = await SharedPreferences.getInstance();
  if (role == null) {
    await prefs.remove(_kDevRoleOverrideKey);
  } else {
    await prefs.setString(_kDevRoleOverrideKey, role);
  }
}

Future<String?> devRoleOverride() async {
  if (!kDebugMode) return null;
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString(_kDevRoleOverrideKey);
}

// Mirrors neolingo/src/lib/auth/permissions.ts exactly — the Next.js app's
// ROLE_PERMISSIONS map is the single source of truth; this is a client-side
// port so Flutter shows/hides screens and actions the same way, and to keep
// the UI in sync with the matching Postgres RLS policies (which enforce the
// same rules server-side).

class Permission {
  static const reviewRequests = 'review:requests';
  static const approveRequests = 'approve:requests';
  static const manageUsers = 'manage:users';
  static const createRequests = 'create:requests';
  static const voteSuggestions = 'vote:suggestions';
  static const viewAdmin = 'view:admin';
  static const viewManager = 'view:manager';
  static const rateNeos = 'rate:neos';
  static const takeQuiz = 'take:quiz';
  static const createNeos = 'create:neos';
}

const _communityBasePermissions = [
  Permission.createRequests,
  Permission.voteSuggestions,
  Permission.createNeos,
];

const _reviewPermissions = [
  Permission.reviewRequests,
  Permission.approveRequests,
];

const Map<String, List<String>> rolePermissions = {
  'ADMIN': [
    ..._reviewPermissions,
    Permission.manageUsers,
    ..._communityBasePermissions,
    Permission.viewAdmin,
    Permission.rateNeos,
  ],
  'JUROR': [
    ..._reviewPermissions,
    ..._communityBasePermissions,
    Permission.rateNeos,
  ],
  'CURATOR': [..._communityBasePermissions, Permission.reviewRequests],
  'MANAGER': [
    Permission.viewManager,
    ..._communityBasePermissions,
    Permission.reviewRequests,
  ],
  'EXPLORER': [Permission.takeQuiz, Permission.voteSuggestions],
};

bool hasPermission(String? role, String permission) =>
    rolePermissions[role]?.contains(permission) ?? false;

/// Reads the caller's role name (e.g. 'CURATOR') the same way every screen
/// already does: `user_roles` joined to `roles`. Mirrors getUserRole()
/// (server-auth.ts:39-42): defaults to 'EXPLORER' when the user has no role
/// row, since that's the implicit default role, not "no permissions at all".
Future<String> fetchUserRole(SupabaseClient db, String userId) async {
  final override = await devRoleOverride();
  if (override != null) return override;

  final row = await db
      .from('user_roles')
      .select('role:roles!roleId(name)')
      .eq('userId', userId)
      .limit(1)
      .maybeSingle();
  final role = row?['role'] as Map<String, dynamic>?;
  return (role?['name'] as String?) ?? 'EXPLORER';
}
