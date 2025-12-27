import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LiveFeedList extends StatelessWidget {
  final String? clubId;
  final Function(String tableId)? onEventTap;

  const LiveFeedList({Key? key, this.clubId, this.onEventTap}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Query query = FirebaseFirestore.instance
        .collection('live_feed')
        .orderBy('timestamp', descending: true)
        .limit(20);

    if (clubId != null) {
      query = query.where('clubId', isEqualTo: clubId);
    } else {
      query = query.where('visibility', isEqualTo: 'PUBLIC');
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) return const SizedBox.shrink();
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(strokeWidth: 2));

        final docs = snapshot.data!.docs;
        if (docs.isEmpty) return const SizedBox.shrink();

        return ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            return _buildFeedItem(data);
          },
        );
      },
    );
  }

  Widget _buildFeedItem(Map<String, dynamic> data) {
    IconData icon = Icons.emoji_events;
    Color iconColor = Colors.amber;
    
    switch (data['type']) {
        case 'BIG_POT':
            icon = Icons.monetization_on;
            iconColor = Colors.amber;
            break;
        case 'JACKPOT':
            icon = Icons.local_fire_department;
            iconColor = Colors.redAccent;
            break;
        case 'TOURNAMENT_WIN':
            icon = Icons.emoji_events;
            iconColor = Colors.purple;
            break;
        case 'TABLE_CREATED':
            icon = Icons.table_restaurant;
            iconColor = Colors.green;
            break;
    }

    final tableId = data['metadata'] != null ? data['metadata']['tableId'] as String? : null;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3), // Glassmorphism background
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: ListTile(
        dense: true,
        leading: Icon(icon, color: iconColor, size: 20),
        title: Text(data['title'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
        subtitle: Text(data['subtitle'] ?? '', style: const TextStyle(color: Colors.white70, fontSize: 11)),
        trailing: data['amount'] != null 
          ? Text("+${data['amount']}", style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)) 
          : null,
        onTap: (tableId != null && onEventTap != null) ? () => onEventTap!(tableId) : null,
      ),
    );
  }
}
