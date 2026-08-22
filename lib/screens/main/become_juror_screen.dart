import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_provider.dart';
import '../../services/permissions.dart';

// ── Models ────────────────────────────────────────────────────────────────────

class _PracticeNeo {
  final int id;
  final String text;
  final String type;
  final String termText;
  final String termMeaning;
  const _PracticeNeo({required this.id, required this.text, required this.type, required this.termText, required this.termMeaning});
}

// ── Service ───────────────────────────────────────────────────────────────────

class _BecomeJurorService {
  final SupabaseClient _db = Supabase.instance.client;

  Future<_PracticeNeo?> loadPracticeNeo(String userId) async {
    final utl = await _db.from('user_target_languages').select('languageId').eq('userId', userId).maybeSingle();
    final langId = utl?['languageId'] as int?;
    if (langId == null) return null;

    // Get a neo to practice rating
    final neoRows = await _db
        .from('neos')
        .select('id, text, type, termId')
        .eq('languageId', langId)
        .neq('userId', userId)
        .gt('ratingCount', 0)
        .limit(10);

    if (neoRows.isEmpty) return null;
    neoRows.shuffle();
    final neo = neoRows.first;
    final termId = neo['termId'] as int;

    final termRow = await _db.from('terms').select('text, meaning').eq('id', termId).maybeSingle();

    return _PracticeNeo(
      id: neo['id'] as int,
      text: neo['text'] as String,
      type: neo['type'] as String? ?? 'POPULAR',
      termText: termRow?['text'] as String? ?? '',
      termMeaning: termRow?['meaning'] as String? ?? '',
    );
  }

  Future<bool> hasExistingApplication(String userId) async {
    final row = await _db
        .from('juror_applications')
        .select('id')
        .eq('userId', userId)
        .maybeSingle();
    return row != null;
  }

  Future<({String? name, String? email})> prefillFromProfile(String userId) async {
    final row = await _db.from('user_profile').select('name').eq('userId', userId).maybeSingle();
    final name = row?['name'] as String?;
    final authUser = _db.auth.currentUser;
    return (name: name, email: authUser?.email);
  }

