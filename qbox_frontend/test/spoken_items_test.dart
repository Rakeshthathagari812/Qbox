import 'package:flutter_test/flutter_test.dart';
import 'package:qbox_app/customer/page_models.dart';
import 'package:qbox_app/customer/spoken_items.dart';
import 'package:qbox_app/stock/heard_items.dart';
import 'package:qbox_app/stock/stock_models.dart';
import 'package:qbox_app/stock/voice_stock.dart';
import 'package:qbox_app/translator/languages.dart';

List<String> show(List<PageItem> items) => [for (final i in items) i.qty.isEmpty ? i.text : '${i.text} | ${i.qty}'];

List<String> say(String words, [AppLanguage lang = AppLanguage.english, List<String> guesses = const []]) =>
    show(readSpokenItems(words, lang, guesses: guesses));

List<String> typed(String words) => show(readItems(words));

void main() {
  group('eggs, heard as x', () {
    test('put right next to a quantity', () {
      expect(say('x 12'), ['Eggs | 12']);
      expect(say('X 12'), ['Eggs | 12']);
      expect(say('ex 12'), ['Eggs | 12']);
      expect(say('x twelve'), ['Eggs | 12']);
      expect(say('eggs 12'), ['Eggs | 12']);
      expect(say('12 x'), ['Eggs | 12']);
      expect(say('x 1 dozen'), ['Eggs | 1 dozen']);
      expect(say('one dozen x'), ['Eggs | 1 dozen']);
      expect(say('a dozen eggs'), ['Eggs | 1 dozen']);
      expect(say('half a dozen x'), ['Eggs | half dozen']);
      expect(say('milk 2 litres x 12'), ['Milk | 2 litres', 'Eggs | 12']);
      expect(say('12 x milk 1 litre'), ['Eggs | 12', 'Milk | 1 litre']);
      expect(say('x'), ['Eggs']);
      expect(say('ఎక్స్ 12', AppLanguage.telugu), ['ఎగ్స్ | 12']);
    });

    test('left alone elsewhere', () {
      expect(fixHeard('pepsi 2 x 500 ml'), 'pepsi 2 x 500 ml');
      expect(fixHeard('chest x ray report'), 'chest x ray report');
      expect(fixHeard('250 x 3'), '250 x 3');
      expect(fixHeard('xerox paper'), 'xerox paper');
      expect(typed('Soap x 2').single.toLowerCase(), isNot(contains('eggs')));
    });

    test('in stock too', () {
      const eggs = StockItem(id: 1, name: 'Eggs', unit: StockUnit.piece, catalogCode: 'eggs');
      final s = parseSpokenStock('x 12 sold', AppLanguage.english, [eggs])!;
      expect((s.matches.single.name, s.qtyMilli, s.kind), ('Eggs', 12000, MoveKind.out));
    });
  });

  group('quantities', () {
    test('with a unit', () {
      expect(say('shampoo 5 packets'), ['Shampoo | 5 packets']);
      expect(say('shampoo five packets'), ['Shampoo | 5 packets']);
      expect(say('5 packets of shampoo'), ['Shampoo | 5 packets']);
      expect(say('half kg sugar'), ['Sugar | half kg']);
      expect(say('sugar half kg'), ['Sugar | half kg']);
      expect(say('one and a half kg rice'), ['Rice | 1.5 kg']);
      expect(say('rice 10kg'), ['Rice | 10 kg']);
      expect(say('Rice, 2 kg'), ['Rice | 2 kg']);
      expect(say('milk 500 ml 2 packets'), ['Milk | 500 ml 2 packets']);
      expect(say('rice 25 kg bag'), ['Rice | 25 kg bag']);
      expect(say('two fifty grams tea powder'), ['Tea powder | 250 grams']);
    });

    test('with no unit', () {
      expect(say('soap 3'), ['Soap | 3']);
      expect(say('12 eggs'), ['Eggs | 12']);
      expect(say('surf excel 2'), ['Surf excel | 2']);
      expect(say('5 star 10'), ['5 star | 10']);
      expect(say('seven up 2'), ['Seven up | 2']);
    });

    test('numbers in names stay', () {
      expect(say('7 up'), ['7 up']);
      expect(say('5 star'), ['5 star']);
      expect(say('50 50 biscuits'), ['50 50 biscuits']);
      expect(say('vitamin b 12'), ['Vitamin b 12']);
      expect(say('3 roses'), ['3 roses']);
      expect(say('paint 1 litre white'), ['Paint 1 litre white']);
    });

    test('in Telugu, Hindi, Kannada and Tamil', () {
      expect(say('బియ్యం 2 కిలోలు', AppLanguage.telugu), ['బియ్యం | 2 కిలోలు']);
      expect(say('బియ్యం రెండు కిలోలు', AppLanguage.telugu), ['బియ్యం | 2 కిలోలు']);
      expect(say('షాంపూ ఐదు ప్యాకెట్లు', AppLanguage.telugu), ['షాంపూ | 5 ప్యాకెట్లు']);
      expect(say('అర కిలో చక్కెర', AppLanguage.telugu).single, startsWith('చక్కెర | '));
      expect(say('గుడ్లు 12', AppLanguage.telugu), ['గుడ్లు | 12']);
      expect(say('గుడ్లు పన్నెండు కావాలి', AppLanguage.telugu), ['గుడ్లు | 12']);
      expect(say('చక్కెర 1 కిలో పాలు 2 లీటర్లు', AppLanguage.telugu), ['చక్కెర | 1 కిలో', 'పాలు | 2 లీటర్లు']);
      expect(say('चीनी दो किलो', AppLanguage.hindi), ['चीनी | 2 किलो']);
      expect(say('अंडे 12 चाहिए', AppLanguage.hindi), ['अंडे | 12']);
      expect(say('ಅಕ್ಕಿ 5 ಕಿಲೋ', AppLanguage.kannada), ['ಅಕ್ಕಿ | 5 ಕಿಲೋ']);
      expect(say('அரிசி 3 கிலோ', AppLanguage.tamil), ['அரிசி | 3 கிலோ']);
      expect(typed('బియ్యం 2 కిలోలు'), ['బియ్యం | 2 కిలోలు']);
    });

    test('typed: a number at the end, but not years, phone numbers or vitamin b 12', () {
      expect(typed('eggs 12'), ['Eggs | 12']);
      expect(typed('7 up'), ['7 up']);
      expect(typed('Vitamin b 12'), ['Vitamin b 12']);
      expect(typed('Calendar 2027'), ['Calendar 2027']);
      expect(typed('Call 9876543210'), ['Call 9876543210']);
      expect(typed('50 50'), ['50 50']);
    });
  });

  group('many in one go', () {
    test('split at the quantities', () {
      expect(say('rice 2 kg milk 1 litre shampoo 5 packets'), ['Rice | 2 kg', 'Milk | 1 litre', 'Shampoo | 5 packets']);
      expect(say('2 kg rice 1 litre milk and 5 packets shampoo'), ['Rice | 2 kg', 'Milk | 1 litre', 'Shampoo | 5 packets']);
      expect(say('rice 2 kg and milk 1 litre'), ['Rice | 2 kg', 'Milk | 1 litre']);
      expect(say('eggs 12 bread 2 milk 1 litre'), ['Eggs | 12', 'Bread | 2', 'Milk | 1 litre']);
      expect(say('rice 2 kg maggi'), ['Rice | 2 kg', 'Maggi']);
      expect(say('2 packets milk 500 ml'), ['Milk | 2 packets 500 ml']);
      expect(say('milk, rice 2 kg, onions'), ['Milk', 'Rice | 2 kg', 'Onions']);
    });

    test('with no quantities', () {
      expect(say('milk and eggs'), ['Milk', 'Eggs']);
      expect(say('milk eggs bread'), ['Milk', 'Eggs', 'Bread']);
      expect(say('butter milk'), ['Butter milk']);
      expect(say('2 packets butter milk 500 ml'), ['Butter milk | 2 packets 500 ml']);
      expect(say('milk and brown bread'), ['Milk', 'Brown bread']);
      expect(say('salt and vinegar chips'), ['Salt and vinegar chips']);
    });
  });

  test('"add ..." and "... please" are not part of the item', () {
    expect(say('add shampoo 5 packets'), ['Shampoo | 5 packets']);
    expect(say('please add eggs 12 to my list'), ['Eggs | 12']);
    expect(say('add x 12'), ['Eggs | 12']);
    expect(say('i want milk 1 litre please'), ['Milk | 1 litre']);
    expect(say('add'), ['Add']);
    expect(say('? !'), isEmpty);
  });

  test("the phone's other guesses: only one that sounds the same and is a shop item", () {
    expect(say('dull 2 kg', AppLanguage.english, ['dull 2 kg', 'toor dal 2 kg']), ['Dull | 2 kg']);
    expect(say('peneer 2', AppLanguage.english, ['peneer 2', 'paneer 2']), ['Paneer | 2']);
    expect(say('peneer 2', AppLanguage.english, ['paneer 20']), ['Peneer | 2']); // another quantity
    expect(say('horlicks 1', AppLanguage.english, ['garlic 1']), ['Horlicks | 1']); // another thing
  });

  test('what is said back', () {
    PageItem i(String t, [String q = '']) => makeItem(t, q);
    expect(addedSays([i('shampoo', '5 packets')], AppLanguage.english), 'Shampoo 5 packets added successfully');
    expect(addedSays([i('rice', '2 kg'), i('milk')], AppLanguage.english), 'Rice 2 kg, Milk added successfully');
    expect(addedSays([for (var n = 0; n < 6; n++) i('a$n')], AppLanguage.english), '6 items added successfully');
    expect(alreadySays(['Rice', 'Dal'], AppLanguage.english), 'Rice, Dal are already in the list');
    for (final lang in AppLanguage.values) {
      expect(addedSays([i('salt')], lang), contains('Salt'));
      expect(notUnderstoodSays(lang), isNotEmpty);
    }
  });
}
