import 'dart:async';

import 'package:flutter/material.dart';

import '../calculator/voice_services.dart';
import '../services/api_client.dart';
import '../services/app_services.dart';
import '../translator/indic_numbers.dart';
import '../translator/languages.dart';
import '../translator/transliterate.dart';
import '../translator/voice_language.dart';
import 'add_customer_screen.dart';
import 'customer_screen.dart';
import 'entry_form_screen.dart';
import 'udhaar_models.dart';
import 'udhaar_repository.dart';
import 'udhaar_widgets.dart';
import 'voice_udhaar.dart';

/// Opens the shop's udhaar book (Business home tile).
Widget openUdhaar(BuildContext context) => const UdhaarScreen();

/// The shop's udhaar book: total pending, every customer with their balance,
/// search, overdue filter, and adding by voice.
class UdhaarScreen extends StatefulWidget {
  const UdhaarScreen({this.now, super.key});

  /// For tests: pretend it is this moment.
  final DateTime? now;

  @override
  State<UdhaarScreen> createState() => _UdhaarScreenState();
}

class _UdhaarScreenState extends State<UdhaarScreen> {
  AppServices? _services;
  UdhaarBook? _book;
  bool _syncing = false;
  bool _offline = false;
  int _waiting = 0;
  _Filter _filter = _Filter.all;
  String _search = '';
  bool _listening = false;
  String _heard = '';
  AppLanguage _voiceLang = AppLanguage.english;

