import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../theme/app_theme.dart';
import '../../services/auth_provider.dart';

// ── Model ─────────────────────────────────────────────────────────────────────

class AppNotification {
  final int id;
  final String type;
  final String title;
  final String message;
  final String? link;
  final bool isRead;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    this.link,
    required this.isRead,
    required this.createdAt,
  });

  AppNotification copyWith({bool? isRead}) => AppNotification(
        id: id, type: type, title: title, message: message,
        link: link, isRead: isRead ?? this.isRead, createdAt: createdAt,
      );

  factory AppNotification.fromRow(Map<String, dynamic> r) => AppNotification(
        id: r['id'] as int,
        type: r['type'] as String? ?? 'SYSTEM',
        title: r['title'] as String? ?? '',
        message: r['message'] as String? ?? '',
        link: r['link'] as String?,
        isRead: (r['isRead'] as bool?) ?? false,
        createdAt: DateTime.tryParse(r['createdAt'] as String? ?? '') ?? DateTime.now(),
      );
}

// ── Service ───────────────────────────────────────────────────────────────────

class _NotificationService {
  final SupabaseClient _db = Supabase.instance.client;

  Future<List<AppNotification>> load(String userId, {int limit = 50, int offset = 0}) async {
    final rows = await _db
        .from('notifications')
        .select('id, type, title, message, link, isRead, createdAt')
        .eq('userId', userId)
        .order('createdAt', ascending: false)
        .range(offset, offset + limit - 1);
    return rows.map(AppNotification.fromRow).toList();
  }

  Future<int> unreadCount(String userId) async {
    final rows = await _db
        .from('notifications')
        .select('id')
        .eq('userId', userId)
        .eq('isRead', false);
    return rows.length;
  }

  Future<void> markRead(String userId, int id) async {
    await _db.from('notifications').update({'isRead': true}).eq('id', id).eq('userId', userId);
  }

  Future<void> markAllRead(String userId) async {
    await _db.from('notifications').update({'isRead': true}).eq('userId', userId).eq('isRead', false);
  }

  Future<void> delete(String userId, int id) async {
    await _db.from('notifications').delete().eq('id', id).eq('userId', userId);
  }

  Future<void> deleteAll(String userId) async {
    await _db.from('notifications').delete().eq('userId', userId);
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _service = _NotificationService();
  bool _loading = true;
  List<AppNotification> _items = [];
  String? _userId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _userId = AuthProvider.of(context).user?.id;
    if (_loading) _load();
  }

