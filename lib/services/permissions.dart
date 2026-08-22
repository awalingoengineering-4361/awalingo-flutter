import 'package:supabase_flutter/supabase_flutter.dart';

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
/// already does: `user_roles` joined to `roles`. Returns null if the user
/// has no role row (treat as no permissions, same as neolingo's default).
Future<String?> fetchUserRole(SupabaseClient db, String userId) async {
  final row = await db
      .from('user_roles')
      .select('role:roles!roleId(name)')
      .eq('userId', userId)
      .limit(1)
      .maybeSingle();
  final role = row?['role'] as Map<String, dynamic>?;
  return role?['name'] as String?;
}
