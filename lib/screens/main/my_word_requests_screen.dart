import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_provider.dart';
import '../../widgets/word_request_tabs.dart';
import 'request_screen.dart';

// Ports src/actions/word-requests.ts + MyWordRequestsList.tsx: lets a user
// track the status of every word they've requested, filterable by status,
// paginated the same way (10 per page).

const _pageSize = 10;
const _statuses = ['PENDING', 'REVIEWED', 'APPROVED', 'REJECTED'];

class _StatusDetail {
  final String label;
  final String description;
  final Color light, dark, border, borderDark;
  const _StatusDetail(this.label, this.description, this.light, this.dark, this.border, this.borderDark);
}

const _statusDetails = <String, _StatusDetail>{
  'PENDING': _StatusDetail(
    'Pending', 'Waiting for a curator to review it.',
    Color(0xFFB45309), Color(0xFFFCD34D), Color(0xFFFFFBEB), Color(0xFF78350F),
  ),
  'REVIEWED': _StatusDetail(
    'Under Review', 'Reviewed by a curator and awaiting final approval.',
    Color(0xFF0369A1), Color(0xFF7DD3FC), Color(0xFFF0F9FF), Color(0xFF0C4A6E),
  ),
  'APPROVED': _StatusDetail(
    'Approved', 'Approved for the community dictionary workflow.',
    Color(0xFF047857), Color(0xFF6EE7B7), Color(0xFFECFDF5), Color(0xFF064E3B),
  ),
  'REJECTED': _StatusDetail(
    'Rejected', 'Not approved in its current form.',
    Color(0xFFBE123C), Color(0xFFFDA4AF), Color(0xFFFFF1F2), Color(0xFF4C0519),
  ),
};

// ── Model ─────────────────────────────────────────────────────────────────────

class _WordRequestItem {
  final int id;
  final String word;
  final String? meaning;
  final String status;
  final String? rejectionReason;
  final DateTime createdAt;
  final String sourceLanguageName;
  final String targetLanguageName;
  final String partOfSpeechName;

  const _WordRequestItem({
    required this.id,
    required this.word,
    this.meaning,
    required this.status,
    this.rejectionReason,
    required this.createdAt,
    required this.sourceLanguageName,
    required this.targetLanguageName,
    required this.partOfSpeechName,
  });

  factory _WordRequestItem.fromRow(Map<String, dynamic> r) => _WordRequestItem(
        id: r['id'] as int,
        word: r['word'] as String? ?? '',
        meaning: r['meaning'] as String?,
        status: r['status'] as String? ?? 'PENDING',
        rejectionReason: r['rejectionReason'] as String?,
        createdAt: DateTime.tryParse(r['createdAt'] as String? ?? '') ?? DateTime.now(),
        sourceLanguageName: (r['sourceLanguage'] as Map<String, dynamic>?)?['name'] as String? ?? '',
        targetLanguageName: (r['targetLanguage'] as Map<String, dynamic>?)?['name'] as String? ?? '',
        partOfSpeechName: (r['partOfSpeech'] as Map<String, dynamic>?)?['name'] as String? ?? '',
      );
}

class _WordRequestsPage {
  final List<_WordRequestItem> requests;
  final Map<String, int> statusCounts;
  final int totalCount;
  final int filteredCount;
  final int page;
  final int pageCount;

  const _WordRequestsPage({
    required this.requests,
    required this.statusCounts,
    required this.totalCount,
    required this.filteredCount,
    required this.page,
    required this.pageCount,
  });
}

// ── Service ───────────────────────────────────────────────────────────────────

class _MyWordRequestsService {
  final SupabaseClient _db = Supabase.instance.client;

