/// The words Ask QBOX knows, in the app's five languages: what is asked about
/// (concepts), the answers, and examples to try.
library;

import '../onboarding_draft.dart';
import '../translator/languages.dart';

/// What a question is about. Several can be in one question.
enum Concept {
  help,
  owe,
  most,
  late,
  stock,
  low,
  value,
  money,
  came,
  confirm,
  supplier,
  order,
  spend,
  budget,
  calendar,
  remindMe,
  list,
  pay,
  given,
  connect,
  tomorrow,
}

// (English words, also those said in English letters; beginnings in Indian scripts,
// or the whole word when it ends with a space).
const _words = <Concept, (Set<String>, List<String>)>{
  Concept.help: (
    {'help', 'what can you do', 'how to ask'},
    ['సహాయ', 'मदद', 'ಸಹಾಯ', 'உதவி'],
  ),
  Concept.owe: (
    {
      'udhaar', 'udhar', 'udaar', 'udhari', 'due', 'dues', 'owe', 'owes', 'owed', 'owing', 'pending', 'balance',
      'baki', 'baaki', 'bakaya', 'credit', 'khata', 'appu', 'debt', 'to get', 'to collect', 'unpaid', 'not paid', 'not paying',
      'not given', 'has to give', 'have to give', 'should give', 'must give', 'to be paid', 'has to pay', 'have to pay',
      'should pay', 'must pay', 'need to pay', 'needs to pay', 'to pay me',
    },
    [
      'ఉధార', 'ఉద్దార', 'ఉద్దెర', 'అప్పు', 'బాకీ', 'బాకి', 'బకాయ', 'ఇవ్వాలి', 'రావాలి', 'రావాల్సి',
      'उधार', 'नहीं दिए', 'नहीं दिया', 'नहीं दी', 'बाकी', 'बाक़ी', 'बकाया', 'कर्ज', 'देना', 'देने', 'लेना', 'लेने',
      'ಉದ್ರಿ', 'ಉದ್ದರಿ', 'ಉಧಾರ', 'ಬಾಕಿ', 'ಸಾಲ', 'ಕೊಡಬೇಕು', 'ಬರಬೇಕು',
      'கடன்', 'பாக்கி', 'உதார', 'நிலுவை', 'தர வேண்டும்', 'வரவேண்டிய',
    ],
  ),
  Concept.most: (
    {'most', 'highest', 'biggest', 'top', 'maximum', 'more', 'who', 'evaru', 'kaun'},
    ['ఎక్కువ', 'ఎవరు', 'ज्यादा', 'ज़्यादा', 'सबसे', 'कौन', 'ಹೆಚ್ಚು', 'ಜಾಸ್ತಿ', 'ಯಾರು', 'அதிக', 'யார்'],
  ),
  Concept.late: (
    {'late', 'overdue', 'old', 'long', 'delayed', 'delay'},
    ['ఆలస్య', 'పాత', 'देर', 'पुरान', 'लेट', 'ತಡ', 'ಹಳೆ', 'தாமத', 'பழைய'],
  ),
  Concept.stock: (
    {'stock', 'stocks', 'goods', 'item', 'items', 'inventory', 'maal', 'saruku', 'left', 'remaining', 'product', 'products'},
    [
      'స్టాక్', 'సరుకు', 'నిల్వ', 'వస్తువు', 'स्टॉक', 'स्टाक', 'माल', 'सामान', 'ಸ್ಟಾಕ್', 'ಸರಕು', 'ದಾಸ್ತಾನು',
      'ವಸ್ತು', 'ஸ்டாக்', 'சரக்கு', 'இருப்பு', 'பொருள்', 'பொருட்',
    ],
  ),
  Concept.low: (
    {
      'low', 'less', 'finish', 'finished', 'finishing', 'shortage', 'short', 'running', 'takkuva', 'kam', 'out of stock',
      'no stock', 'empty', 'buy', 'purchase', 'reorder',
    },
    ['తక్కువ', 'అయిపో', 'కొనాలి', 'खरीदना', 'ख़रीदना', 'ಖರೀದಿಸಬೇಕು', 'வாங்க வேண்டும்', 'कम ', 'खत्म', 'ख़त्म', 'ಕಡಿಮೆ', 'ಖಾಲಿ', 'ಮುಗಿ', 'குறை', 'தீர்ந்'],
  ),
  Concept.value: (
    {'worth', 'value', 'valued'},
    ['విలువ', 'कीमत', 'क़ीमत', 'मूल्य', 'ಮೌಲ್ಯ', 'மதிப்பு'],
  ),
  Concept.money: (
    {
      'payment', 'payments', 'money', 'paisa', 'paise', 'dabbulu', 'cash', 'upi',
    },
    [
      'చెల్లింపు', 'పేమెంట్', 'డబ్బు', 'पेमेंट', 'भुगतान', 'पैसा', 'पैसे', 'ಪೇಮೆಂಟ್', 'ಪಾವತಿ', 'ಹಣ', 'ದುಡ್ಡು',
      'பேமெண்ட்', 'பணம்', 'கட்டண',
    ],
  ),
  // Money that moved: it is never about what is still owed.
  Concept.came: (
    {
      'paid', 'received', 'receive', 'collection', 'collected', 'income', 'earned', 'earn', 'earning', 'earnings',
      'sales', 'sale', 'came', 'did i pay', 'i pay', 'anyone pay', 'we get', 'i get',
    },
    [
      'చెల్లించ', 'వసూలు', 'వసూళ్', 'వచ్చాయి', 'వచ్చింది', 'అమ్మకా', 'సంపాద', 'वसूली', 'मिले', 'मिला', 'कमाई', 'बिक्री',
      'ವಸೂಲಿ', 'ಬಂತು', 'ಬಂದಿದೆ', 'ಮಾರಾಟ', 'ಗಳಿಕೆ', 'வசூல்', 'வந்தது', 'விற்பனை', 'வருமான',
    ],
  ),
  Concept.confirm: (
    {'confirm', 'check', 'waiting', 'verify', 'approve'},
    ['నిర్ధార', 'చూడాల', 'जाँच', 'जांच', 'पुष्टि', 'ಪರಿಶೀಲ', 'ಖಚಿತ', 'சரிபார்', 'உறுதி'],
  ),
  Concept.supplier: (
    {'supplier', 'suppliers', 'distributor', 'distributors', 'wholesaler', 'wholesale', 'vendor', 'vendors'},
    ['సప్లయర్', 'సప్లైయర్', 'సరఫరా', 'सप्लायर', 'थोक', 'आपूर्ति', 'ಸಪ್ಲೈಯರ್', 'ಸಪ್ಲಯರ್', 'ಪೂರೈಕೆ', 'சப்ளையர்', 'வழங்குந'],
  ),
  Concept.order: ({'order', 'orders', 'ordered'}, ['ఆర్డర్', 'ऑर्डर', 'आर्डर', 'ಆರ್ಡರ್', 'ஆர்டர்']),
  Concept.spend: (
    {'spend', 'spent', 'spending', 'waste', 'wasted', 'expense', 'expenses', 'expenditure', 'kharch', 'kharchu'},
    ['ఖర్చ', 'खर्च', 'ख़र्च', 'ಖರ್ಚು', 'செலவ', 'செலவு'],
  ),
  Concept.budget: ({'budget'}, ['బడ్జెట్', 'बजट', 'ಬಜೆಟ್', 'பட்ஜெட்']),
  Concept.calendar: (
    {
      'calendar', 'reminder', 'reminders', 'event', 'events', 'schedule', 'meeting', 'meetings', 'plan', 'plans',
      'festival', 'festivals', 'holiday', 'holidays',
    },
    [
      'క్యాలెండర్', 'రిమైండర్', 'కార్యక్రమ', 'పండుగ', 'కేలండర్', 'कैलेंडर', 'रिमाइंडर', 'कार्यक्रम', 'त्योहार',
      'ಕ್ಯಾಲೆಂಡರ್', 'ರಿಮೈಂಡರ್', 'ಕಾರ್ಯಕ್ರಮ', 'ಹಬ್ಬ', 'காலண்டர்', 'நாட்காட்டி', 'நிகழ்', 'பண்டிகை',
    ],
  ),
  Concept.remindMe: (
    {'remind me', 'set a reminder', 'set reminder', 'add a reminder', 'add reminder', 'remind'},
    ['గుర్తు చే', 'గుర్తుచే', 'याद दिला', 'ನೆನಪಿಸ', 'ನೆನಪು ಮಾಡ', 'நினைவூட்ட', 'நினைவு படுத்த'],
  ),
  Concept.list: (
    {'list', 'lists', 'checklist', 'shopping', 'notes', 'note'},
    ['జాబితా', 'లిస్ట్', 'చెక్‌లిస్ట్', 'सूची', 'लिस्ट', 'ಪಟ್ಟಿ', 'ಲಿಸ್ಟ್', 'பட்டியல்', 'லிஸ்ட்'],
  ),
  Concept.pay: ({'pay', 'send money', 'scan'}, ['చెల్లించాల', 'పంపాల', 'भुगतान कर', 'पैसे भेज', 'ಪಾವತಿ ಮಾಡ', 'பணம் அனுப்']),
  Concept.given: (
    {'given', 'gave', 'give', 'sold', 'sell', 'supplied', 'report', 'reports', 'business'},
    ['ఇచ్చిన', 'ఇచ్చాను', 'రిపోర్ట్', 'అమ్మిన', 'दिया', 'दिए', 'रिपोर्ट', 'बेचा', 'ಕೊಟ್ಟ', 'ವರದಿ', 'ಮಾರಿದ', 'கொடுத்த', 'அறிக்கை', 'விற்ற'],
  ),
  Concept.connect: (
    {'connect', 'connection', 'connections', 'request', 'requests', 'join'},
    ['కనెక్ట్', 'అభ్యర్థన', 'कनेक्ट', 'जुड़', 'अनुरोध', 'ಸಂಪರ್ಕ', 'ಕನೆಕ್ಟ್', 'ವಿನಂತಿ', 'இணை', 'கோரிக்கை'],
  ),
  Concept.tomorrow: ({'tomorrow', 'repu'}, ['రేపు', 'ನಾಳೆ', 'நாளை', 'कल ']),
};