  Future<void> _load() async {
    if (_userId == null) { setState(() => _loading = false); return; }
    try {
      final items = await _service.load(_userId!);
      if (mounted) setState(() { _items = items; _loading = false; });
    } catch (e) {
      debugPrint('Notifications load: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markRead(int id) async {
    if (_userId == null) return;
    setState(() { _items = _items.map((n) => n.id == id ? n.copyWith(isRead: true) : n).toList(); });
    await _service.markRead(_userId!, id);
  }

  Future<void> _markAllRead() async {
    if (_userId == null) return;
    setState(() { _items = _items.map((n) => n.copyWith(isRead: true)).toList(); });
    await _service.markAllRead(_userId!);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('All notifications marked as read.', style: TextStyle(fontFamily: 'Metropolis')),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
      ));
    }
  }

  Future<void> _delete(int id) async {
    if (_userId == null) return;
    setState(() { _items = _items.where((n) => n.id != id).toList(); });
    await _service.delete(_userId!, id);
  }

  Future<void> _clearAll() async {
    if (_userId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) {
        final c = AppColorScheme.of(context);
        return AlertDialog(
          backgroundColor: c.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Clear all notifications?', style: TextStyle(fontFamily: 'Parkinsans', fontSize: 17, color: c.foreground)),
          content: Text('This cannot be undone.', style: TextStyle(fontFamily: 'Metropolis', color: c.mutedForeground)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel', style: TextStyle(color: c.mutedForeground))),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Clear All', style: TextStyle(color: Color(0xFFEF4444))),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    setState(() => _items = []);
    await _service.deleteAll(_userId!);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    final unread = _items.where((n) => !n.isRead).length;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.card,
        elevation: 0,
        leading: BackButton(color: c.foreground),
        title: Text('Notifications', style: TextStyle(fontFamily: 'Parkinsans', fontSize: 17, fontWeight: FontWeight.w600, color: c.foreground)),
        actions: [
          if (_items.isNotEmpty)
            TextButton(
              onPressed: _markAllRead,
              child: Text('Mark all read', style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: c.primary)),
            ),
          if (_items.isNotEmpty)
            IconButton(
              icon: Icon(Icons.delete_outline, color: c.mutedForeground, size: 20),
              onPressed: _clearAll,
              tooltip: 'Clear all',
            ),
        ],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Divider(height: 1, color: c.border)),
      ),
      body: RefreshIndicator(
        onRefresh: () async { setState(() => _loading = true); await _load(); },
        color: c.primary,
        child: _loading
            ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
            : _items.isEmpty
                ? _EmptyState(c: c)
                : Column(
                    children: [
                      if (unread > 0)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          color: c.secondary,
                          child: Text(
                            '$unread unread notification${unread == 1 ? '' : 's'}',
                            style: TextStyle(fontFamily: 'Metropolis', fontSize: 12, color: c.mutedForeground),
                          ),
                        ),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                          itemCount: _items.length,
                          itemBuilder: (_, i) => _NotificationTile(
                            notification: _items[i],
                            c: c,
                            onTap: () => _markRead(_items[i].id),
                            onDelete: () => _delete(_items[i].id),
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}

// ── Tile ──────────────────────────────────────────────────────────────────────

class _NotificationTile extends StatelessWidget {
  final AppNotification notification;
  final AppColorScheme c;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _NotificationTile({required this.notification, required this.c, required this.onTap, required this.onDelete});

  IconData get _icon {
    switch (notification.type) {
      case 'WOTD_DAILY': return Icons.star_outline;
      case 'REQUEST_SUBMITTED': return Icons.edit_note_outlined;
      case 'REQUEST_APPROVED': return Icons.check_circle_outline;
      case 'REQUEST_REJECTED': return Icons.cancel_outlined;
      case 'ROLE_DAILY_ACTION': return Icons.notifications_outlined;
      default: return Icons.info_outline;
    }
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }

  @override
  Widget build(BuildContext context) {
    final isUnread = !notification.isRead;

    return Dismissible(
      key: ValueKey(notification.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: const Color(0xFFEF4444), borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 22),
      ),
      onDismissed: (_) => onDelete(),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isUnread ? c.primary.withValues(alpha: 0.06) : c.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isUnread ? c.primary.withValues(alpha: 0.2) : c.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: isUnread ? c.primary.withValues(alpha: 0.12) : c.secondary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(_icon, size: 18, color: isUnread ? c.primary : c.mutedForeground),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(notification.title,
                            style: TextStyle(
                                fontFamily: 'Metropolis',
                                fontSize: 14,
                                fontWeight: isUnread ? FontWeight.w600 : FontWeight.w500,
                                color: c.foreground)),
                      ),
                      if (isUnread)
                        Container(
                          width: 8, height: 8,
                          margin: const EdgeInsets.only(left: 6),
                          decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
                        ),
                    ]),
                    const SizedBox(height: 3),
                    Text(notification.message,
                        style: TextStyle(fontFamily: 'Metropolis', fontSize: 12, color: c.mutedForeground),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Text(_timeAgo(notification.createdAt),
                        style: TextStyle(fontFamily: 'Metropolis', fontSize: 11, color: c.mutedForeground)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final AppColorScheme c;
  const _EmptyState({required this.c});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.5,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(color: c.secondary, shape: BoxShape.circle),
                  child: Icon(Icons.notifications_none_outlined, size: 30, color: c.mutedForeground),
                ),
                const SizedBox(height: 16),
                Text('No notifications', style: TextStyle(fontFamily: 'Parkinsans', fontSize: 16, fontWeight: FontWeight.w600, color: c.foreground)),
                const SizedBox(height: 6),
                Text("You're all caught up!", style: TextStyle(fontFamily: 'Metropolis', fontSize: 13, color: c.mutedForeground)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