  Future<void> submitApplication({
    required String userId,
    required String name,
    required String email,
    required String phone,
    required int? practiceNeoId,
    required int? practiceRating,
  }) async {
    await _db.from('juror_applications').upsert({
      'userId': userId,
      'name': name,
      'email': email,
      'phone': phone,
      'agreementAccepted': true,
      'status': 'PENDING',
      if (practiceNeoId != null) 'practiceNeoId': practiceNeoId,
      if (practiceRating != null) 'practiceRating': practiceRating,
    }, onConflict: 'userId');
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class BecomeJurorScreen extends StatefulWidget {
  const BecomeJurorScreen({super.key});

  @override
  State<BecomeJurorScreen> createState() => _BecomeJurorScreenState();
}

class _BecomeJurorScreenState extends State<BecomeJurorScreen> {
  final _service = _BecomeJurorService();
  bool _loading = true;
  bool _submitting = false;
  int _step = 0; // 0 = practice, 1 = form, 2 = done

  _PracticeNeo? _practiceNeo;
  int? _practiceRating;
  bool _alreadyApplied = false;

  // Mirrors neolingo's requireCuratorApplicant(): only CURATORs may view or
  // submit a juror application — enforced there before even loading the
  // page's data, not just on submit.
  bool _isCurator = false;

  // Form
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl = TextEditingController();
  late final TextEditingController _emailCtrl = TextEditingController();
  late final TextEditingController _phoneCtrl = TextEditingController();
  bool _agreementAccepted = false;

  static const _emojis = [
    (char: '❌', label: 'Reject', value: 0),
    (char: '😓', label: 'Weak', value: 1),
    (char: '😕', label: 'Unclear', value: 2),
    (char: '😐', label: 'Okay', value: 3),
    (char: '😁', label: 'Good', value: 4),
    (char: '😍', label: 'Excellent', value: 5),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final userId = AuthProvider.of(context).user?.id;
    if (userId == null) { setState(() => _loading = false); return; }
    try {
      final role = await fetchUserRole(Supabase.instance.client, userId);
      final isCurator = role == 'CURATOR';
      if (!isCurator) {
        if (mounted) setState(() { _isCurator = false; _loading = false; });
        return;
      }

      final results = await Future.wait([
        _service.loadPracticeNeo(userId),
        _service.hasExistingApplication(userId),
        _service.prefillFromProfile(userId),
      ]);
      final neo = results[0] as _PracticeNeo?;
      final hasApp = results[1] as bool;
      final prefill = results[2] as ({String? name, String? email});

      if (mounted) {
        _nameCtrl.text = prefill.name ?? '';
        _emailCtrl.text = prefill.email ?? '';
        setState(() {
          _isCurator = true;
          _practiceNeo = neo;
          _alreadyApplied = hasApp;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('BecomeJuror load: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (!_isCurator) return;
    if (!_formKey.currentState!.validate()) return;
    if (!_agreementAccepted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please accept the agreement to continue.', style: TextStyle(fontFamily: 'Metropolis')),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    final userId = AuthProvider.of(context).user?.id;
    if (userId == null) return;
    setState(() => _submitting = true);
    try {
      await _service.submitApplication(
        userId: userId,
        name: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        phone: _phoneCtrl.text.trim(),
        practiceNeoId: _practiceNeo?.id,
        practiceRating: _practiceRating,
      );
      if (mounted) setState(() { _step = 2; _submitting = false; });
    } catch (e) {
      debugPrint('BecomeJuror submit: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Submission failed. Please try again.', style: TextStyle(fontFamily: 'Metropolis')),
          behavior: SnackBarBehavior.floating,
        ));
        setState(() => _submitting = false);
      }
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
        title: Text('Become a Juror', style: TextStyle(fontFamily: 'Parkinsans', fontSize: 17, fontWeight: FontWeight.w600, color: c.foreground)),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Divider(height: 1, color: c.border)),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: c.primary, strokeWidth: 2))
          : !_isCurator
              ? _NotCuratorView(c: c)
              : _alreadyApplied && _step != 2
              ? _AlreadyAppliedView(c: c)
              : _step == 0
                  ? _PracticeStep(
                      neo: _practiceNeo,
                      rating: _practiceRating,
                      emojis: _emojis,
                      c: c,
                      onRate: (v) => setState(() => _practiceRating = v),
                      onContinue: () => setState(() => _step = 1),
                    )
                  : _step == 1
                      ? _FormStep(
                          formKey: _formKey,
                          nameCtrl: _nameCtrl,
                          emailCtrl: _emailCtrl,
                          phoneCtrl: _phoneCtrl,
                          agreementAccepted: _agreementAccepted,
                          submitting: _submitting,
                          c: c,
                          onAgreementChanged: (v) => setState(() => _agreementAccepted = v ?? false),
                          onSubmit: _submit,
                        )
                      : _DoneView(c: c),
    );
  }
}

// ── Practice Step ─────────────────────────────────────────────────────────────

class _PracticeStep extends StatelessWidget {
  final _PracticeNeo? neo;
  final int? rating;
  final List<({String char, String label, int value})> emojis;
  final AppColorScheme c;
  final ValueChanged<int> onRate;
  final VoidCallback onContinue;

  const _PracticeStep({required this.neo, required this.rating, required this.emojis, required this.c, required this.onRate, required this.onContinue});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: c.secondary, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)),
            child: Row(children: [
              Icon(Icons.info_outline, size: 18, color: c.mutedForeground),
              const SizedBox(width: 10),
              Expanded(child: Text('Step 1 of 2 — Practice Rating\nRate this neo suggestion to demonstrate your judgment.',
                  style: TextStyle(fontFamily: 'Metropolis', fontSize: 12, color: c.mutedForeground))),
            ]),
          ),
          const SizedBox(height: 16),

          if (neo != null) ...[
            // Term card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Word to translate', style: TextStyle(fontFamily: 'Metropolis', fontSize: 11, fontWeight: FontWeight.w600, color: c.mutedForeground, letterSpacing: 0.5)),
                const SizedBox(height: 6),
                Text(neo!.termText, style: TextStyle(fontFamily: 'Parkinsans', fontSize: 20, fontWeight: FontWeight.w600, color: c.foreground)),
                if (neo!.termMeaning.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(neo!.termMeaning, style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: c.mutedForeground)),
                ],
              ]),
            ),
            const SizedBox(height: 12),

            // Neo to rate
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Community suggestion', style: TextStyle(fontFamily: 'Metropolis', fontSize: 11, fontWeight: FontWeight.w600, color: c.mutedForeground, letterSpacing: 0.5)),
                const SizedBox(height: 6),
                Text(neo!.text, style: TextStyle(fontFamily: 'Parkinsans', fontSize: 22, fontWeight: FontWeight.w600, color: c.foreground)),
                const SizedBox(height: 16),
                Text('How would you rate this suggestion?', style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: c.mutedForeground)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: emojis.map((e) => GestureDetector(
                    onTap: () => onRate(e.value),
                    child: AnimatedScale(
                      scale: rating == e.value ? 1.3 : 1.0,
                      duration: const Duration(milliseconds: 150),
                      child: Column(children: [
                        Text(e.char, style: const TextStyle(fontSize: 28)),
                        const SizedBox(height: 4),
                        Text(e.label, style: TextStyle(fontFamily: 'Metropolis', fontSize: 10, color: c.mutedForeground)),
                      ]),
                    ),
                  )).toList(),
                ),
              ]),
            ),
          ] else
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)),
              child: Text('No practice suggestions available for your language yet. You can still apply.',
                  style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: c.mutedForeground)),
            ),

          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: onContinue,
            style: ElevatedButton.styleFrom(
                backgroundColor: c.primary,
                foregroundColor: c.primaryForeground,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('Continue to Application', style: TextStyle(fontFamily: 'Metropolis', fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Form Step ─────────────────────────────────────────────────────────────────

class _FormStep extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController nameCtrl, emailCtrl, phoneCtrl;
  final bool agreementAccepted;
  final bool submitting;
  final AppColorScheme c;
  final ValueChanged<bool?> onAgreementChanged;
  final VoidCallback onSubmit;

  const _FormStep({
    required this.formKey, required this.nameCtrl, required this.emailCtrl,
    required this.phoneCtrl, required this.agreementAccepted, required this.submitting,
    required this.c, required this.onAgreementChanged, required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(color: c.secondary, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)),
            child: Text('Step 2 of 2 — Application Form\nA member of our team will review your application.',
                style: TextStyle(fontFamily: 'Metropolis', fontSize: 12, color: c.mutedForeground)),
          ),
          _FormField(label: 'Full Name', controller: nameCtrl, c: c, validator: (v) => (v?.trim().length ?? 0) < 2 ? 'Name is required' : null),
          const SizedBox(height: 12),
          _FormField(label: 'Email Address', controller: emailCtrl, c: c, keyboardType: TextInputType.emailAddress,
              validator: (v) => (v?.contains('@') ?? false) ? null : 'Enter a valid email'),
          const SizedBox(height: 12),
          _FormField(label: 'Phone Number', controller: phoneCtrl, c: c, keyboardType: TextInputType.phone,
              validator: (v) => (v?.trim().length ?? 0) < 5 ? 'Phone number is required' : null),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () => onAgreementChanged(!agreementAccepted),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Checkbox(value: agreementAccepted, onChanged: onAgreementChanged, activeColor: c.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text('I agree to uphold community standards, rate fairly, and commit to regular participation as a Juror.',
                      style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: c.foreground)),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: submitting ? null : onSubmit,
            style: ElevatedButton.styleFrom(
                backgroundColor: c.primary,
                foregroundColor: c.primaryForeground,
                minimumSize: const Size(double.infinity, 52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: submitting
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Submit Application', style: TextStyle(fontFamily: 'Metropolis', fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _FormField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final AppColorScheme c;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  const _FormField({required this.label, required this.controller, required this.c, this.keyboardType, this.validator});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, fontWeight: FontWeight.w500, color: c.foreground)),
      const SizedBox(height: 6),
      TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        validator: validator,
        style: TextStyle(fontFamily: 'Metropolis', color: c.foreground),
        decoration: InputDecoration(
          filled: true,
          fillColor: c.card,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.primary)),
        ),
      ),
    ]);
  }
}