/// What [text] is about.
Set<Concept> conceptsIn(String text) {
  final lower = ' ${text.toLowerCase().replaceAll(RegExp(r'''[.,!?।|"'()]'''), ' ').replaceAll(RegExp(r'\s+'), ' ').trim()} ';
  return {
    for (final MapEntry(key: concept, value: (english, native)) in _words.entries)
      if (english.any((w) => lower.contains(' $w ')) || native.any((w) => lower.contains(' ${_stem(w)}'))) concept,
  };
}

/// Without the mark that closes a word: endings replace it (Tamil "...r" + "ukku").
String _stem(String word) =>
    const {0x094D, 0x0C4D, 0x0CCD, 0x0BCD}.contains(word.runes.last) ? word.substring(0, word.length - 1) : word;

/// Answers: English, Telugu, Hindi, Kannada, Tamil. {a} {b} {c} are filled in.
const _says = <String, List<String>>{
  'owedMost': [
    '{a} owes the most: {b}.',
    'అందరికంటే ఎక్కువ బాకీ {a}: {b}.',
    'सबसे ज़्यादा {a} का बाकी है: {b}.',
    'ಹೆಚ್ಚು ಬಾಕಿ {a}: {b}.',
    'அதிக பாக்கி {a}: {b}.',
  ],
  'owedTotal': [
    'Customers owe you {b} in all. Customers: {a}.',
    'కస్టమర్లు మీకు మొత్తం {b} ఇవ్వాలి. కస్టమర్లు: {a}.',
    'ग्राहकों से कुल {b} मिलने हैं. ग्राहक: {a}.',
    'ಗ್ರಾಹಕರಿಂದ ಒಟ್ಟು {b} ಬರಬೇಕು. ಗ್ರಾಹಕರು: {a}.',
    'வாடிக்கையாளர்களிடமிருந்து மொத்தம் {b} வர வேண்டும். வாடிக்கையாளர்கள்: {a}.',
  ],
  'owedNone': [
    'No customer owes you now.',
    'ఇప్పుడు మీకు ఎవరూ బాకీ లేరు.',
    'अभी किसी का बाकी नहीं है.',
    'ಈಗ ಯಾರ ಬಾಕಿಯೂ ಇಲ್ಲ.',
    'இப்போது யாருக்கும் பாக்கி இல்லை.',
  ],
  'owesYou': [
    '{a} owes you {b}.',
    '{a} మీకు {b} ఇవ్వాలి.',
    '{a} से {b} मिलने हैं.',
    '{a} ಅವರಿಂದ {b} ಬರಬೇಕು.',
    '{a} உங்களுக்கு {b} தர வேண்டும்.',
  ],
  'owesNothing': [
    '{a} owes you nothing.',
    '{a} మీకు బాకీ లేదు.',
    '{a} का कुछ बाकी नहीं है.',
    '{a} ಅವರ ಬಾಕಿ ಇಲ್ಲ.',
    '{a} பாக்கி எதுவும் இல்லை.',
  ],
  'advance': [
    '{a} paid {b} in advance.',
    '{a} ముందుగా {b} ఇచ్చారు.',
    '{a} ने {b} पहले से दिए हैं.',
    '{a} ಮುಂಗಡ {b} ಕೊಟ್ಟಿದ್ದಾರೆ.',
    '{a} {b} முன்பணம் கொடுத்துள்ளார்.',
  ],
  'late': [
    'Customers who are late: {a}.',
    'ఆలస్యం చేసిన కస్టమర్లు: {a}.',
    'देर करने वाले ग्राहक: {a}.',
    'ತಡ ಮಾಡಿದ ಗ್ರಾಹಕರು: {a}.',
    'தாமதமான வாடிக்கையாளர்கள்: {a}.',
  ],
  'lateNone': [
    'No customer is late.',
    'ఎవరూ ఆలస్యం చేయలేదు.',
    'किसी ने देर नहीं की है.',
    'ಯಾರೂ ತಡ ಮಾಡಿಲ್ಲ.',
    'யாரும் தாமதம் இல்லை.',
  ],
  'low': [
    'Running low: {a}.',
    'తక్కువగా ఉన్నవి: {a}.',
    'कम हो रही चीज़ें: {a}.',
    'ಕಡಿಮೆ ಇರುವವು: {a}.',
    'குறைவாக உள்ளவை: {a}.',
  ],
  'lowNone': [
    'Nothing is running low.',
    'ఏదీ తక్కువగా లేదు.',
    'कुछ भी कम नहीं है.',
    'ಯಾವುದೂ ಕಡಿಮೆ ಇಲ್ಲ.',
    'எதுவும் குறைவாக இல்லை.',
  ],
  'have': [
    'You have {b} of {a}.',
    '{a}: {b} ఉంది.',
    '{a}: {b} है.',
    '{a}: {b} ಇದೆ.',
    '{a}: {b} உள்ளது.',
  ],
  'notCounted': [
    'You do not count {a} yet.',
    '{a} ఇంకా లెక్కించలేదు.',
    '{a} की गिनती अभी नहीं है.',
    '{a} ಇನ್ನೂ ಎಣಿಸಿಲ್ಲ.',
    '{a} இன்னும் எண்ணவில்லை.',
  ],
  'stockAll': [
    'Items in stock: {a}. Running low: {b}.',
    'స్టాక్‌లో వస్తువులు: {a}. తక్కువగా ఉన్నవి: {b}.',
    'स्टॉक में चीज़ें: {a}. कम: {b}.',
    'ಸ್ಟಾಕ್‌ನಲ್ಲಿ ವಸ್ತುಗಳು: {a}. ಕಡಿಮೆ: {b}.',
    'ஸ்டாக்கில் பொருட்கள்: {a}. குறைவு: {b}.',
  ],
  'stockValue': [
    'Your stock is worth {a}.',
    'మీ స్టాక్ విలువ {a}.',
    'आपके स्टॉक की कीमत {a} है.',
    'ನಿಮ್ಮ ಸ್ಟಾಕ್ ಮೌಲ್ಯ {a}.',
    'உங்கள் ஸ்டாக் மதிப்பு {a}.',
  ],
  'paidToday': [
    'You received {a} today.',
    'ఈరోజు {a} వచ్చాయి.',
    'आज {a} मिले.',
    'ಇಂದು {a} ಬಂದಿದೆ.',
    'இன்று {a} வந்தது.',
  ],
  'toConfirm': [
    'Payments waiting for you to check: {a}.',
    'మీరు చూడాల్సిన చెల్లింపులు: {a}.',
    'जाँचने वाले भुगतान: {a}.',
    'ನೀವು ನೋಡಬೇಕಾದ ಪಾವತಿಗಳು: {a}.',
    'நீங்கள் சரிபார்க்க வேண்டிய கட்டணங்கள்: {a}.',
  ],
  'confirmNone': [
    'No payment is waiting for you.',
    'చూడాల్సిన చెల్లింపులు లేవు.',
    'जाँचने के लिए कोई भुगतान नहीं है.',
    'ನೋಡಬೇಕಾದ ಪಾವತಿಗಳಿಲ್ಲ.',
    'சரிபார்க்க கட்டணம் எதுவும் இல்லை.',
  ],
  'oweSuppliers': [
    'You owe suppliers {a} in all.',
    'మీరు సప్లయర్లకు మొత్తం {a} ఇవ్వాలి.',
    'आपको सप्लायरों को कुल {a} देने हैं.',
    'ನೀವು ಸಪ್ಲೈಯರ್‌ಗಳಿಗೆ ಒಟ್ಟು {a} ಕೊಡಬೇಕು.',
    'நீங்கள் சப்ளையர்களுக்கு மொத்தம் {a} தர வேண்டும்.',
  ],
  'youOwe': [
    'You owe {a} {b}.',
    'మీరు {a}కి {b} ఇవ్వాలి.',
    'आपको {a} को {b} देने हैं.',
    'ನೀವು {a} ಅವರಿಗೆ {b} ಕೊಡಬೇಕು.',
    'நீங்கள் {a} அவர்களுக்கு {b} தர வேண்டும்.',
  ],
  'youOweNothingTo': [
    'You owe {a} nothing.',
    'మీరు {a}కి ఏమీ ఇవ్వక్కర్లేదు.',
    'आपको {a} को कुछ नहीं देना है.',
    'ನೀವು {a} ಅವರಿಗೆ ಏನೂ ಕೊಡಬೇಕಿಲ್ಲ.',
    'நீங்கள் {a} அவர்களுக்கு எதுவும் தர வேண்டியதில்லை.',
  ],
  'youPaidAdvance': [
    'You paid {a} {b} in advance.',
    'మీరు {a}కి ముందుగా {b} ఇచ్చారు.',
    'आपने {a} को {b} पहले से दिए हैं.',
    'ನೀವು {a} ಅವರಿಗೆ ಮುಂಗಡ {b} ಕೊಟ್ಟಿದ್ದೀರಿ.',
    'நீங்கள் {a} அவர்களுக்கு {b} முன்பணம் கொடுத்துள்ளீர்கள்.',
  ],
  'youOweTotal': [
    'You owe {b} in all. Shops: {a}.',
    'మీరు మొత్తం {b} ఇవ్వాలి. షాపులు: {a}.',
    'आपको कुल {b} देने हैं. दुकानें: {a}.',
    'ನೀವು ಒಟ್ಟು {b} ಕೊಡಬೇಕು. ಅಂಗಡಿಗಳು: {a}.',
    'நீங்கள் மொத்தம் {b} தர வேண்டும். கடைகள்: {a}.',
  ],
  'youOweNone': [
    'You owe nothing.',
    'మీకు బాకీలు లేవు.',
    'आपका कुछ बाकी नहीं है.',
    'ನಿಮಗೆ ಬಾಕಿ ಇಲ್ಲ.',
    'உங்களுக்கு பாக்கி இல்லை.',
  ],
  'orders': [
    'Orders waiting for goods: {a}.',
    'సరుకు రావాల్సిన ఆర్డర్లు: {a}.',
    'जिन ऑर्डर का माल आना है: {a}.',
    'ಸರಕು ಬರಬೇಕಾದ ಆರ್ಡರ್‌ಗಳು: {a}.',
    'பொருள் வர வேண்டிய ஆர்டர்கள்: {a}.',
  ],
  'ordersNone': [
    'No order is waiting.',
    'పెండింగ్ ఆర్డర్లు లేవు.',
    'कोई ऑर्डर बाकी नहीं है.',
    'ಬಾಕಿ ಆರ್ಡರ್ ಇಲ್ಲ.',
    'நிலுவை ஆர்டர் இல்லை.',
  ],
  'newOrders': [
    'New orders: {a}. To send: {b}.',
    'కొత్త ఆర్డర్లు: {a}. పంపాల్సినవి: {b}.',
    'नए ऑर्डर: {a}. भेजने हैं: {b}.',
    'ಹೊಸ ಆರ್ಡರ್‌ಗಳು: {a}. ಕಳಿಸಬೇಕಾದವು: {b}.',
    'புதிய ஆர்டர்கள்: {a}. அனுப்ப வேண்டியவை: {b}.',
  ],
  'spent': [
    'You spent {a} this month.',
    'ఈ నెల {a} ఖర్చు చేశారు.',
    'इस महीने {a} खर्च हुए.',
    'ಈ ತಿಂಗಳು {a} ಖರ್ಚಾಗಿದೆ.',
    'இந்த மாதம் {a} செலவானது.',
  ],
  'budgetLeft': [
    'You spent {a} of {b}. {c} is left.',
    '{b}లో {a} ఖర్చు చేశారు. ఇంకా {c} ఉంది.',
    '{b} में से {a} खर्च हुए. {c} बचे हैं.',
    '{b} ರಲ್ಲಿ {a} ಖರ್ಚಾಗಿದೆ. {c} ಉಳಿದಿದೆ.',
    '{b} இல் {a} செலவானது. {c} மீதம்.',
  ],
  'budgetOver': [
    'You spent {a}. That is {c} over your budget of {b}.',
    '{a} ఖర్చు చేశారు. బడ్జెట్ {b} కంటే {c} ఎక్కువ.',
    '{a} खर्च हुए. बजट {b} से {c} ज़्यादा.',
    '{a} ಖರ್ಚಾಗಿದೆ. ಬಜೆಟ್ {b} ಗಿಂತ {c} ಹೆಚ್ಚು.',
    '{a} செலவானது. பட்ஜெட் {b} ஐ விட {c} அதிகம்.',
  ],
  'lastPaid': [
    'Payments this month: {a}. Total {b}.',
    'ఈ నెల చెల్లింపులు: {a}. మొత్తం {b}.',
    'इस महीने के भुगतान: {a}. कुल {b}.',
    'ಈ ತಿಂಗಳ ಪಾವತಿಗಳು: {a}. ಒಟ್ಟು {b}.',
    'இந்த மாத கட்டணங்கள்: {a}. மொத்தம் {b}.',
  ],
  'lastPaidNone': [
    'No payment this month.',
    'ఈ నెల చెల్లింపులు లేవు.',
    'इस महीने कोई भुगतान नहीं.',
    'ಈ ತಿಂಗಳು ಪಾವತಿ ಇಲ್ಲ.',
    'இந்த மாதம் கட்டணம் இல்லை.',
  ],
  'today': [
    'In your calendar today: {a}.',
    'ఈరోజు మీ క్యాలెండర్‌లో: {a}.',
    'आज आपके कैलेंडर में: {a}.',
    'ಇಂದು ನಿಮ್ಮ ಕ್ಯಾಲೆಂಡರ್‌ನಲ್ಲಿ: {a}.',
    'இன்று உங்கள் காலண்டரில்: {a}.',
  ],
  'todayNone': [
    'Nothing in your calendar today.',
    'ఈరోజు క్యాలెండర్‌లో ఏమీ లేదు.',
    'आज कैलेंडर में कुछ नहीं है.',
    'ಇಂದು ಕ್ಯಾಲೆಂಡರ್‌ನಲ್ಲಿ ಏನೂ ಇಲ್ಲ.',
    'இன்று காலண்டரில் எதுவும் இல்லை.',
  ],
  'tomorrow': [
    'In your calendar tomorrow: {a}.',
    'రేపు మీ క్యాలెండర్‌లో: {a}.',
    'कल आपके कैलेंडर में: {a}.',
    'ನಾಳೆ ನಿಮ್ಮ ಕ್ಯಾಲೆಂಡರ್‌ನಲ್ಲಿ: {a}.',
    'நாளை உங்கள் காலண்டரில்: {a}.',
  ],
  'tomorrowNone': [
    'Nothing in your calendar tomorrow.',
    'రేపు క్యాలెండర్‌లో ఏమీ లేదు.',
    'कल कैलेंडर में कुछ नहीं है.',
    'ನಾಳೆ ಕ್ಯಾಲೆಂಡರ್‌ನಲ್ಲಿ ಏನೂ ಇಲ್ಲ.',
    'நாளை காலண்டரில் எதுவும் இல்லை.',
  ],
  'lists': [
    'Left in your lists: {a}.',
    'మీ లిస్టుల్లో మిగిలినవి: {a}.',
    'आपकी सूचियों में बाकी: {a}.',
    'ನಿಮ್ಮ ಪಟ್ಟಿಗಳಲ್ಲಿ ಉಳಿದವು: {a}.',
    'உங்கள் பட்டியலில் மீதம்: {a}.',
  ],
  'listsNone': [
    'Nothing is left in your lists.',
    'మీ లిస్టుల్లో ఏమీ మిగలలేదు.',
    'आपकी सूचियों में कुछ बाकी नहीं है.',
    'ನಿಮ್ಮ ಪಟ್ಟಿಗಳಲ್ಲಿ ಏನೂ ಉಳಿದಿಲ್ಲ.',
    'உங்கள் பட்டியலில் எதுவும் மீதமில்லை.',
  ],
  'toGet': [
    'Shops owe you {a} in all.',
    'షాపులు మీకు మొత్తం {a} ఇవ్వాలి.',
    'दुकानों से कुल {a} मिलने हैं.',
    'ಅಂಗಡಿಗಳಿಂದ ಒಟ್ಟು {a} ಬರಬೇಕು.',
    'கடைகளிடமிருந்து மொத்தம் {a} வர வேண்டும்.',
  ],
  'received': [
    'You received {a} this month.',
    'ఈ నెల {a} వచ్చాయి.',
    'इस महीने {a} मिले.',
    'ಈ ತಿಂಗಳು {a} ಬಂದಿದೆ.',
    'இந்த மாதம் {a} வந்தது.',
  ],
  'given': [
    'You gave goods of {a} this month.',
    'ఈ నెల {a} సరుకు ఇచ్చారు.',
    'इस महीने {a} का माल दिया.',
    'ಈ ತಿಂಗಳು {a} ಸರಕು ಕೊಟ್ಟಿದ್ದೀರಿ.',
    'இந்த மாதம் {a} பொருள் கொடுத்தீர்கள்.',
  ],
  'requests': [
    'Shops that want to connect: {a}.',
    'కనెక్ట్ కావాలనుకునే షాపులు: {a}.',
    'जुड़ना चाहने वाली दुकानें: {a}.',
    'ಸಂಪರ್ಕ ಬಯಸುವ ಅಂಗಡಿಗಳು: {a}.',
    'இணைய விரும்பும் கடைகள்: {a}.',
  ],
  'requestsNone': [
    'No shop is asking to connect.',
    'కనెక్ట్ అభ్యర్థనలు లేవు.',
    'जुड़ने का कोई अनुरोध नहीं है.',
    'ಸಂಪರ್ಕ ವಿನಂತಿ ಇಲ್ಲ.',
    'இணைப்பு கோரிக்கை இல்லை.',
  ],
  'writeUdhaar': [
    'Udhaar given to {a}: {b}. Check and save.',
    '{a}కి ఉధార్: {b}. చూసి సేవ్ చేయండి.',
    '{a} को उधार: {b}. जाँचकर सेव करें.',
    '{a} ಅವರಿಗೆ ಉದ್ರಿ: {b}. ನೋಡಿ ಸೇವ್ ಮಾಡಿ.',
    '{a} அவர்களுக்கு கடன்: {b}. சரிபார்த்து சேமிக்கவும்.',
  ],
  'writePayment': [
    'Payment from {a}: {b}. Check and save.',
    '{a} ఇచ్చింది: {b}. చూసి సేవ్ చేయండి.',
    '{a} से भुगतान: {b}. जाँचकर सेव करें.',
    '{a} ಅವರಿಂದ ಪಾವತಿ: {b}. ನೋಡಿ ಸೇವ್ ಮಾಡಿ.',
    '{a} செலுத்தியது: {b}. சரிபார்த்து சேமிக்கவும்.',
  ],
  'stockIn': [
    'Stock in, {a}: {b}. Check and save.',
    'స్టాక్ వచ్చింది, {a}: {b}. చూసి సేవ్ చేయండి.',
    'स्टॉक आया, {a}: {b}. जाँचकर सेव करें.',
    'ಸ್ಟಾಕ್ ಬಂದಿದೆ, {a}: {b}. ನೋಡಿ ಸೇವ್ ಮಾಡಿ.',
    'ஸ்டாக் வந்தது, {a}: {b}. சரிபார்த்து சேமிக்கவும்.',
  ],
  'stockOut': [
    'Sold, {a}: {b}. Check and save.',
    'అమ్మింది, {a}: {b}. చూసి సేవ్ చేయండి.',
    'बिका, {a}: {b}. जाँचकर सेव करें.',
    'ಮಾರಿದ್ದು, {a}: {b}. ನೋಡಿ ಸೇವ್ ಮಾಡಿ.',
    'விற்றது, {a}: {b}. சரிபார்த்து சேமிக்கவும்.',
  ],
  'reminder': [
    'Reminder: {a}. Check and save.',
    'రిమైండర్: {a}. చూసి సేవ్ చేయండి.',
    'रिमाइंडर: {a}. जाँचकर सेव करें.',
    'ರಿಮೈಂಡರ್: {a}. ನೋಡಿ ಸೇವ್ ಮಾಡಿ.',
    'நினைவூட்டல்: {a}. சரிபார்த்து சேமிக்கவும்.',
  ],
  'payShop': [
    'Choose the shop and the amount, then pay.',
    'షాపు, మొత్తం ఎంచుకొని చెల్లించండి.',
    'दुकान और रकम चुनकर भुगतान करें.',
    'ಅಂಗಡಿ ಮತ್ತು ಮೊತ್ತ ಆರಿಸಿ ಪಾವತಿಸಿ.',
    'கடையும் தொகையும் தேர்ந்தெடுத்து செலுத்தவும்.',
  ],
  'whichWay': [
    '{a}, {b}: udhaar given, or payment?',
    '{a}, {b}: ఉధార్ ఇచ్చారా, లేక చెల్లించారా?',
    '{a}, {b}: उधार दिया या भुगतान मिला?',
    '{a}, {b}: ಉದ್ರಿ ಕೊಟ್ಟದ್ದೇ, ಪಾವತಿಯೇ?',
    '{a}, {b}: கடனா, கட்டணமா?',
  ],
  'udhaar': ['Udhaar given', 'ఉధార్ ఇచ్చాను', 'उधार दिया', 'ಉದ್ರಿ ಕೊಟ್ಟೆ', 'கடன் கொடுத்தேன்'],
  'payment': ['Payment received', 'చెల్లింపు వచ్చింది', 'भुगतान मिला', 'ಪಾವತಿ ಬಂತು', 'கட்டணம் வந்தது'],
  'which': ['Which one?', 'ఎవరు?', 'कौन सा?', 'ಯಾವುದು?', 'எது?'],
  'help': [
    'You can ask me like this.',
    'ఇలా అడగండి.',
    'ऐसे पूछिए.',
    'ಹೀಗೆ ಕೇಳಿ.',
    'இப்படி கேளுங்கள்.',
  ],
  'sorry': [
    'I did not understand. Try one of these.',
    'అర్థం కాలేదు. వీటిలో ఒకటి అడగండి.',
    'समझ नहीं आया. इनमें से कुछ पूछिए.',
    'ಅರ್ಥವಾಗಲಿಲ್ಲ. ಇವುಗಳಲ್ಲಿ ಒಂದನ್ನು ಕೇಳಿ.',
    'புரியவில்லை. இவற்றில் ஒன்றைக் கேளுங்கள்.',
  ],
  'needNet': [
    'This needs internet.',
    'దీనికి ఇంటర్నెట్ కావాలి.',
    'इसके लिए इंटरनेट चाहिए.',
    'ಇದಕ್ಕೆ ಇಂಟರ್ನೆಟ್ ಬೇಕು.',
    'இதற்கு இணையம் தேவை.',
  ],
  'saved': [
    'Offline: from the saved copy.',
    'ఆఫ్‌లైన్: సేవ్ చేసిన కాపీ నుండి.',
    'ऑफ़लाइन: सेव की हुई कॉपी से.',
    'ಆಫ್‌ಲೈನ್: ಸೇವ್ ಮಾಡಿದ ಪ್ರತಿಯಿಂದ.',
    'ஆஃப்லைன்: சேமித்த நகலிலிருந்து.',
  ],
  'open': ['Open', 'తెరవండి', 'खोलें', 'ತೆರೆಯಿರಿ', 'திற'],
  'check': ['Check and save', 'చూసి సేవ్ చేయండి', 'जाँचकर सेव करें', 'ನೋಡಿ ಸೇವ್ ಮಾಡಿ', 'சரிபார்த்து சேமி'],
  'asking': [
    'Ask in your language',
    'మీ భాషలో అడగండి',
    'अपनी भाषा में पूछिए',
    'ನಿಮ್ಮ ಭಾಷೆಯಲ್ಲಿ ಕೇಳಿ',
    'உங்கள் மொழியில் கேளுங்கள்',
  ],
  'listening': ['Listening...', 'వింటున్నాను...', 'सुन रहा हूँ...', 'ಕೇಳುತ್ತಿದ್ದೇನೆ...', 'கேட்கிறேன்...'],
};

int _at(AppLanguage language) => switch (language) {
  AppLanguage.english => 0,
  AppLanguage.telugu => 1,
  AppLanguage.hindi => 2,
  AppLanguage.kannada => 3,
  AppLanguage.tamil => 4,
};

/// The answer [key] in [language], with {a} {b} {c} filled in.
String askSays(String key, AppLanguage language, {String a = '', String b = '', String c = ''}) =>
    _says[key]![_at(language)].replaceAll('{a}', a).replaceAll('{b}', b).replaceAll('{c}', c);

/// For tests.
Iterable<MapEntry<String, List<String>>> get allAnswers => _says.entries;

/// Things to try, for each role.
List<String> askExamples(QboxRole role, AppLanguage language) => _examples[role]![_at(language)];

const _examples = <QboxRole, List<List<String>>>{
  QboxRole.business: [
    ['Who owes me the most?', 'What is running low?', 'How much payment came today?', 'How much do I owe suppliers?', 'Total udhaar'],
    ['ఎవరు ఎక్కువ బాకీ?', 'ఏ స్టాక్ తక్కువగా ఉంది?', 'ఈరోజు ఎంత పేమెంట్ వచ్చింది?', 'సప్లయర్లకు ఎంత ఇవ్వాలి?', 'మొత్తం ఉధార్ ఎంత?'],
    ['सबसे ज़्यादा किसका बाकी है?', 'कौन सा स्टॉक कम है?', 'आज कितना पेमेंट आया?', 'सप्लायर को कितना देना है?', 'कुल उधार कितना है?'],
    ['ಯಾರ ಬಾಕಿ ಹೆಚ್ಚು?', 'ಯಾವ ಸ್ಟಾಕ್ ಕಡಿಮೆ ಇದೆ?', 'ಇಂದು ಎಷ್ಟು ಪೇಮೆಂಟ್ ಬಂತು?', 'ಸಪ್ಲೈಯರ್‌ಗೆ ಎಷ್ಟು ಕೊಡಬೇಕು?', 'ಒಟ್ಟು ಉದ್ರಿ ಎಷ್ಟು?'],
    ['யார் அதிக பாக்கி?', 'எந்த ஸ்டாக் குறைவு?', 'இன்று எவ்வளவு பேமெண்ட் வந்தது?', 'சப்ளையருக்கு எவ்வளவு பாக்கி?', 'மொத்த கடன் எவ்வளவு?'],
  ],
  QboxRole.customer: [
    ['How much do I owe?', 'How much did I spend this month?', 'How much budget is left?', 'What is in my calendar tomorrow?', 'What is left in my list?'],
    ['నా బాకీ ఎంత?', 'ఈ నెల ఎంత ఖర్చు చేశాను?', 'బడ్జెట్ ఎంత ఉంది?', 'రేపు క్యాలెండర్‌లో ఏముంది?', 'నా లిస్ట్‌లో ఏముంది?'],
    ['मेरा कितना बाकी है?', 'इस महीने कितना खर्च हुआ?', 'बजट कितना बचा है?', 'कल कैलेंडर में क्या है?', 'मेरी सूची में क्या है?'],
    ['ನನ್ನ ಬಾಕಿ ಎಷ್ಟು?', 'ಈ ತಿಂಗಳು ಎಷ್ಟು ಖರ್ಚು?', 'ಬಜೆಟ್ ಎಷ್ಟು ಉಳಿದಿದೆ?', 'ನಾಳೆ ಕ್ಯಾಲೆಂಡರ್‌ನಲ್ಲಿ ಏನಿದೆ?', 'ನನ್ನ ಪಟ್ಟಿಯಲ್ಲಿ ಏನಿದೆ?'],
    ['என் பாக்கி எவ்வளவு?', 'இந்த மாதம் எவ்வளவு செலவு?', 'பட்ஜெட் எவ்வளவு மீதம்?', 'நாளை காலண்டரில் என்ன?', 'என் பட்டியலில் என்ன?'],
  ],
  QboxRole.supplier: [
    ['Any new orders?', 'How much do shops owe me?', 'Which products are low?', 'Payments to confirm', 'How much did I give this month?'],
    ['కొత్త ఆర్డర్లు ఉన్నాయా?', 'షాపుల బాకీ ఎంత?', 'ఏ స్టాక్ తక్కువగా ఉంది?', 'ఈ నెల ఎంత పేమెంట్ వచ్చింది?', 'రిపోర్ట్ చెప్పు'],
    ['नए ऑर्डर हैं?', 'दुकानों का कितना बाकी है?', 'कौन सा स्टॉक कम है?', 'इस महीने कितना पेमेंट आया?', 'रिपोर्ट बताओ'],
    ['ಹೊಸ ಆರ್ಡರ್ ಇದೆಯಾ?', 'ಅಂಗಡಿಗಳ ಬಾಕಿ ಎಷ್ಟು?', 'ಯಾವ ಸ್ಟಾಕ್ ಕಡಿಮೆ ಇದೆ?', 'ಈ ತಿಂಗಳು ಎಷ್ಟು ಪೇಮೆಂಟ್ ಬಂತು?', 'ವರದಿ ಹೇಳಿ'],
    ['புதிய ஆர்டர் இருக்கா?', 'கடைகளின் பாக்கி எவ்வளவு?', 'எந்த ஸ்டாக் குறைவு?', 'இந்த மாதம் எவ்வளவு பேமெண்ட்?', 'அறிக்கை சொல்லு'],
  ],
};
