import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../udhaar/udhaar_models.dart';
import '../udhaar/udhaar_widgets.dart';
import 'month_page.dart';
import 'record_form_screen.dart';
import 'transaction_models.dart';
import 'transactions_screen.dart';

/// Opens "Expenses Tracking" (Customer home tile).
Widget openExpenses(BuildContext context) => const ExpensesScreen();

/// Where the money went this month: the total against the budget, by category,
/// and every payment. Udhaar counts once, when it is paid.
class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({this.now, super.key});

  final DateTime? now;

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> with MonthPage {
  ExpenseCategory? _only;

  @override
  DateTime get now => widget.now ?? DateTime.now();

  @override
  void onMonthShown() {
    if (!history!.items.any((t) => t.isExpense && !t.hidden && _categoryOf(t) == _only)) _only = null;
  }

  static ExpenseCategory _categoryOf(Transaction t) => t.category ?? ExpenseCategory.other;

  Future<void> _editBudget() async {
    final answer = await showDialog<({int? paise})>(
      context: context,
      builder: (_) => _BudgetDialog(budget: history?.budgetPaise),
    );
    if (answer == null || !mounted) return;
    await change(
      () => app.transactions.api.setBudget(answer.paise),
      answer.paise == null ? 'Budget removed' : 'Budget saved',
    );
  }

  /// Another category, or left out. The payment itself is never changed.
  Future<void> _open(Transaction t) async {
    if (t.pending) {
      udNotify(context, 'Waiting for internet. Try again after it is sent.');
      return;
    }
    final choice = await showModalBottomSheet<({ExpenseCategory? category, bool hidden})>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${t.shopName}, ${rupees(t.amountPaise)}', style: udText(16, weight: FontWeight.w700)),
              const SizedBox(height: 12),
              CategoryChips(
                selected: _categoryOf(t),
                onSelected: (c) => Navigator.of(context).pop((category: c, hidden: false)),
              ),
              const Divider(height: 28),
              ListTile(
                key: const Key('expense-hide'),
                contentPadding: EdgeInsets.zero,
                leading: Icon(t.hidden ? Icons.add_circle_outline_rounded : Icons.remove_circle_outline_rounded),
                title: Text(t.hidden ? 'Count it in expenses' : 'Leave out of expenses'),
                subtitle: Text(t.hidden ? 'It is left out now' : 'It stays in Transaction History'),
                onTap: () => Navigator.of(context).pop((category: t.category, hidden: !t.hidden)),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    await change(
      () => app.transactions.api.mark(t.id, category: choice.category, hidden: choice.hidden),
      choice.hidden ? 'Left out' : 'Saved',
    );
  }

  @override
  Widget build(BuildContext context) {
    final all = (history?.items ?? const <Transaction>[]).where((t) => t.isExpense).toList();
    final counted = all.where((t) => !t.hidden).toList();
    final hidden = all.where((t) => t.hidden).toList();
    final categories = spentByCategory(all);
    final shown = _only == null ? counted : counted.where((t) => _categoryOf(t) == _only).toList();
    final spent = totalSpent(all);
    final same = possibleDuplicates(counted);
    return Scaffold(
      backgroundColor: udBackground,
      floatingActionButton: addButton(),
      body: SafeArea(
        child: Column(
          children: [
            UdHeader(title: 'Expenses', subtitle: 'Where your money goes', busy: busy),
            errorBanner(),
            monthBar(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  children: [
                    _totalCard(spent, history?.budgetPaise),
                    const SizedBox(height: 12),
                    if (history != null && all.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          'No spending in ${monthLabel(month)}.\nTap "Add payment" for cash or payments in other apps.',
                          key: const Key('expenses-empty'),
                          textAlign: TextAlign.center,
                          style: udText(14, color: udBody),
                        ),
                      ),
                    if (categories.isNotEmpty)
                      UdCard(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          children: [for (final (c, paise) in categories) _categoryRow(c, paise, spent)],
                        ),
                      ),
                    if (shown.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _only == null ? 'Payments' : _only!.label,
                              style: udText(16, weight: FontWeight.w700),
                            ),
                          ),
                          if (_only != null)
                            TextButton(
                              key: const Key('expenses-all'),
                              onPressed: () => setState(() => _only = null),
                              child: const Text('Show all'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      for (final t in shown) _tile(t, same[t.id]),
                    ],
                    if (hidden.isNotEmpty)
                      Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          key: const Key('expenses-hidden'),
                          tilePadding: EdgeInsets.zero,
                          title: Text('Left out (${hidden.length})', style: udText(14, weight: FontWeight.w600)),
                          children: [for (final t in hidden) _tile(t)],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(Transaction t, [Transaction? same]) => TransactionTile(
    item: t,
    now: now,
    onTap: () => _open(t),
    below: same == null ? null : sameQuestion(t, same),
  );

  Widget _totalCard(int spent, int? budget) {
    final left = budget == null ? 0 : budget - spent;
    final color = budget == null
        ? udInk
        : left < 0
        ? udDue
        : spent >= budget * 0.8
        ? udWarn
        : udPaid;
    return UdCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Spent', style: udText(13, color: udBody)),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              rupees(spent),
              key: const Key('expenses-total'),
              style: udText(34, weight: FontWeight.w800, color: color),
            ),
          ),
          if (budget != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: (spent / budget).clamp(0.0, 1.0),
                minHeight: 10,
                color: color,
                backgroundColor: udSoft,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              left < 0
                  ? '${rupees(left)} over your budget of ${rupees(budget)}'
                  : '${rupees(left)} left of ${rupees(budget)}',
              key: const Key('expenses-budget'),
              style: udText(13, weight: FontWeight.w600, color: color),
            ),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const Key('expenses-set-budget'),
              onPressed: busy ? null : _editBudget,
              child: Text(budget == null ? 'Set a monthly budget' : 'Change budget'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryRow(ExpenseCategory c, int paise, int spent) {
    final part = spent == 0 ? 0.0 : paise / spent;
    return Material(
      color: _only == c ? udSoft : Colors.transparent,
      child: InkWell(
        key: Key('expenses-${c.code}'),
        onTap: () => setState(() => _only = _only == c ? null : c),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(c.icon, color: c.color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(c.label, style: udText(14, weight: FontWeight.w600))),
                        Text(rupees(paise), style: udText(14, weight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: part,
                        minHeight: 6,
                        color: c.color,
                        backgroundColor: udSoft,
                      ),
                    ),
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

class _BudgetDialog extends StatefulWidget {
  const _BudgetDialog({required this.budget});

  final int? budget;

  @override
  State<_BudgetDialog> createState() => _BudgetDialogState();
}

class _BudgetDialogState extends State<_BudgetDialog> {
  late final _amount = TextEditingController(text: widget.budget == null ? '' : paiseToText(widget.budget!));
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _save() {
    final paise = parsePaise(_amount.text);
    if (paise == null || paise < 100) {
      setState(() => _error = 'Enter at least ₹1');
    } else if (paise > 1000000000) {
      setState(() => _error = 'Enter up to ₹1,00,00,000');
    } else {
      Navigator.of(context).pop((paise: paise));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Monthly budget'),
      content: TextField(
        key: const Key('budget-amount'),
        controller: _amount,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
        style: udText(26, weight: FontWeight.w800),
        decoration: InputDecoration(prefixText: '₹ ', errorText: _error),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        if (widget.budget != null)
          TextButton(
            key: const Key('budget-remove'),
            onPressed: () => Navigator.of(context).pop((paise: null)),
            child: const Text('Remove'),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          key: const Key('budget-save'),
          onPressed: _save,
          style: FilledButton.styleFrom(backgroundColor: udPurple),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
