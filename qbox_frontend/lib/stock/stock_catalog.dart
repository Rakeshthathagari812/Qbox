import '../translator/languages.dart';
import 'stock_models.dart';

/// A common shop item with its name in all 5 languages, so the shopkeeper can
/// pick it in one tap and say it in any language ("బియ్యం", "चावल", "rice").
class CatalogItem {
  const CatalogItem(this.code, this.unit, this.en, this.te, this.hi, this.kn, this.ta, [this.aliases = const []]);

  final String code;
  final StockUnit unit;
  final String en;
  final String te;
  final String hi;
  final String kn;
  final String ta;

  /// Other ways people say it, in English letters ("chawal", "biyyam").
  final List<String> aliases;

  String nameIn(AppLanguage language) => switch (language) {
    AppLanguage.english => en,
    AppLanguage.telugu => te,
    AppLanguage.hindi => hi,
    AppLanguage.kannada => kn,
    AppLanguage.tamil => ta,
  };

  /// Every name it can be called by.
  List<String> get allNames => [en, te, hi, kn, ta, ...aliases];
}

CatalogItem? catalogItem(String? code) {
  if (code == null) return null;
  for (final c in stockCatalog) {
    if (c.code == code) return c;
  }
  return null;
}

const stockCatalog = <CatalogItem>[
  // Rice, flour, dals
  CatalogItem('rice', StockUnit.kg, 'Rice', 'బియ్యం', 'चावल', 'ಅಕ್ಕಿ', 'அரிசி', ['chawal', 'biyyam', 'akki', 'arisi']),
  CatalogItem('wheat_atta', StockUnit.kg, 'Wheat flour (atta)', 'గోధుమ పిండి', 'आटा', 'ಗೋಧಿ ಹಿಟ್ಟು', 'கோதுமை மாவு', ['atta', 'aata', 'godhuma pindi', 'godhi hittu']),
  CatalogItem('maida', StockUnit.kg, 'Maida', 'మైదా', 'मैदा', 'ಮೈದಾ', 'மைதா'),
  CatalogItem('rava', StockUnit.kg, 'Rava (sooji)', 'రవ్వ', 'सूजी', 'ರವೆ', 'ரவை', ['sooji', 'suji', 'ravva', 'rave', 'ravai']),
  CatalogItem('besan', StockUnit.kg, 'Besan', 'శనగ పిండి', 'बेसन', 'ಕಡಲೆ ಹಿಟ್ಟು', 'கடலை மாவு', ['senaga pindi']),
  CatalogItem('rice_flour', StockUnit.kg, 'Rice flour', 'బియ్యం పిండి', 'चावल का आटा', 'ಅಕ್ಕಿ ಹಿಟ್ಟು', 'அரிசி மாவு', ['biyyam pindi']),
  CatalogItem('ragi_flour', StockUnit.kg, 'Ragi flour', 'రాగి పిండి', 'रागी आटा', 'ರಾಗಿ ಹಿಟ್ಟು', 'கேழ்வரகு மாவு', ['ragi']),
  CatalogItem('poha', StockUnit.kg, 'Poha', 'అటుకులు', 'पोहा', 'ಅವಲಕ್ಕಿ', 'அவல்', ['atukulu', 'avalakki', 'aval']),
  CatalogItem('sabudana', StockUnit.kg, 'Sabudana', 'సగ్గుబియ్యం', 'साबूदाना', 'ಸಬ್ಬಕ್ಕಿ', 'ஜவ்வரிசி', ['saggubiyyam']),
  CatalogItem('toor_dal', StockUnit.kg, 'Toor dal', 'కంది పప్పు', 'अरहर दाल', 'ತೊಗರಿ ಬೇಳೆ', 'துவரம் பருப்பு', ['tur dal', 'arhar', 'kandi pappu', 'togari bele']),
  CatalogItem('moong_dal', StockUnit.kg, 'Moong dal', 'పెసర పప్పు', 'मूंग दाल', 'ಹೆಸರು ಬೇಳೆ', 'பாசிப் பருப்பு', ['pesara pappu', 'hesaru bele']),
  CatalogItem('urad_dal', StockUnit.kg, 'Urad dal', 'మినప పప్పు', 'उड़द दाल', 'ಉದ್ದಿನ ಬೇಳೆ', 'உளுத்தம் பருப்பு', ['minapa pappu', 'uddina bele']),
  CatalogItem('chana_dal', StockUnit.kg, 'Chana dal', 'శనగ పప్పు', 'चना दाल', 'ಕಡಲೆ ಬೇಳೆ', 'கடலைப் பருப்பு', ['senaga pappu', 'kadale bele']),
  CatalogItem('masoor_dal', StockUnit.kg, 'Masoor dal', 'మసూర్ పప్పు', 'मसूर दाल', 'ಮಸೂರ್ ಬೇಳೆ', 'மசூர் பருப்பு'),
  CatalogItem('chana', StockUnit.kg, 'Chickpeas (chana)', 'శనగలు', 'चना', 'ಕಡಲೆ', 'கொண்டைக்கடலை', ['senagalu', 'kadale']),
  CatalogItem('rajma', StockUnit.kg, 'Rajma', 'రాజ్మా', 'राजमा', 'ರಾಜ್ಮಾ', 'ராஜ்மா'),
  CatalogItem('groundnuts', StockUnit.kg, 'Groundnuts', 'వేరుశనగలు', 'मूंगफली', 'ಕಡಲೆಕಾಯಿ', 'வேர்க்கடலை', ['peanuts', 'verusenagalu']),
  // Oil, sugar, dairy
  CatalogItem('sugar', StockUnit.kg, 'Sugar', 'చక్కెర', 'चीनी', 'ಸಕ್ಕರೆ', 'சர்க்கரை', ['cheeni', 'chini', 'chakkera', 'panchadara', 'sakkare']),
  CatalogItem('jaggery', StockUnit.kg, 'Jaggery', 'బెల్లం', 'गुड़', 'ಬೆಲ್ಲ', 'வெல்லம்', ['gud', 'bellam', 'bella']),
  CatalogItem('salt', StockUnit.packet, 'Salt', 'ఉప్పు', 'नमक', 'ಉಪ್ಪು', 'உப்பு', ['namak', 'uppu']),
  CatalogItem('sunflower_oil', StockUnit.l, 'Sunflower oil', 'సన్‌ఫ్లవర్ నూనె', 'सूरजमुखी तेल', 'ಸೂರ್ಯಕಾಂತಿ ಎಣ್ಣೆ', 'சூரியகாந்தி எண்ணெய்'),
  CatalogItem('groundnut_oil', StockUnit.l, 'Groundnut oil', 'వేరుశనగ నూనె', 'मूंगफली तेल', 'ಕಡಲೆಕಾಯಿ ಎಣ್ಣೆ', 'கடலை எண்ணெய்', ['palli nune']),
  CatalogItem('mustard_oil', StockUnit.l, 'Mustard oil', 'ఆవ నూనె', 'सरसों का तेल', 'ಸಾಸಿವೆ ಎಣ್ಣೆ', 'கடுகு எண்ணெய்'),
  CatalogItem('coconut_oil', StockUnit.l, 'Coconut oil', 'కొబ్బరి నూనె', 'नारियल तेल', 'ತೆಂಗಿನ ಎಣ್ಣೆ', 'தேங்காய் எண்ணெய்'),
  CatalogItem('ghee', StockUnit.kg, 'Ghee', 'నెయ్యి', 'घी', 'ತುಪ್ಪ', 'நெய்', ['neyyi', 'tuppa']),
  CatalogItem('milk', StockUnit.packet, 'Milk', 'పాలు', 'दूध', 'ಹಾಲು', 'பால்', ['doodh', 'paalu', 'haalu']),
  CatalogItem('curd', StockUnit.packet, 'Curd', 'పెరుగు', 'दही', 'ಮೊಸರು', 'தயிர்', ['dahi', 'perugu', 'mosaru']),
  CatalogItem('butter', StockUnit.packet, 'Butter', 'వెన్న', 'मक्खन', 'ಬೆಣ್ಣೆ', 'வெண்ணெய்'),
  CatalogItem('paneer', StockUnit.packet, 'Paneer', 'పనీర్', 'पनीर', 'ಪನೀರ್', 'பனீர்'),
  CatalogItem('eggs', StockUnit.piece, 'Eggs', 'గుడ్లు', 'अंडे', 'ಮೊಟ್ಟೆ', 'முட்டை', ['egg', 'ande', 'guddu', 'motte']),
  CatalogItem('bread', StockUnit.packet, 'Bread', 'బ్రెడ్', 'ब्रेड', 'ಬ್ರೆಡ್', 'ரொட்டி'),
  CatalogItem('tea', StockUnit.packet, 'Tea powder', 'టీ పొడి', 'चाय पत्ती', 'ಟೀ ಪುಡಿ', 'டீ தூள்', ['chai', 'tea']),
  CatalogItem('coffee', StockUnit.packet, 'Coffee powder', 'కాఫీ పొడి', 'कॉफ़ी', 'ಕಾಫಿ ಪುಡಿ', 'காபி தூள்', ['coffee']),
  CatalogItem('honey', StockUnit.piece, 'Honey', 'తేనె', 'शहद', 'ಜೇನುತುಪ್ಪ', 'தேன்'),
  // Spices
  CatalogItem('chilli_powder', StockUnit.packet, 'Chilli powder', 'కారం పొడి', 'लाल मिर्च पाउडर', 'ಖಾರದ ಪುಡಿ', 'மிளகாய் தூள்', ['karam', 'mirchi powder']),
  CatalogItem('turmeric', StockUnit.packet, 'Turmeric powder', 'పసుపు', 'हल्दी', 'ಅರಿಶಿನ', 'மஞ்சள் தூள்', ['haldi', 'pasupu', 'arishina']),
  CatalogItem('coriander_powder', StockUnit.packet, 'Coriander powder', 'ధనియాల పొడి', 'धनिया पाउडर', 'ಕೊತ್ತಂಬರಿ ಪುಡಿ', 'மல்லித் தூள்', ['dhaniya']),
  CatalogItem('garam_masala', StockUnit.packet, 'Garam masala', 'గరం మసాలా', 'गरम मसाला', 'ಗರಂ ಮಸಾಲ', 'கரம் மசாலா', ['masala']),
  CatalogItem('cumin', StockUnit.kg, 'Cumin (jeera)', 'జీలకర్ర', 'जीरा', 'ಜೀರಿಗೆ', 'சீரகம்', ['jeera', 'jeelakarra']),
  CatalogItem('mustard_seeds', StockUnit.kg, 'Mustard seeds', 'ఆవాలు', 'राई', 'ಸಾಸಿವೆ', 'கடுகு', ['rai', 'avalu']),
  CatalogItem('pepper', StockUnit.kg, 'Black pepper', 'మిరియాలు', 'काली मिर्च', 'ಕಾಳು ಮೆಣಸು', 'மிளகு', ['miriyalu']),
  CatalogItem('dry_chilli', StockUnit.kg, 'Dry red chilli', 'ఎండు మిర్చి', 'सूखी लाल मिर्च', 'ಒಣ ಮೆಣಸಿನಕಾಯಿ', 'காய்ந்த மிளகாய்', ['endu mirchi']),
  CatalogItem('tamarind', StockUnit.kg, 'Tamarind', 'చింతపండు', 'इमली', 'ಹುಣಸೆ ಹಣ್ಣು', 'புளி', ['imli', 'chintapandu']),
  CatalogItem('hing', StockUnit.packet, 'Asafoetida (hing)', 'ఇంగువ', 'हींग', 'ಇಂಗು', 'பெருங்காயம்', ['hing', 'inguva']),
  CatalogItem('cloves', StockUnit.packet, 'Cloves', 'లవంగాలు', 'लौंग', 'ಲವಂಗ', 'கிராம்பு', ['laung', 'lavangalu']),
  CatalogItem('cardamom', StockUnit.packet, 'Cardamom', 'యాలకులు', 'इलायची', 'ಏಲಕ್ಕಿ', 'ஏலக்காய்', ['elaichi', 'yalakulu']),
  CatalogItem('cashew', StockUnit.kg, 'Cashew', 'జీడిపప్పు', 'काजू', 'ಗೋಡಂಬಿ', 'முந்திரி', ['kaju', 'jeedipappu']),
  CatalogItem('dates', StockUnit.packet, 'Dates', 'ఖర్జూరం', 'खजूर', 'ಖರ್ಜೂರ', 'பேரீச்சம்பழம்', ['khajur']),
  // Vegetables and fruit
  CatalogItem('onion', StockUnit.kg, 'Onion', 'ఉల్లిపాయ', 'प्याज़', 'ಈರುಳ್ಳಿ', 'வெங்காயம்', ['onions', 'pyaz', 'pyaaz', 'ullipaya', 'eerulli']),
  CatalogItem('potato', StockUnit.kg, 'Potato', 'బంగాళాదుంప', 'आलू', 'ಆಲೂಗಡ್ಡೆ', 'உருளைக்கிழங்கு', ['potatoes', 'aloo', 'alu']),
  CatalogItem('tomato', StockUnit.kg, 'Tomato', 'టమాటా', 'टमाटर', 'ಟೊಮೆಟೊ', 'தக்காளி', ['tomatoes', 'tamatar']),
  CatalogItem('garlic', StockUnit.kg, 'Garlic', 'వెల్లుల్లి', 'लहसुन', 'ಬೆಳ್ಳುಳ್ಳಿ', 'பூண்டு', ['lahsun', 'vellulli']),
  CatalogItem('ginger', StockUnit.kg, 'Ginger', 'అల్లం', 'अदरक', 'ಶುಂಠಿ', 'இஞ்சி', ['adrak', 'allam']),
  CatalogItem('green_chilli', StockUnit.kg, 'Green chilli', 'పచ్చి మిర్చి', 'हरी मिर्च', 'ಹಸಿ ಮೆಣಸಿನಕಾಯಿ', 'பச்சை மிளகாய்', ['hari mirch', 'pachi mirchi']),
  CatalogItem('coconut', StockUnit.piece, 'Coconut', 'కొబ్బరికాయ', 'नारियल', 'ತೆಂಗಿನಕಾಯಿ', 'தேங்காய்', ['nariyal', 'kobbari']),
  CatalogItem('lemon', StockUnit.piece, 'Lemon', 'నిమ్మకాయ', 'नींबू', 'ನಿಂಬೆ ಹಣ್ಣು', 'எலுமிச்சை', ['lemons', 'nimbu', 'nimmakaya']),
  CatalogItem('banana', StockUnit.dozen, 'Banana', 'అరటిపండు', 'केला', 'ಬಾಳೆಹಣ್ಣು', 'வாழைப்பழம்', ['bananas', 'kela', 'aratipandu']),
  // Packed food
  CatalogItem('biscuits', StockUnit.packet, 'Biscuits', 'బిస్కెట్లు', 'बिस्कुट', 'ಬಿಸ್ಕತ್', 'பிஸ்கட்', ['biscuit']),
  CatalogItem('noodles', StockUnit.packet, 'Noodles', 'నూడుల్స్', 'नूडल्स', 'ನೂಡಲ್ಸ್', 'நூடுல்ஸ்', ['maggi']),
  CatalogItem('vermicelli', StockUnit.packet, 'Vermicelli', 'సేమియా', 'सेवई', 'ಶಾವಿಗೆ', 'சேமியா', ['semiya', 'sevai']),
  CatalogItem('chips', StockUnit.packet, 'Chips', 'చిప్స్', 'चिप्स', 'ಚಿಪ್ಸ್', 'சிப்ஸ்'),
  CatalogItem('chocolates', StockUnit.piece, 'Chocolates', 'చాక్లెట్లు', 'चॉकलेट', 'ಚಾಕೊಲೇಟ್', 'சாக்லேட்', ['chocolate']),
  CatalogItem('papad', StockUnit.packet, 'Papad', 'అప్పడాలు', 'पापड़', 'ಹಪ್ಪಳ', 'அப்பளம்', ['appadalu']),
  CatalogItem('pickle', StockUnit.piece, 'Pickle', 'ఊరగాయ', 'अचार', 'ಉಪ್ಪಿನಕಾಯಿ', 'ஊறுகாய்', ['achar', 'avakaya']),
  CatalogItem('cold_drink', StockUnit.piece, 'Cold drink', 'కూల్ డ్రింక్', 'कोल्ड ड्रिंक', 'ಕೂಲ್ ಡ್ರಿಂಕ್', 'குளிர் பானம்', ['soda', 'cool drink']),
  CatalogItem('water_bottle', StockUnit.piece, 'Water bottle', 'నీళ్ల సీసా', 'पानी की बोतल', 'ನೀರಿನ ಬಾಟಲಿ', 'தண்ணீர் பாட்டில்', ['water']),
  // Home and personal care
  CatalogItem('bath_soap', StockUnit.piece, 'Bath soap', 'స్నానపు సబ్బు', 'नहाने का साबुन', 'ಸ್ನಾನದ ಸೋಪು', 'குளியல் சோப்பு', ['soap', 'sabun', 'sabbu']),
  CatalogItem('washing_soap', StockUnit.piece, 'Washing soap', 'బట్టల సబ్బు', 'कपड़े धोने का साबुन', 'ಬಟ್ಟೆ ಸೋಪು', 'துணி சோப்பு', ['battala sabbu']),
  CatalogItem('detergent', StockUnit.packet, 'Detergent powder', 'సర్ఫ్', 'कपड़े धोने का पाउडर', 'ಡಿಟರ್ಜೆಂಟ್ ಪುಡಿ', 'சலவைத் தூள்', ['surf', 'washing powder']),
  CatalogItem('dishwash', StockUnit.piece, 'Dishwash bar', 'గిన్నెల సబ్బు', 'बर्तन साबुन', 'ಪಾತ್ರೆ ಸೋಪು', 'பாத்திர சோப்பு', ['vim']),
  CatalogItem('floor_cleaner', StockUnit.piece, 'Floor cleaner', 'ఫినాయిల్', 'फिनाइल', 'ಫಿನೈಲ್', 'ஃபினாயில்', ['phenyl', 'phenoil']),
  CatalogItem('shampoo', StockUnit.piece, 'Shampoo', 'షాంపూ', 'शैम्पू', 'ಶಾಂಪೂ', 'ஷாம்பு'),
  CatalogItem('hair_oil', StockUnit.piece, 'Hair oil', 'తలనూనె', 'बालों का तेल', 'ತಲೆ ಎಣ್ಣೆ', 'தலை எண்ணெய்'),
  CatalogItem('toothpaste', StockUnit.piece, 'Toothpaste', 'టూత్‌పేస్ట్', 'टूथपेस्ट', 'ಟೂತ್‌ಪೇಸ್ಟ್', 'பற்பசை', ['paste']),
  CatalogItem('toothbrush', StockUnit.piece, 'Toothbrush', 'టూత్‌బ్రష్', 'टूथब्रश', 'ಟೂತ್‌ಬ್ರಷ್', 'பல் துலக்கி', ['brush']),
  CatalogItem('sanitary_pads', StockUnit.packet, 'Sanitary pads', 'శానిటరీ ప్యాడ్స్', 'सैनिटरी पैड', 'ಸ್ಯಾನಿಟರಿ ಪ್ಯಾಡ್', 'சானிட்டரி பேட்', ['pads']),
  // Pooja and household
  CatalogItem('agarbatti', StockUnit.packet, 'Agarbatti', 'అగరబత్తి', 'अगरबत्ती', 'ಅಗರಬತ್ತಿ', 'ஊதுபத்தி', ['incense']),
  CatalogItem('camphor', StockUnit.packet, 'Camphor', 'కర్పూరం', 'कपूर', 'ಕರ್ಪೂರ', 'கற்பூரம்', ['kapur', 'karpuram']),
  CatalogItem('matchbox', StockUnit.piece, 'Matchbox', 'అగ్గిపెట్టె', 'माचिस', 'ಬೆಂಕಿ ಪೆಟ್ಟಿಗೆ', 'தீப்பெட்டி', ['machis', 'match box', 'aggipette']),
  CatalogItem('candles', StockUnit.piece, 'Candles', 'కొవ్వొత్తులు', 'मोमबत्ती', 'ಮೇಣದ ಬತ್ತಿ', 'மெழுகுவர்த்தி', ['candle']),
];
