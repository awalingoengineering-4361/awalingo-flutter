import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_provider.dart';

// ── Model ─────────────────────────────────────────────────────────────────────

class _WordRequest {
  final int id;
  final String word;
  final String status;
  final String languageName;
  final DateTime createdAt;
  const _WordRequest({required this.id, required this.word, required this.status,
      required this.languageName, required this.createdAt});
}

// ── Service ───────────────────────────────────────────────────────────────────

class _CuratorRequestsService {
  final SupabaseClient _db = Supabase.instance.client;

  Future<List<_WordRequest>> loadPending(int? communityLangId) async {
    var query = _db
        .from('translation_requests')
        .select('id, word, status, userId, sourceLanguageId, createdAt, language:languages!sourceLanguageId(name)')
        .eq('status', 'PENDING');

    if (communityLangId != null) {
      query = query.eq('sourceLanguageId', communityLangId);
    }

    final rows = await query.order('createdAt', ascending: false).limit(50);
    return rows.map((r) {
      final lang = r['language'] as Map<String, dynamic>?;
      return _WordRequest(
        id: r['id'] as int,
        word: r['word'] as String,
        status: r['status'] as String,
        languageName: lang?['name'] as String? ?? 'Unknown',
        createdAt: DateTime.tryParse(r['createdAt'] as String? ?? '') ?? DateTime.now(),
      );
    }).toList();
  }

  Future<void> approve(String userId, int requestId) async {
    await _db.from('translation_requests').update({
      'status': 'APPROVED',
      'reviewedBy': userId,
      'reviewedAt': DateTime.now().toIso8601String(),
    }).eq('id', requestId);
  }

  Future<void> reject(String userId, int requestId, String reason) async {
    await _db.from('translation_requests').update({
      'status': 'REJECTED',
      'rejectionReason': reason,
      'reviewedBy': userId,
      'reviewedAt': DateTime.now().toIso8601String(),
    }).eq('id', requestId);
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class CuratorRequestsScreen extends StatefulWidget {
  const CuratorRequestsScreen({super.key});

  @override
  State<CuratorRequestsScreen> createState() => _CuratorRequestsScreenState();
}

class _CuratorRequestsScreenState extends State<CuratorRequestsScreen> {
  final _service = _CuratorRequestsService();
  bool _loading = true;
  List<_WordRequest> _requests = [];
  int? _communityLangId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) _load();
  }

  Future<void> _load() async {
    final userId = AuthProvider.of(context).user?.id;
    if (userId == null) { setState(() => _loading = false); return; }
    try {
      final utl = await Supabase.instance.client
          .from('user_target_languages').select('languageId').eq('userId', userId).maybeSingle();
      _communityLangId = utl?['languageId'] as int?;
      final requests = await _service.loadPending(_communityLangId);
      if (mounted) setState(() { _requests = requests; _loading = false; });
    } catch (e) {
      debugPrint('CuratorRequests load: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _approve(int requestId) async {
    final userId = AuthProvider.of(context).user?.id;
    if (userId == null) return;
    setState(() { _requests = _requests.where((r) => r.id != requestId).toList(); });
    await _service.approve(userId, requestId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Request approved.', style: TextStyle(fontFamily: 'Metropolis')),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
      ));
    }
  }

  Future<void> _showRejectDialog(int requestId) async {
    final c = AppColorScheme.of(context);
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: c.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Reject request?', style: TextStyle(fontFamily: 'Parkinsans', fontSize: 16, color: c.foreground)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Optionally provide a reason:', style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: c.mutedForeground)),
          const SizedBox(height: 10),
          TextField(
            controller: ctrl,
            decoration: InputDecoration(
              hintText: 'Reason (optional)',
              hintStyle: TextStyle(fontFamily: 'Metropolis', color: c.mutedForeground),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
              contentPadding: const EdgeInsets.all(12),
            ),
            style: TextStyle(fontFamily: 'Metropolis', color: c.foreground),
            maxLines: 2,
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel', style: TextStyle(color: c.mutedForeground))),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reject', style: TextStyle(color: Color(0xFFEF4444))),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    final userId = AuthProvider.of(context).user?.id;
    if (userId == null) return;
    setState(() { _requests = _requests.where((r) => r.id != requestId).toList(); });
    await _service.reject(userId, requestId, ctrl.text.trim());
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Request rejected.', style: TextStyle(fontFamily: 'Metropolis')),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
      ));
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
        title: Text('Word Requests', style: TextStyle(fontFamily: 'Parkinsans', fontSize: 17, fontWeight: FontWeight.w600, color: c.foreground)),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Divider(height: 1, color: c.border)),
      ),
      body: RefreshIndicator(
        onRefresh: () async { setState(() => _loading = true); await _load(); },
        color: c.primary,
        child: _loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : _requests.isEmpty
                ? _EmptyState(c: c)
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                    itemCount: _requests.length,
                    itemBuilder: (_, i) => _RequestTile(
                      request: _requests[i],
                      c: c,
                      onApprove: () => _approve(_requests[i].id),
                      onReject: () => _showRejectDialog(_requests[i].id),
                    ),
                  ),
      ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  final _WordRequest request;
  final AppColorScheme c;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  const _RequestTile({required this.request, required this.c, required this.onApprove, required this.onReject});

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 0) return '${diff.inDays}d ago';
    if (diff.inHours > 0) return '${diff.inHours}h ago';
    return '${diff.inMinutes}m ago';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(request.word, style: TextStyle(fontFamily: 'Parkinsans', fontSize: 17, fontWeight: FontWeight.w600, color: c.foreground)),
              const SizedBox(height: 2),
              Text('${request.languageName} • ${_timeAgo(request.createdAt)}',
                  style: TextStyle(fontFamily: 'Metropolis', fontSize: 12, color: c.mutedForeground)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: c.secondary, borderRadius: BorderRadius.circular(100)),
            child: Text('Pending', style: TextStyle(fontFamily: 'Metropolis', fontSize: 11, color: c.mutedForeground)),
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: onReject,
              style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFEF4444),
                  side: const BorderSide(color: Color(0xFFEF4444)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(vertical: 10)),
              child: const Text('Reject', style: TextStyle(fontFamily: 'Metropolis', fontWeight: FontWeight.w500)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton(
              onPressed: onApprove,
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF22C55E),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(vertical: 10)),
              child: const Text('Approve', style: TextStyle(fontFamily: 'Metropolis', fontWeight: FontWeight.w500)),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final AppColorScheme c;
  const _EmptyState({required this.c});

  @override
  Widget build(BuildContext context) {
    return ListView(children: [
      SizedBox(
        height: MediaQuery.of(context).size.height * 0.5,
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(color: c.secondary, shape: BoxShape.circle),
              child: Icon(Icons.check_circle_outline, size: 30, color: c.mutedForeground),
            ),
            const SizedBox(height: 16),
            Text('All clear!', style: TextStyle(fontFamily: 'Parkinsans', fontSize: 16, fontWeight: FontWeight.w600, color: c.foreground)),
            const SizedBox(height: 6),
            Text('No pending requests.', style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: c.mutedForeground)),
          ]),
        ),
      ),
    ]);
  }
}
