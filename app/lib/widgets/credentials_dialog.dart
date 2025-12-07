import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Credentials Dialog
/// Shows the created username, password, and shareable link
class CredentialsDialog extends StatelessWidget {
  final String username;
  final String password;
  final String appLink = 'https://poker-fa33a.web.app';

  const CredentialsDialog({
    super.key,
    required this.username,
    required this.password,
  });

  void _copyToClipboard(BuildContext context) {
    final text = '''
¡Bienvenido a Poker Imperial!
Tus credenciales de acceso:

Usuario: $username
Contraseña: $password
Link: $appLink

¡Buena suerte en las mesas!
''';
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Credenciales copiadas al portapapeles'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Row(
        children: [
          Icon(Icons.vpn_key, color: Color(0xFFFFD700)),
          SizedBox(width: 12),
          Text('Credenciales Creadas', style: TextStyle(color: Colors.white)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCredentialRow('Usuario', username),
          const SizedBox(height: 12),
          _buildCredentialRow('Contraseña', password),
          const SizedBox(height: 12),
          _buildCredentialRow('Link', appLink),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFD700).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.3)),
            ),
            child: const Text(
              'Comparte estos datos con el nuevo miembro. Se le pedirá cambiar la contraseña al ingresar.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar', style: TextStyle(color: Colors.white54)),
        ),
        ElevatedButton.icon(
          onPressed: () => _copyToClipboard(context),
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('Copiar Todo'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFD700),
            foregroundColor: Colors.black,
          ),
        ),
      ],
    );
  }

  Widget _buildCredentialRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.white10),
          ),
          child: SelectableText(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ],
    );
  }
}
