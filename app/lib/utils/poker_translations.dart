// Poker hand translation from English to Spanish
String translatePokerHand(String englishHand) {
  // Common poker hand patterns
  final translations = {
    // Hand types
    'High Card': 'Carta Alta',
    'Pair': 'Par',
    'Two Pair': 'Doble Par',
    'Three of a Kind': 'Trío',
    'Straight': 'Escalera',
    'Flush': 'Color',
    'Full House': 'Full',
    'Four of a Kind': 'Poker',
    'Straight Flush': 'Escalera de Color',
    'Royal Flush': 'Escalera Real',
    
    // Card ranks
    'Ace': 'As',
    'King': 'Rey',
    'Queen': 'Reina',
    'Jack': 'Jota',
    
    // Plurals
    '\'s': '',
    'high': 'alta',
  };
  
  String result = englishHand;
  
  // Replace each translation
  translations.forEach((english, spanish) {
    result = result.replaceAll(english, spanish);
  });
  
  return result;
}
