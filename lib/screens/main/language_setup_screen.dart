import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/auth_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_buttons.dart';
import '../../widgets/country_flag.dart';

class LanguageSetupScreen extends StatefulWidget {
  const LanguageSetupScreen({super.key});

  @override
  State<LanguageSetupScreen> createState() => _LanguageSetupScreenState();
}

class _LanguageSetupScreenState extends State<LanguageSetupScreen> {
  final _db = Supabase.instance.client;
  bool _loading = true;
  bool _saving = false;
  bool _loadFailed = false;
  List<({int id, String name, String? countryCode, bool isSupported})>
  _languages = [];
  int? _selectedId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return;
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final membership = await _db
          .from('user_target_languages')
          .select('languageId')
          .eq('userId', userId)
          .limit(1)
          .maybeSingle();
      if (!_ownsSetup(userId)) return;
      if (membership != null) {
        _openHome();
        return;
      }

      final rows = await _db
          .from('languages')
          .select('id, name, icon, is_supported')
          .or('icon.eq.NG,type.eq.LRL')
          .order('name');
      if (!_ownsSetup(userId)) return;
      // Match the web picker's order, with Nigerian communities first.
      setState(() {
        _languages = [
          for (final group in [true, false])
            for (final row in rows)
              if ((row['icon'] == 'NG') == group)
                (
                  id: row['id'] as int,
                  name: row['name'] as String,
                  countryCode: row['icon'] as String?,
                  isSupported: row['is_supported'] == true,
                ),
        ];
        _loading = false;
      });
    } catch (_) {
      if (_ownsSetup(userId)) {
        setState(() {
          _loading = false;
          _loadFailed = true;
        });
      }
    }
  }

  bool _ownsSetup(String userId) =>
      mounted && _db.auth.currentUser?.id == userId;

  void _openHome() => Navigator.of(context).pushReplacementNamed('/home');

  Future<void> _save() async {
    final languageId = _selectedId;
    final userId = _db.auth.currentUser?.id;
    if (userId == null || languageId == null || _saving) return;
    setState(() => _saving = true);
    try {
      await _db.rpc(
        'complete_community_onboarding',
        params: {'p_language_id': languageId},
      );
      if (_ownsSetup(userId)) _openHome();
    } catch (_) {
      if (_ownsSetup(userId)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save your community. Please try again.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (_ownsSetup(userId)) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        actionsPadding: const EdgeInsets.only(right: 16),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => AuthProvider.of(context).logout(),
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _loading
                  ? const CircularProgressIndicator(strokeWidth: 2)
                  : _loadFailed || _languages.isEmpty
                  ? SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _loadFailed
                                ? 'Could not load your community.'
                                : 'No communities are available right now.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton(
                            onPressed: _load,
                            style: AppButtonStyles.secondary(c),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : _buildPicker(c),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPicker(AppColorScheme c) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: SingleChildScrollView(
            child: Material(
              color: c.card,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(color: c.border),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        'Choose Your Awalingo Community',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Parkinsans',
                          fontSize: 24,
                          fontWeight: FontWeight.w500,
                          color: c.foreground,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Rep your mother tongue.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: c.mutedForeground),
                    ),
                    const SizedBox(height: 24),
                    RadioGroup<int>(
                      groupValue: _selectedId,
                      onChanged: (id) => setState(() => _selectedId = id),
                      child: Column(
                        spacing: 12,
                        children: [
                          for (final language in _languages)
                            Opacity(
                              opacity: language.isSupported ? 1 : 0.5,
                              child: RadioListTile<int>(
                                value: language.id,
                                enabled: language.isSupported && !_saving,
                                controlAffinity:
                                    ListTileControlAffinity.trailing,
                                activeColor: c.foreground,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide(color: c.border),
                                ),
                                secondary: language.countryCode == null
                                    ? null
                                    : ExcludeSemantics(
                                        child: Text(
                                          countryFlagEmoji(
                                            language.countryCode!,
                                          ),
                                          style: const TextStyle(fontSize: 22),
                                        ),
                                      ),
                                title: Text(
                                  language.name,
                                  style: const TextStyle(
                                    fontFamily: 'Parkinsans',
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _selectedId == null || _saving ? null : _save,
          style: AppButtonStyles.primary(c).copyWith(
            minimumSize: const WidgetStatePropertyAll(Size.fromHeight(58)),
          ),
          child: Text(_saving ? 'Completing Profile…' : 'Complete Profile'),
        ),
      ],
    );
  }
}