class _DoneView extends StatelessWidget {
  final AppColorScheme c;
  const _DoneView({required this.c});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(color: const Color(0xFF22C55E).withValues(alpha: 0.1), shape: BoxShape.circle),
              child: const Icon(Icons.check_circle_outline, size: 36, color: Color(0xFF22C55E)),
            ),
            const SizedBox(height: 20),
            Text('Application submitted!', style: TextStyle(fontFamily: 'Parkinsans', fontSize: 20, fontWeight: FontWeight.w700, color: c.foreground)),
            const SizedBox(height: 8),
            Text('Our team will review your application. You\'ll receive a notification when a decision is made.',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Metropolis', fontSize: 14, color: c.mutedForeground)),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: ElevatedButton.styleFrom(
                  backgroundColor: c.primary,
                  foregroundColor: c.primaryForeground,
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              child: const Text('Done', style: TextStyle(fontFamily: 'Metropolis', fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotCuratorView extends StatelessWidget {
  final AppColorScheme c;
  const _NotCuratorView({required this.c});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(color: c.secondary, shape: BoxShape.circle),
              child: Icon(Icons.lock_outline, size: 30, color: c.mutedForeground),
            ),
            const SizedBox(height: 20),
            Text('Not Available', style: TextStyle(fontFamily: 'Parkinsans', fontSize: 18, fontWeight: FontWeight.w600, color: c.foreground)),
            const SizedBox(height: 8),
            Text('Only curators can apply to become a Juror. Become a curator first to unlock this.',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Metropolis', fontSize: 14, color: c.mutedForeground)),
          ],
        ),
      ),
    );
  }
}

class _AlreadyAppliedView extends StatelessWidget {
  final AppColorScheme c;
  const _AlreadyAppliedView({required this.c});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(color: c.secondary, shape: BoxShape.circle),
              child: Icon(Icons.schedule, size: 30, color: c.mutedForeground),
            ),
            const SizedBox(height: 20),
            Text('Application Pending', style: TextStyle(fontFamily: 'Parkinsans', fontSize: 18, fontWeight: FontWeight.w600, color: c.foreground)),
            const SizedBox(height: 8),
            Text('You have already submitted a Juror application. Our team will review it and notify you of the decision.',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'Metropolis', fontSize: 14, color: c.mutedForeground)),
          ],
        ),
      ),
    );
  }
}
