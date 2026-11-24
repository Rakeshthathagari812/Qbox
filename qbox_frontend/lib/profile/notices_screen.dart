import 'package:flutter/material.dart';

import '../onboarding_draft.dart';
import '../services/api_client.dart';
import '../services/app_services.dart';
import '../udhaar/udhaar_models.dart' show whenLabel;
import '../udhaar/udhaar_widgets.dart';
import 'notices.dart';

/// The bell's list for one role. Tapping one opens the screen it is about.
class NoticesScreen extends StatefulWidget {
  const NoticesScreen({required this.role, this.now, super.key});

  final QboxRole role;
  final DateTime? now;

  @override
  State<NoticesScreen> createState() => _NoticesScreenState();
}

class _NoticesScreenState extends State<NoticesScreen> {
  AppServices? _services;
  Notices? _notices;
  String? _error;
  bool _busy = false;

  AppServices get _app => _services!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services != null) return;
    _services = ServicesScope.of(context);
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final notices = await _app.notices.all(widget.role);
      if (mounted) {
        setState(() {
          _notices = notices;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.isNetwork ? 'Offline: notifications need internet.' : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _readAll() async {
    try {
      await _app.notices.markRead(widget.role);
    } on ApiException catch (e) {
      if (mounted) udNotify(context, e.isNetwork ? 'This needs internet. Please try again.' : e.message);
      return;
    }
    if (mounted) await _load();
  }

  Future<void> _open(Notice notice) async {
    final notices = _notices;
    if (notice.unread && notices != null) {
      setState(() {
        _notices = Notices(
          unread: notices.unread - 1,
          off: notices.off,
          items: [for (final n in notices.items) n.id == notice.id ? n.read() : n],
        );
      });
      // Opening matters more than marking: it is tried again next time.
      _app.notices.markRead(widget.role, id: notice.id).catchError((Object _) {});
    }
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => notice.screen));
    if (mounted) await _load();
  }

  Future<void> _settings() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => NoticeSettingsScreen(role: widget.role)));
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final notices = _notices;
    final now = widget.now ?? DateTime.now();
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(
              title: 'Notifications',
              subtitle: notices == null || notices.unread == 0 ? null : '${notices.unread} new',
              busy: _busy,
              actions: [
                if (notices != null && notices.unread > 0)
                  IconButton(
                    key: const Key('notices-read-all'),
                    onPressed: _busy ? null : _readAll,
                    icon: const Icon(Icons.done_all_rounded, color: udPurple),
                    tooltip: 'Mark all as read',
                  ),
                if (NoticeType.of(widget.role).isNotEmpty)
                  IconButton(
                    key: const Key('notices-settings'),
                    onPressed: _settings,
                    icon: const Icon(Icons.settings_outlined, color: udPurple),
                    tooltip: 'Choose notifications',
                  ),
              ],
            ),
            if (_error != null)
              UdBanner(
                key: const Key('notices-error'),
                icon: Icons.wifi_off_rounded,
                text: _error!,
                actionLabel: 'Retry',
                onAction: _busy ? null : _load,
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    if (notices != null && notices.items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 64),
                        child: Column(
                          children: [
                            const Icon(Icons.notifications_none_rounded, size: 44, color: udBody),
                            const SizedBox(height: 8),
                            Text(
                              'Nothing new.',
                              key: const Key('notices-empty'),
                              style: udText(15, color: udBody),
                            ),
                          ],
                        ),
                      ),
                    for (final n in notices?.items ?? const <Notice>[]) _tile(n, now),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(Notice n, DateTime now) {
    final detail = n.detail ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: n.unread ? Colors.white : const Color(0xFFF4F1FA),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          key: Key('notice-${n.id}'),
          borderRadius: BorderRadius.circular(16),
          onTap: () => _open(n),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(n.icon, color: n.color, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(n.title, style: udText(14, weight: n.unread ? FontWeight.w700 : FontWeight.w500)),
                      if (detail.isNotEmpty)
                        Text(
                          detail,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: udText(12, color: udBody),
                        ),
                      const SizedBox(height: 2),
                      Text(whenLabel(n.at, now), style: udText(11, color: udBody)),
                      if (n.testMode) const UdBadge('Test money', color: udPurple),
                    ],
                  ),
                ),
                if (n.unread)
                  Container(
                    key: Key('notice-new-${n.id}'),
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(left: 8, top: 5),
                    decoration: const BoxDecoration(color: Color(0xFFE11D48), shape: BoxShape.circle),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Which notifications to show.
class NoticeSettingsScreen extends StatefulWidget {
  const NoticeSettingsScreen({required this.role, super.key});

  final QboxRole role;

  @override
  State<NoticeSettingsScreen> createState() => _NoticeSettingsScreenState();
}

class _NoticeSettingsScreenState extends State<NoticeSettingsScreen> {
  AppServices? _services;
  Set<NoticeType>? _off;
  String? _error;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services != null) return;
    _services = ServicesScope.of(context);
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final notices = await _services!.notices.all(widget.role);
      if (mounted) {
        setState(() {
          _off = notices.off;
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.isNetwork ? 'This needs internet.' : e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _set(NoticeType type, bool on) async {
    final before = _off!;
    final after = {...before};
    on ? after.remove(type) : after.add(type);
    setState(() {
      _off = after;
      _busy = true;
    });
    try {
      await _services!.notices.setOff(widget.role, after);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _off = before);
        udNotify(context, e.isNetwork ? 'This needs internet. Please try again.' : e.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final off = _off;
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(title: 'Choose notifications', busy: _busy),
            if (_error != null)
              UdBanner(
                icon: Icons.wifi_off_rounded,
                text: _error!,
                actionLabel: 'Retry',
                onAction: _busy ? null : _load,
              ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (NoticeType.of(widget.role).isEmpty)
                    Text('There is nothing to choose yet.', style: udText(14, color: udBody)),
                  if (off != null)
                    Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (final t in NoticeType.of(widget.role))
                            SwitchListTile(
                              key: Key('notice-type-${t.code}'),
                              value: !off.contains(t),
                              onChanged: _busy ? null : (on) => _set(t, on),
                              activeTrackColor: udPurple,
                              title: Text(t.label, style: udText(15, weight: FontWeight.w600)),
                              subtitle: Text(t.about, style: udText(12, color: udBody)),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