  Future<_WordRequestsPage> load(String userId, {required String status, required int page}) async {
    final safePage = page < 1 ? 1 : page;

    var query = _db
        .from('translation_requests')
        .select('id, word, meaning, status, rejectionReason, createdAt, '
            'sourceLanguage:languages!sourceLanguageId(name), '
            'targetLanguage:languages!targetLanguageId(name), '
            'partOfSpeech:part_of_speech!partOfSpeechId(name)')
        .eq('userId', userId);
    if (status != 'ALL') query = query.eq('status', status);

    final rows = await query
        .order('createdAt', ascending: false)
        .range((safePage - 1) * _pageSize, safePage * _pageSize - 1);

    final allStatusRows = await _db.from('translation_requests').select('status').eq('userId', userId);
    final statusCounts = <String, int>{for (final s in _statuses) s: 0};
    for (final r in allStatusRows) {
      final s = r['status'] as String?;
      if (s != null && statusCounts.containsKey(s)) statusCounts[s] = statusCounts[s]! + 1;
    }
    final totalCount = statusCounts.values.fold(0, (a, b) => a + b);
    final filteredCount = status == 'ALL' ? totalCount : (statusCounts[status] ?? 0);
    final pageCount = filteredCount == 0 ? 0 : (filteredCount / _pageSize).ceil();

    return _WordRequestsPage(
      requests: rows.map(_WordRequestItem.fromRow).toList(),
      statusCounts: statusCounts,
      totalCount: totalCount,
      filteredCount: filteredCount,
      page: safePage,
      pageCount: pageCount,
    );
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class MyWordRequestsScreen extends StatefulWidget {
  const MyWordRequestsScreen({super.key});

  @override
  State<MyWordRequestsScreen> createState() => _MyWordRequestsScreenState();
}

class _MyWordRequestsScreenState extends State<MyWordRequestsScreen> {
  final _service = _MyWordRequestsService();
  bool _loading = true;
  String _status = 'ALL';
  int _page = 1;
  _WordRequestsPage? _data;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) _load();
  }

  Future<void> _load() async {
    final userId = AuthProvider.of(context).user?.id;
    if (userId == null) { setState(() => _loading = false); return; }
    setState(() => _loading = true);
    try {
      final data = await _service.load(userId, status: _status, page: _page);
      if (mounted) setState(() { _data = data; _loading = false; });
    } catch (e) {
      debugPrint('MyWordRequests load: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setFilter(String status) {
    if (_status == status) return;
    setState(() { _status = status; _page = 1; });
    _load();
  }

  void _setPage(int page) {
    setState(() => _page = page);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.card,
        elevation: 0,
        leading: BackButton(color: c.foreground),
        title: Text('Word Requests', style: TextStyle(fontFamily: 'Parkinsans', fontSize: 17, fontWeight: FontWeight.w600, color: c.foreground)),
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Divider(height: 1, color: c.border)),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: c.primary, strokeWidth: 2))
          : RefreshIndicator(
              onRefresh: _load,
              color: c.primary,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    WordRequestTabs(activeIsHistory: true, requestCount: _data?.totalCount),
                    const SizedBox(height: 16),

                    // ── Section header + "Request a Word" ─────────────────
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('My Word Requests', style: TextStyle(fontFamily: 'Parkinsans', fontSize: 18, fontWeight: FontWeight.w600, color: c.foreground)),
                              const SizedBox(height: 4),
                              Text('Follow each word from submission through community review.',
                                  style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: c.mutedForeground)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const RequestScreen())),
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('Request', style: TextStyle(fontFamily: 'Metropolis', fontWeight: FontWeight.w600)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: c.primary,
                            foregroundColor: c.primaryForeground,
                            shape: const StadiumBorder(),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            elevation: 0,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    if ((_data?.totalCount ?? 0) > 0) _buildFilters(c),
                    const SizedBox(height: 16),

                    if ((_data?.requests.isEmpty ?? true))
                      _buildEmptyState(c)
                    else
                      ...(_data!.requests.map((r) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _RequestCard(request: r, c: c, isDark: isDark),
                          ))),

                    if ((_data?.pageCount ?? 0) > 1) _buildPagination(c),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildFilters(AppColorScheme c) {
    final data = _data!;
    final filters = [
      ('ALL', 'All', data.totalCount),
      ('PENDING', 'Pending', data.statusCounts['PENDING'] ?? 0),
      ('REVIEWED', 'Under Review', data.statusCounts['REVIEWED'] ?? 0),
      ('APPROVED', 'Approved', data.statusCounts['APPROVED'] ?? 0),
      ('REJECTED', 'Rejected', data.statusCounts['REJECTED'] ?? 0),
    ];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final (value, label, count) = filters[i];
          final active = _status == value;
          return GestureDetector(
            onTap: () => _setFilter(value),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: active ? c.foreground : c.card,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(color: active ? c.foreground : c.border),
              ),
              alignment: Alignment.center,
              child: Text('$label $count',
                  style: TextStyle(
                    fontFamily: 'Metropolis',
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: active ? c.background : c.mutedForeground,
                  )),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(AppColorScheme c) {
    final isFirstRequest = (_data?.totalCount ?? 0) == 0;
    final filteredLabel = _status == 'ALL' ? 'word' : (_statusDetails[_status]?.label.toLowerCase() ?? 'word');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: c.border, style: BorderStyle.solid),
      ),
      child: Column(
        children: [
          Text(
            isFirstRequest ? 'No word requests yet' : 'No $filteredLabel requests',
            style: TextStyle(fontFamily: 'Parkinsans', fontSize: 16, fontWeight: FontWeight.w600, color: c.foreground),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            isFirstRequest
                ? 'Request a word you want the community to translate and track its progress here.'
                : 'Choose another status to see your other requests.',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: c.mutedForeground),
          ),
          if (isFirstRequest) ...[
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const RequestScreen())),
              style: ElevatedButton.styleFrom(
                backgroundColor: c.primary,
                foregroundColor: c.primaryForeground,
                shape: const StadiumBorder(),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                elevation: 0,
              ),
              child: const Text('Request Your First Word', style: TextStyle(fontFamily: 'Metropolis', fontWeight: FontWeight.w600)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPagination(AppColorScheme c) {
    final data = _data!;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          data.page > 1
              ? OutlinedButton(
                  onPressed: () => _setPage(data.page - 1),
                  style: OutlinedButton.styleFrom(shape: const StadiumBorder(), foregroundColor: c.foreground, side: BorderSide(color: c.border)),
                  child: const Text('Previous', style: TextStyle(fontFamily: 'Metropolis', fontWeight: FontWeight.w500)),
                )
              : const SizedBox(),
          Text('Page ${data.page} of ${data.pageCount}', style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: c.mutedForeground)),
          data.page < data.pageCount
              ? OutlinedButton(
                  onPressed: () => _setPage(data.page + 1),
                  style: OutlinedButton.styleFrom(shape: const StadiumBorder(), foregroundColor: c.foreground, side: BorderSide(color: c.border)),
                  child: const Text('Next', style: TextStyle(fontFamily: 'Metropolis', fontWeight: FontWeight.w500)),
                )
              : const SizedBox(),
        ],
      ),
    );
  }
}

