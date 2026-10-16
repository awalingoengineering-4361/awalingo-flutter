import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../screens/main/notifications_screen.dart';

const _kNotificationPreviewLimit = 5;

// A real State owns the request lifecycle; async callbacks never outlive it.
class NotificationPreviewMenu extends StatefulWidget {
  final String userId;
  final NotificationService service;
  final ValueChanged<int> onUnreadChanged;
  final ValueChanged<AppNotification> onOpen;
  final VoidCallback onViewAll;

  const NotificationPreviewMenu({
    super.key,
    required this.userId,
    required this.service,
    required this.onUnreadChanged,
    required this.onOpen,
    required this.onViewAll,
  });

  @override
  State<NotificationPreviewMenu> createState() =>
      _NotificationPreviewMenuState();
}

class _NotificationPreviewMenuState extends State<NotificationPreviewMenu> {
  List<AppNotification> _preview = [];
  int _unread = 0;
  bool _loading = true;
  bool _loadFailed = false;
  bool _updating = false;
  String? _actionError;

  // A popped popup stays mounted while its reverse animation runs.
  bool get _isActive => mounted && ModalRoute.of(context)?.isCurrent == true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final results = await Future.wait([
        widget.service.load(widget.userId, limit: _kNotificationPreviewLimit),
        widget.service.unreadCount(widget.userId),
      ]);
      if (!_isActive) return;
      setState(() {
        _preview = results[0] as List<AppNotification>;
        _unread = results[1] as int;
        _loading = false;
      });
      widget.onUnreadChanged(_unread);
    } catch (_) {
      if (!_isActive) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  Future<void> _markAllRead() async {
    if (_updating) return;
    setState(() {
      _updating = true;
      _actionError = null;
    });
    try {
      await widget.service.markAllRead(widget.userId);
      if (!_isActive) return;
      setState(() {
        _preview = _preview.map((n) => n.copyWith(isRead: true)).toList();
        _unread = 0;
      });
      widget.onUnreadChanged(0);
    } catch (_) {
      if (!_isActive) return;
      setState(() => _actionError = 'Unable to mark notifications as read.');
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _open(AppNotification notification) async {
    if (_updating) return;
    if (!notification.isRead) {
      setState(() {
        _updating = true;
        _actionError = null;
      });
      try {
        await widget.service.markRead(widget.userId, notification.id);
        if (!_isActive) return;
        setState(() {
          _preview = _preview
              .map(
                (n) => n.id == notification.id ? n.copyWith(isRead: true) : n,
              )
              .toList();
          _unread = _unread > 0 ? _unread - 1 : 0;
        });
        widget.onUnreadChanged(_unread);
      } catch (_) {
        if (!_isActive) return;
        setState(() => _actionError = 'Unable to mark notifications as read.');
        return;
      } finally {
        if (mounted) setState(() => _updating = false);
      }
    }
    if (_isActive) widget.onOpen(notification);
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColorScheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Notifications',
                  style: TextStyle(
                    fontFamily: 'Parkinsans',
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: c.foreground,
                  ),
                ),
              ),
              if (!_loading && !_loadFailed && _unread > 0)
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: _updating ? null : _markAllRead,
                  child: Text(
                    'Mark all as read',
                    style: TextStyle(
                      fontFamily: 'Metropolis',
                      fontSize: 12,
                      color: c.primary,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Divider(height: 1, color: c.border),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_loadFailed)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  'Unable to load notifications.',
                  style: TextStyle(
                    fontFamily: 'Metropolis',
                    fontSize: 13,
                    color: c.mutedForeground,
                  ),
                ),
                TextButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          )
        else if (_preview.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No notifications',
              style: TextStyle(
                fontFamily: 'Metropolis',
                fontSize: 13,
                color: c.mutedForeground,
              ),
            ),
          )
        else
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (var i = 0; i < _preview.length; i++)
                    _NotificationPreviewTile(
                      notification: _preview[i],
                      c: c,
                      isLast: i == _preview.length - 1,
                      onTap: () => _open(_preview[i]),
                    ),
                ],
              ),
            ),
          ),
        if (_actionError != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              _actionError!,
              style: const TextStyle(
                fontFamily: 'Metropolis',
                fontSize: 12,
                color: AppColors.error,
              ),
            ),
          ),
        if (!_loading && !_loadFailed && _preview.isNotEmpty) ...[
          Divider(height: 1, color: c.border),
          InkWell(
            onTap: widget.onViewAll,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'View all notifications',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Metropolis',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: c.primary,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// Preview row inside the notification dropdown — mirrors the item markup
// in NotificationBell.tsx (title + unread dot, 2-line message, relative time).
class _NotificationPreviewTile extends StatelessWidget {
  final AppNotification notification;
  final AppColorScheme c;
  final bool isLast;
  final VoidCallback onTap;

  const _NotificationPreviewTile({
    required this.notification,
    required this.c,
    required this.isLast,
    required this.onTap,
  });

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
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUnread
              ? c.primary.withValues(alpha: 0.06)
              : Colors.transparent,
          border: isLast ? null : Border(bottom: BorderSide(color: c.border)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    notification.title,
                    style: TextStyle(
                      fontFamily: 'Metropolis',
                      fontSize: 13,
                      fontWeight: isUnread ? FontWeight.w600 : FontWeight.w500,
                      color: c.foreground,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isUnread)
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(left: 6, top: 2),
                    decoration: BoxDecoration(
                      color: c.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              notification.message,
              style: TextStyle(
                fontFamily: 'Metropolis',
                fontSize: 11.5,
                color: c.mutedForeground,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 3),
            Text(
              _timeAgo(notification.createdAt),
              style: TextStyle(
                fontFamily: 'Metropolis',
                fontSize: 10.5,
                color: c.mutedForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
