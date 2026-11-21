import 'package:flutter/material.dart';

class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity & Audit Logs', style: TextStyle(color: Color(0xFF00F0FF))),
        backgroundColor: const Color(0xFF0F172A),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          ListTile(
            leading: Icon(Icons.history, color: Color(0xFF00F0FF)),
            title: Text("Executed tool 'create_folder'", style: TextStyle(color: Colors.white, fontSize: 13)),
            subtitle: Text("Risk: LOW • Result: SUCCESS • 2 mins ago", style: TextStyle(color: Colors.grey, fontSize: 11)),
          ),
          ListTile(
            leading: Icon(Icons.history, color: Color(0xFF00F0FF)),
            title: Text("Executed tool 'open_application'", style: TextStyle(color: Colors.white, fontSize: 13)),
            subtitle: Text("Risk: LOW • Result: SUCCESS • 5 mins ago", style: TextStyle(color: Colors.grey, fontSize: 11)),
          ),
        ],
      ),
    );
  }
}
