import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/app_shell.dart';
import '../services/auth_provider.dart';
import '../services/permissions.dart';

// ── TEMPORARY DEV TOOL — remove this file, its call site in
// profile_screen.dart, and setDevRoleOverride/devRoleOverride in
// permissions.dart once role-testing is done. ──────────────────────────────
//
// Only ever rendered under `if (kDebugMode)` by its caller, so it's compiled
// out of release builds entirely. Doesn't touch the database at all —
// user_roles has RLS that blocks a user from writing their own row (by
// design), so this overrides what fetchUserRole() *returns* on this device
// instead (via SharedPreferences, checked first by fetchUserRole — see
// permissions.dart). Your actual stored role never changes.
const _kDevSwitchableRoles = ['EXPLORER', 'CURATOR', 'JUROR'];

class DevRoleSwitcher extends StatefulWidget {
  const DevRoleSwitcher({super.key});

  @override
  State<DevRoleSwitcher> createState() => _DevRoleSwitcherState();
}

class _DevRoleSwitcherState extends State<DevRoleSwitcher> {
  final _db = Supabase.instance.client;
  String? _realRole;
  String? _override;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = AuthProvider.of(context).user?.id;
    if (userId == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final override = await devRoleOverride();
      // Bypass the override just for this one read, so we always know the
      // real stored role underneath it (needed for the "Reset" button).
      await setDevRoleOverride(null);
      final realRole = await fetchUserRole(_db, userId);
      if (override != null) await setDevRoleOverride(override);
      if (mounted) {
        setState(() {
          _realRole = realRole;
          _override = override;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('DevRoleSwitcher load: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _switchTo(String? role) async {
    if (role == _override) return;
    await setDevRoleOverride(role);
    AppShell.refreshRole();
    if (!mounted) return;
    setState(() => _override = role);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          role == null ? 'Back to your real role ($_realRole)' : 'Now testing as $role',
          style: const TextStyle(fontFamily: 'Metropolis'),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveRole = _override ?? _realRole;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFCD34D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bug_report_outlined, size: 16, color: Color(0xFF92400E)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _loading
                      ? 'DEV: Switch Role'
                      : 'DEV: Switch Role (real: ${_realRole ?? '?'})',
                  style: const TextStyle(fontFamily: 'Metropolis', fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF92400E)),
                ),
              ),
              if (_override != null)
                GestureDetector(
                  onTap: () => _switchTo(null),
                  child: const Text(
                    'Reset',
                    style: TextStyle(fontFamily: 'Metropolis', fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF92400E), decoration: TextDecoration.underline),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: _kDevSwitchableRoles.map((role) {
              final selected = role == effectiveRole;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => _switchTo(role),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: selected ? const Color(0xFF92400E) : Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF92400E).withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        role[0] + role.substring(1).toLowerCase(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Metropolis',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: selected ? Colors.white : const Color(0xFF92400E),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
