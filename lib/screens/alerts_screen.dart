import 'package:flutter/material.dart';

class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Mock data based on the spec
    final List<Map<String, dynamic>> alerts = [
      {
        'type': 'Social',
        'message': '@james started following you',
        'time': '2m ago',
        'icon': Icons.person_add,
        'color': Colors.blue,
      },
      {
        'type': 'Moderation',
        'message': 'Your video is temporarily private',
        'time': '1h ago',
        'icon': Icons.gavel,
        'color': Colors.orange,
      },
      {
        'type': 'License',
        'message': 'Your video was licensed · Sale ₩10,000',
        'time': '3h ago',
        'icon': Icons.monetization_on,
        'color': Colors.green,
      },
      {
        'type': 'Earnings',
        'message': 'Your monthly creator revenue has been finalized',
        'time': '1d ago',
        'icon': Icons.account_balance_wallet,
        'color': Colors.purple,
      },
    ];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'Alerts',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        centerTitle: true,
      ),
      body: ListView.separated(
        itemCount: alerts.length,
        separatorBuilder: (context, index) => const Divider(color: Colors.white24, height: 1),
        itemBuilder: (context, index) {
          final alert = alerts[index];
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: alert['color'].withOpacity(0.2),
              child: Icon(alert['icon'], color: alert['color']),
            ),
            title: Text(
              alert['message'],
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
            subtitle: Text(
              alert['time'],
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
            onTap: () {},
          );
        },
      ),
    );
  }
}
