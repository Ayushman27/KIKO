import 'package:flutter/material.dart';

class ApprovalsScreen extends StatefulWidget {
  const ApprovalsScreen({super.key});

  @override
  State<ApprovalsScreen> createState() => _ApprovalsScreenState();
}

class _ApprovalsScreenState extends State<ApprovalsScreen> {
  final List<Map<String, String>> _pending = [
    {
      'id': 'appr_101',
      'action': 'submit_job_application',
      'desc': 'Submit Job Application to TechCorp for Senior AI Engineer',
      'risk': 'HIGH'
    }
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Action Approvals', style: TextStyle(color: Color(0xFF00F0FF))),
        backgroundColor: const Color(0xFF0F172A),
      ),
      body: _pending.isEmpty
          ? const Center(child: Text("No pending approvals", style: TextStyle(color: Colors.grey)))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _pending.length,
              itemBuilder: (context, index) {
                final item = _pending[index];
                return Card(
                  color: const Color(0xFF0F172A),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: Colors.amber, width: 0.8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(item['action']!, style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.2), borderRadius: BorderRadius.circular(6)),
                              child: Text("${item['risk']} RISK", style: const TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                            )
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(item['desc']!, style: const TextStyle(color: Colors.white, fontSize: 13)),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                                onPressed: () {
                                  setState(() => _pending.removeAt(index));
                                },
                                child: const Text('Approve', style: TextStyle(color: Colors.white)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.redAccent)),
                                onPressed: () {
                                  setState(() => _pending.removeAt(index));
                                },
                                child: const Text('Reject', style: TextStyle(color: Colors.redAccent)),
                              ),
                            )
                          ],
                        )
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
