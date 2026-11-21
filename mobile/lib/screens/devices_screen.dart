import 'package:flutter/material.dart';
import 'login_pairing_screen.dart';

class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paired Devices', style: TextStyle(color: Color(0xFF00F0FF))),
        backgroundColor: const Color(0xFF0F172A),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: const Color(0xFF0F172A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFF00F0FF), width: 0.5),
            ),
            child: const ListTile(
              leading: Icon(Icons.laptop, color: Color(0xFF00F0FF), size: 36),
              title: Text("Ayushman's Windows Laptop", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              subtitle: Text("Status: ONLINE • Silent Background Daemon", style: TextStyle(color: Colors.grey, fontSize: 12)),
              trailing: Icon(Icons.check_circle, color: Colors.greenAccent),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              side: const BorderSide(color: Color(0xFF00F0FF)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(Icons.add, color: Color(0xFF00F0FF)),
            label: const Text('Pair New Windows Computer', style: TextStyle(color: Color(0xFF00F0FF))),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginPairingScreen()));
            },
          )
        ],
      ),
    );
  }
}
