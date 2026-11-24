import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_services.dart';
import '../udhaar/udhaar_models.dart' show newClientRef, whenLabel;
import '../udhaar/udhaar_widgets.dart';
import 'checklist_screen.dart';
import 'note_screen.dart';
import 'page_models.dart';
import 'page_widgets.dart';
import 'pages_repository.dart';

/// Opens "Checklist & Notes" (Customer home tile).
Widget openChecklistNotes(BuildContext context) => const ChecklistNotesScreen();

/// The customer's lists (groceries…) and notes. Works offline.
class ChecklistNotesScreen extends StatefulWidget {
  const ChecklistNotesScreen({this.now, super.key});

  final DateTime? now;

  @override
  State<ChecklistNotesScreen> createState() => _ChecklistNotesScreenState();
}

class _ChecklistNotesScreenState extends State<ChecklistNotesScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this);
  AppServices? _services;
  String _search = '';

  PagesRepository get _pages => _services!.pages;
  bool get _onLists => _tabs.index == 0;

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() => setState(() {}));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services != null) return;
    _services = ServicesScope.of(context);
    unawaited(_pages.open());
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _new() async {
    if (_onLists) {
      final name = await askListName(context);
      if (name == null || !mounted) return;
      final list = QboxPage(ref: newClientRef(), isList: true, title: name, updatedAt: DateTime.now());
      _pages.put(list);
      await _open(list);
    } else {
      await _show(NoteScreen(pageRef: newClientRef()));
    }
  }

  Future<void> _open(QboxPage page) =>
      _show(page.isList ? ChecklistScreen(pageRef: page.ref) : NoteScreen(pageRef: page.ref));

  /// The screens answer with the page if it was deleted there.
  Future<void> _show(Widget screen) async {
    final deleted = await Navigator.of(context).push<QboxPage>(MaterialPageRoute(builder: (_) => screen));
    if (deleted == null || !mounted) return;
    notifyUndo(context, '"${deleted.name}" deleted', () => _pages.restore(deleted));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _pages,
      builder: (context, _) {
        final all = _pages.pages;
        return Scaffold(
          backgroundColor: udBackground,
          floatingActionButton: FloatingActionButton.extended(
            key: const Key('pages-new'),
            onPressed: _pages.ready ? _new : null,
            backgroundColor: udPurple,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_rounded),
            label: Text(_onLists ? 'New list' : 'New note'),
          ),
          body: SafeArea(
            child: Column(
              children: [
                UdHeader(title: 'Checklist & Notes', subtitle: 'Only you can see these', busy: _pages.busy),
                PagesBanner(_pages),
                TabBar(
                  controller: _tabs,
                  labelColor: udPurple,
                  indicatorColor: udPurple,
                  unselectedLabelColor: udBody,
                  labelStyle: udText(14, weight: FontWeight.w700),
                  unselectedLabelStyle: udText(14, weight: FontWeight.w600),
                  tabs: const [
                    Tab(key: Key('tab-lists'), text: 'Checklists'),
                    Tab(key: Key('tab-notes'), text: 'Notes'),
                  ],
                ),
                if (all.length > 4 || _search.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: TextField(
                      key: const Key('pages-search'),
                      onChanged: (v) => setState(() => _search = v),
                      style: udText(14),
                      decoration: InputDecoration(
                        hintText: 'Search',
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white,
                        prefixIcon: const Icon(Icons.search_rounded, color: udBody),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _tab(all.where((p) => p.isList).toList(), true),
                      _tab(all.where((p) => !p.isList).toList(), false),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _tab(List<QboxPage> pages, bool lists) {
    final shown = pages.where((p) => p.matches(_search)).toList();
    final empty = pages.isNotEmpty
        ? 'Nothing found.'
        : lists
        ? 'No lists yet.\nTap "New list" for groceries, medicines, school…'
        : 'No notes yet.\nTap "New note" to write or speak one.';
    return RefreshIndicator(
      onRefresh: _pages.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          if (shown.isEmpty && _pages.ready)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Text(
                empty,
                key: Key(lists ? 'lists-empty' : 'notes-empty'),
                textAlign: TextAlign.center,
                style: udText(14, color: udBody),
              ),
            ),
          for (final p in shown) _PageCard(page: p, now: widget.now ?? DateTime.now(), onTap: () => _open(p)),
        ],
      ),
    );
  }
}

class _PageCard extends StatelessWidget {
  const _PageCard({required this.page, required this.now, required this.onTap});

  final QboxPage page;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final total = page.items.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          key: Key('page-${page.ref}'),
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        page.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: udText(16, weight: FontWeight.w700),
                      ),
                    ),
                    if (page.pinned) const Icon(Icons.push_pin_rounded, size: 18, color: udPurple),
                  ],
                ),
                if (_preview.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      _preview,
                      maxLines: page.isList ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: udText(13, color: udBody),
                    ),
                  ),
                if (total > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: page.doneCount / total,
                        minHeight: 6,
                        color: udPaid,
                        backgroundColor: udSoft,
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (page.isList)
                      Expanded(
                        child: Text(
                          total == 0 ? 'No items yet' : doneLabel(page),
                          style: udText(12, weight: FontWeight.w600, color: page.left.isEmpty && total > 0 ? udPaid : udBody),
                        ),
                      ),
                    Text(whenLabel(page.updatedAt, now), style: udText(11, color: udBody)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _preview {
    if (page.isList) return page.left.take(4).map((i) => i.text).join(', ');
    final lines = page.text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);
    // Without a title, the first line is already the name.
    return (page.title.isEmpty ? lines.skip(1) : lines).take(2).join('\n');
  }
}