// ── Request card ──────────────────────────────────────────────────────────────

class _RequestCard extends StatelessWidget {
  final _WordRequestItem request;
  final AppColorScheme c;
  final bool isDark;
  const _RequestCard({required this.request, required this.c, required this.isDark});

  String _fmtDate(DateTime dt) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final details = _statusDetails[request.status] ?? _statusDetails['PENDING']!;
    final rejectionReason = request.status == 'REJECTED' ? request.rejectionReason : null;
    final statusColor = isDark ? details.dark : details.light;
    final statusBg = isDark ? details.borderDark.withValues(alpha: 0.3) : details.border;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(request.word, style: TextStyle(fontFamily: 'Parkinsans', fontFamilyFallback: kContentFontFallback, fontSize: 16, fontWeight: FontWeight.w600, color: c.foreground)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: c.secondary, borderRadius: BorderRadius.circular(100)),
                          child: Text(request.partOfSpeechName, style: TextStyle(fontFamily: 'Metropolis', fontSize: 11, color: c.mutedForeground)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('${request.sourceLanguageName} → ${request.targetLanguageName}',
                        style: TextStyle(fontFamily: 'Metropolis', fontSize: 12, color: c.mutedForeground)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(100),
                  border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                ),
                child: Text(details.label, style: TextStyle(fontFamily: 'Metropolis', fontSize: 11, fontWeight: FontWeight.w600, color: statusColor)),
              ),
            ],
          ),

          if ((request.meaning ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(request.meaning!, style: TextStyle(fontFamily: 'Metropolis', fontFamilyFallback: kContentFontFallback, fontSize: 14, color: c.foreground.withValues(alpha: 0.85))),
          ],

          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(color: c.secondary, borderRadius: BorderRadius.circular(14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(details.description, style: TextStyle(fontFamily: 'Metropolis', fontSize: 12, fontWeight: FontWeight.w500, color: c.foreground.withValues(alpha: 0.8))),
                if (rejectionReason != null && rejectionReason.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('Reason: $rejectionReason', style: TextStyle(fontFamily: 'Metropolis', fontSize: 12, color: statusColor)),
                ],
              ],
            ),
          ),

          const SizedBox(height: 10),
          Text('Submitted ${_fmtDate(request.createdAt)}', style: TextStyle(fontFamily: 'Metropolis', fontSize: 11, color: c.mutedForeground.withValues(alpha: 0.7))),
        ],
      ),
    );
  }
}