  AppServices get _app => _services!;
  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_services != null) return;
    _services = ServicesScope.of(context);
    _start();
  }

  @override
  void dispose() {
    if (_listening) unawaited(_app.voice.stop());
    super.dispose();
  }

  Future<void> _start() async {
    final saved = await _app.udhaar.savedBook();
    final waiting = await _app.udhaar.pendingCount();
    final lang = await readVoiceLanguage(_app.settings);
    if (!mounted) return;
    setState(() {
      _book = saved;
      _waiting = waiting;
      _voiceLang = lang;
    });
    await _sync();
  }

  Future<void> _pickVoiceLanguage() async {
    final picked = await pickVoiceLanguage(
      context,
      current: _voiceLang,
      settings: _app.settings,
      translator: _app.translator,
    );
    if (picked != null && mounted) setState(() => _voiceLang = picked);
  }

  /// What was said, as an udhaar entry. For Telugu/Hindi/Kannada/Tamil the
  /// words are first translated to English on the phone; names are also matched
  /// on the heard words written in English letters ("తేజ" -> "teja").
  /// Returns the result and the English text used (null when spoken in English).
  Future<(SpokenUdhaar?, String?)> _understand(String words) async {
    final customers = _book?.customers ?? const <UdhaarCustomer>[];
    if (_voiceLang == AppLanguage.english) return (parseSpokenUdhaar(words, customers), null);

    final english = await voiceToEnglish(
      context,
      words: words,
      language: _voiceLang,
      translator: _app.translator,
      onError: (m) => udNotify(context, m),
    );
    if (english == null) return (null, null);
    final fromEnglish = parseSpokenUdhaar(english, customers);
    var matches = fromEnglish?.matches ?? const <UdhaarCustomer>[];
    var sure = fromEnglish?.sure ?? true;
    var name = fromEnglish?.spokenName ?? '';
    if (matches.isEmpty) {
      final latin = transliterate(words);
      matches = customersIn(latin, customers);
      sure = namedExactly(latin, matches);
      name = sure ? '' : heardName(latin, matches);
    }
    // The amount read on the phone ("రెండు వందల యాభై" -> 250) is the most
    // reliable; the translation is only used when that finds no single amount.
    final amount = digitsAmount(numbersToDigits(words, _voiceLang)) ?? fromEnglish?.amountPaise;
    if (matches.isEmpty && amount == null) return (null, english);
    return (
      SpokenUdhaar(
        // Which way is read from the Telugu/Hindi words first: translation mixes it up.
        kind: nativeKind(words, _voiceLang) ?? fromEnglish?.kind ?? EntryKind.credit,
        amountPaise: amount,
        matches: matches,
        spokenName: matches.isEmpty || !sure ? name : '',
        sure: sure,
      ),
      english,
    );
  }

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      final report = await _app.udhaar.sendPending();
      final book = await _app.udhaar.freshBook();
      if (!mounted) return;
      setState(() {
        _book = book;
        _offline = false;
      });
      if (report.refused.isNotEmpty) {
        udNotify(context, 'An offline entry could not be saved: ${report.refused.first}');
      } else if (report.sent > 0) {
        udNotify(
          context,
          report.sent == 1
              ? '1 offline entry is now saved'
              : '${report.sent} offline entries are now saved',
        );
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.isNetwork) {
        final saved = await _app.udhaar.savedBook();
        if (!mounted) return;
        setState(() {
          _offline = true;
          _book = saved ?? _book;
        });
      } else {
        udNotify(
          context,
          e.isUnauthorized ? 'Your session has ended. Please log in again.' : e.message,
        );
      }
    } finally {
      final waiting = await _app.udhaar.pendingCount();
      if (mounted) {
        setState(() {
          _syncing = false;
          _waiting = waiting;
        });
      }
    }
  }

  List<UdhaarCustomer> get _shown {
    final all = _book?.customers ?? const <UdhaarCustomer>[];
    final q = _search.trim().toLowerCase();
    return [
      for (final c in all)
        if (switch (_filter) {
              _Filter.all => true,
              _Filter.overdue => c.isOverdue(_now),
              _Filter.disputes => c.dispute == Dispute.reported,
            } &&
            (q.isEmpty || c.name.toLowerCase().contains(q) || c.mobile.contains(q)))
          c,
    ];
  }

  Future<void> _openCustomer(UdhaarCustomer c) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => UdhaarCustomerScreen(customer: c, now: widget.now)),
    );
    if (mounted) await _sync();
  }

  Future<UdhaarCustomer?> _addCustomer({String name = ''}) async {
    final added = await Navigator.of(context).push<UdhaarCustomer>(
      MaterialPageRoute(builder: (_) => AddCustomerScreen(initialName: name)),
    );
    if (added != null && mounted) {
      udNotify(context, '${added.name} added to your udhaar book');
      await _sync();
    }
    return added;
  }

  Future<void> _addCustomerAndOpen() async {
    final added = await _addCustomer();
    if (added != null && mounted) await _openCustomer(added);
  }

  Future<void> _openEntry(
    UdhaarCustomer c,
    SpokenUdhaar spoken, {
    String heard = '',
    String? understood,
  }) async {
    // Use the latest balance for the limit check.
    final current = _book?.customers.where((x) => x.id == c.id).firstOrNull ?? c;
    final outcome = await Navigator.of(context).push<SaveOutcome>(
      MaterialPageRoute(
        builder: (_) => UdhaarEntryForm(
          customer: current,
          kind: spoken.kind,
          amountPaise: spoken.amountPaise,
          fromVoice: true,
          heard: heard,
          understood: understood,
          now: widget.now,
        ),
      ),
    );
    if (outcome == null || !mounted) return;
    await _sync();
    if (!mounted) return;
    udNotify(
      context,
      outcome == SaveOutcome.saved
          ? 'Saved for ${c.name}'
          : 'Saved on the phone for ${c.name}. It will sync when internet is back.',
    );
  }

  Future<void> _voice() async {
    if (_listening) {
      await _app.voice.stop();
      return;
    }
    setState(() {
      _listening = true;
      _heard = '';
    });
    try {
      final words = await _app.voice.listen(
        localeId: _voiceLang.speechLocale,
        onWords: (w) {
          if (mounted) setState(() => _heard = w);
        },
      );
      if (!mounted) return;
      setState(() => _listening = false);
      if (words.trim().isEmpty) {
        udNotify(context, 'Did not hear anything. Tap Speak and say: Ramesh 250 udhaar');
        return;
      }
      final (spoken, understood) = await _understand(words);
      if (!mounted) return;
      if (spoken == null) {
        udNotify(
          context,
          understood == null
              ? 'Could not understand "$words". Try: Ramesh 250 udhaar'
              : 'Could not understand "$words" ("$understood"). Say the name and the amount.',
        );
        return;
      }
      UdhaarCustomer? customer;
      if (spoken.matches.length == 1 && spoken.sure) {
        customer = spoken.matches.single;
      } else if (spoken.matches.isNotEmpty) {
        // Several, or a name that only sounds like one in the book ("Rajesh" / Ramesh).
        customer = await _whichCustomer(spoken.matches, newName: spoken.sure ? null : spoken.spokenName);
      } else {
        customer = await _offerNewCustomer(spoken.spokenName);
      }
      if (customer != null && mounted) {
        await _openEntry(customer, spoken, heard: words, understood: understood);
      }
    } on VoiceException catch (e) {
      if (mounted) udNotify(context, e.message);
    } finally {
      if (mounted) setState(() => _listening = false);
    }
  }

  /// [newName]: the name heard only sounds like [matches]; it may be a new customer.
  Future<UdhaarCustomer?> _whichCustomer(List<UdhaarCustomer> matches, {String? newName}) async {
    const addNew = 'new';
    final picked = await showDialog<Object>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(newName == null ? 'Which customer?' : 'Heard "$newName". Which customer?'),
        children: [
          for (final c in matches)
            SimpleDialogOption(
              key: Key('voice-pick-${c.id}'),
              onPressed: () => Navigator.of(context).pop(c),
              child: Row(
                children: [
                  UdAvatar(name: c.name, size: 36),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.name, style: udText(15, weight: FontWeight.w700)),
                        Text('+91 ${c.mobile}', style: udText(12, color: udBody)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (newName != null && newName.isNotEmpty)
            SimpleDialogOption(
              key: const Key('voice-pick-new'),
              onPressed: () => Navigator.of(context).pop(addNew),
              child: Row(
                children: [
                  const Icon(Icons.person_add_alt_1_rounded, color: udPurple),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Add "$newName" as a new customer', style: udText(15, weight: FontWeight.w700))),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked is UdhaarCustomer) return picked;
    if (picked == addNew && mounted) return _addCustomer(name: newName!);
    return null;
  }

  Future<UdhaarCustomer?> _offerNewCustomer(String name) async {
    final add = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Customer not found'),
        content: Text(
          name.isEmpty
              ? 'QBOX did not hear a customer name from your book.'
              : '"$name" is not in your udhaar book yet. Add them as a new customer?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('voice-add-new'),
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: udPurple),
            child: const Text('Add customer'),
          ),
        ],
      ),
    );
    if (add != true || !mounted) return null;
    return _addCustomer(name: name);
  }

  @override
  Widget build(BuildContext context) {
    final book = _book;
    final shown = _shown;
    final overdue = book?.customers.where((c) => c.isOverdue(_now)).length ?? 0;
    final overLimit = book?.customers.where((c) => c.overLimit).length ?? 0;
    final reports = book?.customers.where((c) => c.dispute == Dispute.reported).length ?? 0;
    return Scaffold(
      backgroundColor: udBackground,
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(title: 'Udhaar', subtitle: 'Credit book', busy: _syncing),
            if (_offline)
              const UdBanner(
                key: Key('udhaar-offline'),
                icon: Icons.wifi_off_rounded,
                text: 'Offline: showing your saved book. New entries are kept on the phone.',
              ),
            if (_waiting > 0)
              UdBanner(
                key: const Key('udhaar-waiting'),
                icon: Icons.cloud_upload_outlined,
                color: udPurple,
                background: udSoft,
                text: _waiting == 1
                    ? '1 entry waiting to sync'
                    : '$_waiting entries waiting to sync',
                actionLabel: 'Sync now',
                onAction: _syncing ? null : _sync,
              ),
            if (reports > 0)
              UdBanner(
                key: const Key('udhaar-disputes'),
                icon: Icons.report_problem_rounded,
                color: udDue,
                background: const Color(0xFFFFE9EB),
                text: reports == 1
                    ? '1 customer says this is not their number. Please check.'
                    : '$reports customers say this is not their number. Please check.',
                actionLabel: 'Show',
                onAction: () => setState(() => _filter = _Filter.disputes),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _sync,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  children: [
                    _TotalCard(
                      total: book?.totalPendingPaise ?? 0,
                      customers: book?.pendingCustomers ?? 0,
                      overdue: overdue,
                      overLimit: overLimit,
                      overdueOnly: _filter == _Filter.overdue,
                      onOverdue: () => setState(
                        () => _filter = _filter == _Filter.overdue ? _Filter.all : _Filter.overdue,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('udhaar-search'),
                      onChanged: (v) => setState(() => _search = v),
                      decoration: InputDecoration(
                        hintText: 'Search name or number',
                        prefixIcon: const Icon(Icons.search_rounded),
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(vertical: 0),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    if (_filter != _Filter.all)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _filter == _Filter.overdue
                                    ? 'Showing customers with no payment for $overdueDays+ days'
                                    : 'Showing customers who say this is not their number',
                                style: udText(12, color: udBody),
                              ),
                            ),
                            TextButton(
                              key: const Key('udhaar-show-all'),
                              onPressed: () => setState(() => _filter = _Filter.all),
                              child: const Text('Show all'),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 10),
                    if (book != null && book.customers.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Column(
                          children: [
                            const Icon(Icons.menu_book_rounded, size: 48, color: udPurple),
                            const SizedBox(height: 8),
                            Text(
                              'Your udhaar book is empty.\nTap "Add customer" to start.',
                              key: const Key('udhaar-empty'),
                              textAlign: TextAlign.center,
                              style: udText(14, color: udBody),
                            ),
                          ],
                        ),
                      )
                    else if (book != null && shown.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text('No customers match.', style: udText(14, color: udBody)),
                        ),
                      ),
                    for (final c in shown)
                      _CustomerTile(customer: c, now: _now, onTap: () => _openCustomer(c)),
                  ],
                ),
              ),
            ),
            if (_listening) _ListeningBar(heard: _heard, language: _voiceLang),
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                child: VoiceLanguageChip(
                  key: const Key('udhaar-voice-lang'),
                  language: _voiceLang,
                  onPressed: _listening ? null : _pickVoiceLanguage,
                ),
              ),
            ),
            UdBottomButtons(
              leftKey: const Key('udhaar-speak'),
              leftIcon: _listening ? Icons.stop_rounded : Icons.mic_rounded,
              leftLabel: _listening ? 'Stop' : 'Speak',
              leftColor: _listening ? udDue : udPurple,
              onLeft: _voice,
              rightKey: const Key('udhaar-add-customer'),
              rightIcon: Icons.person_add_alt_1_rounded,
              rightLabel: 'Add customer',
              onRight: _listening ? null : _addCustomerAndOpen,
            ),
          ],
        ),
      ),
    );
  }
}

