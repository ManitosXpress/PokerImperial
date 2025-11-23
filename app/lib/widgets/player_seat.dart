import 'package:flutter/material.dart';
import 'poker_card.dart';

class PlayerSeat extends StatelessWidget {
  final String name;
  final String chips;
  final bool isMe;
  final bool isActive;
  final bool isDealer;
  final bool isFolded;
  final List<String>? cards;

  const PlayerSeat({
    super.key,
    required this.name,
    required this.chips,
    this.isMe = false,
    this.isActive = true,
    this.isDealer = false,
    this.isFolded = false,
    this.cards,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (cards != null && cards!.isNotEmpty)
          SizedBox(
            height: 50, // Increased height to avoid overflow
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: cards!.map((c) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.0),
                child: PokerCard(cardCode: c, width: 34), // Slightly larger cards
              )).toList(),
            ),
          ),
        const SizedBox(height: 4),
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isActive ? Colors.green : Colors.grey,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 5,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: 25,
                backgroundColor: Colors.grey[800],
                child: Text(
                  name.substring(0, 1).toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ),
            if (isFolded)
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.7),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Text(
                  'Fold',
                  style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
        if (isDealer)
          Container(
            margin: const EdgeInsets.only(top: 4),
            padding: const EdgeInsets.all(4),
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Text('D', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
          ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isMe ? Colors.black87 : Colors.black54,
            borderRadius: BorderRadius.circular(12),
            border: isMe ? Border.all(color: Colors.amber, width: 2) : null,
          ),
          child: Column(
            children: [
              Text(
                name,
                style: TextStyle(
                  color: isMe ? Colors.amber : Colors.white,
                  fontSize: isMe ? 12 : 10,
                  fontWeight: isMe ? FontWeight.bold : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: isMe ? 16 : 14,
                    height: isMe ? 16 : 14,
                    decoration: BoxDecoration(
                      color: Colors.amber,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      'C',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: isMe ? 11 : 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    chips,
                    style: TextStyle(
                      color: Colors.amber,
                      fontSize: isMe ? 14 : 11,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(
                          color: Colors.black,
                          blurRadius: 2,
                          offset: Offset(1, 1),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
