import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../widgets/poker_loading_indicator.dart';

class UserManagementView extends StatefulWidget {
  const UserManagementView({super.key});

  @override
  State<UserManagementView> createState() => _UserManagementViewState();
}

class _UserManagementViewState extends State<UserManagementView> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: TextField(
            controller: _searchController,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Buscar por email, UID o nombre...',
              hintStyle: const TextStyle(color: Colors.white54),
              prefixIcon: const Icon(Icons.search, color: Colors.white54),
              filled: true,
              fillColor: Colors.white10,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear, color: Colors.white54),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
              ),
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _firestore.collection('users')
                .orderBy('createdAt', descending: true)
                .limit(50)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
              if (!snapshot.hasData) return const Center(child: PokerLoadingIndicator(size: 40, color: Colors.amber));

              var docs = snapshot.data!.docs;
              
              // Client-side filter for now (Firestore doesn't support partial text search easily)
              if (_searchQuery.isNotEmpty) {
                docs = docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final email = (data['email'] ?? '').toString().toLowerCase();
                  final name = (data['displayName'] ?? '').toString().toLowerCase();
                  final uid = doc.id.toLowerCase();
                  final q = _searchQuery.toLowerCase();
                  return email.contains(q) || name.contains(q) || uid.contains(q);
                }).toList();
              }

              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final uid = docs[index].id;
                  return _buildUserTile(uid, data);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildUserTile(String uid, Map<String, dynamic> data) {
    final role = data['role'] ?? 'player';
    final credit = data['credit'] ?? 0;
    final email = data['email'] ?? 'No Email';
    final name = data['displayName'] ?? 'No Name';

    Color roleColor = Colors.grey;
    if (role == 'admin') roleColor = Colors.red;
    if (role == 'club') roleColor = Colors.purple;
    if (role == 'seller') roleColor = Colors.blue;

    return Card(
      color: Colors.white10,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: roleColor.withOpacity(0.2),
          child: Icon(Icons.person, color: roleColor),
        ),
        title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(email, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            Text('UID: $uid', style: const TextStyle(color: Colors.white30, fontSize: 10)),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(role.toUpperCase(), style: TextStyle(color: roleColor, fontWeight: FontWeight.bold, fontSize: 10)),
                Text('\$${credit.toString()}', style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold)),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.white54),
              onPressed: () => _showEditRoleDialog(uid, role, name),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditRoleDialog(String uid, String currentRole, String name) {
    String selectedRole = currentRole;
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          title: Text('Editar Rol: $name', style: const TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedRole,
                dropdownColor: const Color(0xFF16213E),
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Nuevo Rol',
                  labelStyle: TextStyle(color: Colors.white70),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                ),
                items: const [
                  DropdownMenuItem(value: 'player', child: Text('JUGADOR')),
                  DropdownMenuItem(value: 'seller', child: Text('VENDEDOR')),
                  DropdownMenuItem(value: 'club', child: Text('DUEÑO DE CLUB')),
                  DropdownMenuItem(value: 'admin', child: Text('ADMINISTRADOR')),
                ],
                onChanged: (val) => setState(() => selectedRole = val!),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: isLoading ? null : () async {
                setState(() => isLoading = true);
                try {
                  await _functions.httpsCallable('adminSetUserRoleFunction').call({
                    'targetUid': uid,
                    'newRole': selectedRole,
                  });
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Rol actualizado correctamente')),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    setState(() => isLoading = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error: $e')),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, foregroundColor: Colors.black),
              child: isLoading 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                : const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
  }
}