enum _Filter { all, overdue, disputes }

class _TotalCard extends StatelessWidget {
  const _TotalCard({
    required this.total,
    required this.customers,
    required this.overdue,
    required this.overLimit,
    required this.overdueOnly,
    required this.onOverdue,
  });

  final int total;
  final int customers;
  final int overdue;
  final int overLimit;
  final bool overdueOnly;
  final VoidCallback onOverdue;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF651CE4), Color(0xFF8B4DFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Total udhaar pending', style: udText(13, color: Colors.white70)),
          Text(
            rupees(total),
            key: const Key('udhaar-total'),
            style: udText(34, weight: FontWeight.w800, color: Colors.white),
          ),
          Text(
            customers == 1 ? 'with 1 customer' : 'with $customers customers',
            style: udText(13, color: Colors.white),
          ),
          if (overdue > 0 || overLimit > 0) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (overdue > 0)
                  ActionChip(
                    key: const Key('udhaar-overdue-chip'),
                    avatar: Icon(
                      overdueOnly ? Icons.filter_alt_off_rounded : Icons.schedule_rounded,
                      size: 16,
                      color: udDue,
                    ),
                    label: Text('$overdue overdue'),
                    labelStyle: udText(12, weight: FontWeight.w700, color: udDue),
                    backgroundColor: Colors.white,
                    side: BorderSide.none,
                    onPressed: onOverdue,
                  ),
                if (overLimit > 0)
                  Chip(
                    avatar: const Icon(Icons.warning_amber_rounded, size: 16, color: udWarn),
                    label: Text('$overLimit over limit'),
                    labelStyle: udText(12, weight: FontWeight.w700, color: udWarn),
                    backgroundColor: Colors.white,
                    side: BorderSide.none,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CustomerTile extends StatelessWidget {
  const _CustomerTile({required this.customer, required this.now, required this.onTap});

  final UdhaarCustomer customer;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = customer;
    final days = c.daysOwing(now);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          key: Key('udhaar-customer-${c.id}'),
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                UdAvatar(name: c.name),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: udText(15, weight: FontWeight.w700),
                      ),
                      Text(
                        c.lastEntryAt == null ? '+91 ${c.mobile}' : 'Last: ${whenLabel(c.lastEntryAt!, now)}',
                        style: udText(12, color: udBody),
                      ),
                      if (days >= overdueDays || c.overLimit || c.dispute != Dispute.none)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              if (days >= overdueDays) UdBadge('No payment $days days'),
                              if (c.overLimit) const UdBadge('Over limit', color: udWarn),
                              if (c.dispute == Dispute.reported) const UdBadge('Says not their number'),
                              if (c.dispute == Dispute.unlinked)
                                const UdBadge('Unlinked: needs right number', color: udBody),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      c.balancePaise == 0 ? '₹0' : rupees(c.balancePaise),
                      style: udText(17, weight: FontWeight.w800, color: balanceColor(c.balancePaise)),
                    ),
                    Text(
                      c.balancePaise > 0 ? 'due' : (c.balancePaise < 0 ? 'advance' : 'settled'),
                      style: udText(11, color: udBody),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ListeningBar extends StatelessWidget {
  const _ListeningBar({required this.heard, required this.language});

  final String heard;
  final AppLanguage language;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('udhaar-listening'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: udSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCCBFF)),
      ),
      child: Row(
        children: [
          const Icon(Icons.graphic_eq_rounded, color: udPurple, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  language == AppLanguage.english ? 'Listening…' : 'Listening in ${language.nativeName}…',
                  style: udText(14, weight: FontWeight.w700, color: udPurple),
                ),
                Text(
                  heard.isEmpty ? 'Say: "Ramesh 250 udhaar" or "Ramesh paid 100"' : heard,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: udText(
                    heard.isEmpty ? 13 : 16,
                    weight: heard.isEmpty ? FontWeight.w500 : FontWeight.w700,
                    color: heard.isEmpty ? udBody : udInk,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
