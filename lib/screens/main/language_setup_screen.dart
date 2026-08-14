import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';

class LanguageSetupScreen extends StatefulWidget {
  const LanguageSetupScreen({super.key});

  @override
  State<LanguageSetupScreen> createState() => _LanguageSetupScreenState();
}

class _LanguageSetupScreenState extends State<LanguageSetupScreen> {
  final _db = Supabase.instance.client;
  bool _loading = true;
  bool _saving = false;
  List<({int id, String name})> _languages = [];
  int? _selectedId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = _db.auth.currentUser?.id;
    try {
      final langRows = await _db.from('languages').select('id, name').order('name');
      final langs = (langRows as List).map((r) => (id: r['id'] as int, name: r['name'] as String)).toList();

      int? currentId;
      if (userId != null) {
        final utl = await _db.from('user_target_languages').select('languageId').eq('userId', userId).maybeSingle();
        currentId = utl?['languageId'] as int?;
      }

      if (mounted) setState(() { _languages = langs; _selectedId = currentId; _loading = false; });
    } catch (e) {
      debugPrint('LanguageSetup load: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_selectedId == null) return;
    final userId = _db.auth.currentUser?.id;
    if (userId == null) return;
    setState(() => _saving = true);
    try {
      await _db.from('user_target_languages').upsert(
        {'userId': userId, 'languageId': _selectedId},
        onConflict: 'userId',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Community updated!', style: TextStyle(fontFamily: 'Metropolis')),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
        ));
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      debugPrint('LanguageSetup save: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to update. Please try again.', style: TextStyle(fontFamily: 'Metropolis')),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.card,
        elevation: 0,
        leading: BackButton(color: c.foreground),
        title: Text('Awalingo Community', style: TextStyle(fontFamily: 'Parkinsans', fontSize: 17, fontWeight: FontWeight.w600, color: c.foreground)),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Divider(height: 1, color: c.border)),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: c.primary, strokeWidth: 2))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                  child: Text(
                    'Choose your community language. This sets the language you help translate into.',
                    style: TextStyle(fontFamily: 'Metropolis', fontSize: 14, color: c.mutedForeground),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                    itemCount: _languages.length,
                    itemBuilder: (_, i) {
                      final lang = _languages[i];
                      final isSelected = _selectedId == lang.id;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedId = lang.id),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: isSelected ? c.primary.withValues(alpha: 0.08) : c.card,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? c.primary : c.border,
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(lang.name,
                                    style: TextStyle(
                                        fontFamily: 'Metropolis',
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        color: c.foreground)),
                              ),
                              if (isSelected) Icon(Icons.check_circle, color: c.primary, size: 20),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            onPressed: _selectedId == null || _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: c.primary,
              foregroundColor: c.primaryForeground,
              minimumSize: const Size(double.infinity, 52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save Community', style: TextStyle(fontFamily: 'Metropolis', fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }
}
