import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../providers/language_provider.dart';
import '../providers/wallet_provider.dart';
import '../providers/auth_provider.dart' as app_auth;
import '../widgets/add_credits_dialog.dart';
import '../widgets/change_password_dialog.dart';
import '../services/credits_service.dart';
import 'login_screen.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../providers/club_provider.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    final walletProvider = Provider.of<WalletProvider>(context);
    final clubProvider = Provider.of<ClubProvider>(context);
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/poker_background.png'),
            fit: BoxFit.cover,
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.7),
                Colors.black.withOpacity(0.85),
                Colors.black.withOpacity(0.9),
              ],
            ),
          ),
          child: SafeArea(
            child: Column(
              children: [
                // Header with back button
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back, color: Color(0xFFC89A4E)), // Gold
                      ),
                      const SizedBox(width: 8),
                      Text(
                        languageProvider.getText('my_profile'),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFC89A4E), // Gold
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Main Content
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        // Profile Header Section
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFFC89A4E), // Gold
                              width: 2,
                            ),
                          ),
                          child: Column(
                            children: [
                              // Avatar
                              CircleAvatar(
                                radius: 50,
                                backgroundColor: const Color(0xFFC89A4E), // Gold
                                backgroundImage: user?.photoURL != null
                                    ? NetworkImage(user!.photoURL!)
                                    : null,
                                child: user?.photoURL == null
                                    ? Text(
                                        (user?.displayName?.isNotEmpty == true
                                            ? user!.displayName![0].toUpperCase()
                                            : user?.email?[0].toUpperCase() ?? '?'),
                                        style: const TextStyle(
                                          fontSize: 40,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF1C1C1C), // Black
                                        ),
                                      )
                                    : null,
                              ),
                              const SizedBox(height: 16),
                              // Display Name
                              Text(
                                user?.displayName ?? user?.email?.split('@')[0] ?? 'User',
                                style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFC89A4E), // Gold
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Email
                              Text(
                                user?.email ?? '',
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Color(0xFFF1E3D3), // Beige
                                ),
                              ),
                              const SizedBox(height: 20),
                              // Buttons Row
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  // Edit Profile Button
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (_) => const EditProfileDialog(),
                                        );
                                      },
                                      icon: const Icon(Icons.edit, size: 18, color: Color(0xFFC89A4E)),
                                      label: Text(languageProvider.getText('edit_profile')),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFFC89A4E),
                                        side: const BorderSide(color: Color(0xFFC89A4E)),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // Change Password Button
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          barrierDismissible: false,
                                          builder: (_) => const ChangePasswordDialog(),
                                        );
                                      },
                                      icon: const Icon(Icons.lock_reset, size: 18, color: Color(0xFFC89A4E)),
                                      label: Text(
                                        languageProvider.currentLocale.languageCode == 'en'
                                            ? 'Password'
                                            : 'Contraseña',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFFC89A4E),
                                        side: const BorderSide(color: Color(0xFFC89A4E)),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 12,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        
                        // Wallet Section
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFFC89A4E), // Gold
                              width: 2,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    languageProvider.getText('wallet'),
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFC89A4E), // Gold
                                    ),
                                  ),
                                  if (clubProvider.myClub != null)
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (_) => const AddCreditsDialog(isClubRequest: true),
                                        );
                                      },
                                      icon: const Icon(
                                        Icons.add,
                                        size: 16,
                                        color: Colors.black,
                                      ),
                                      label: const Text(
                                        'Solicitar',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFFC89A4E), // Gold
                                        foregroundColor: const Color(0xFF1C1C1C), // Black
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                      ),
                                    )
                                  else
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (_) => const AddCreditsDialog(),
                                        );
                                      },
                                      icon: const Icon(
                                        Icons.add,
                                        size: 16,
                                        color: Colors.black,
                                      ),
                                      label: Text(
                                        languageProvider.currentLocale.languageCode == 'en'
                                            ? 'Add'
                                            : 'Agregar',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFFC89A4E), // Gold
                                        foregroundColor: const Color(0xFF1C1C1C), // Black
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              // Balance Display
                              Row(
                                children: [
                                  const Icon(
                                    Icons.account_balance_wallet,
                                    color: Color(0xFFC89A4E), // Gold
                                    size: 32,
                                  ),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        languageProvider.getText('balance'),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFFF1E3D3), // Beige
                                        ),
                                      ),
                                      Text(
                                        '\$${walletProvider.balance.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          fontSize: 28,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFFC89A4E), // Gold
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        
                        // Transaction History Section
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFFC89A4E), // Gold
                              width: 2,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                languageProvider.getText('transactions'),
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFFC89A4E), // Gold
                                ),
                              ),
                              const SizedBox(height: 16),
                              StreamBuilder<List<TransactionLog>>(
                                stream: walletProvider.getTransactionHistory(),
                                builder: (context, snapshot) {
                                  if (snapshot.connectionState == ConnectionState.waiting) {
                                    return const Center(
                                      child: CircularProgressIndicator(
                                        color: Color(0xFFC89A4E), // Gold
                                      ),
                                    );
                                  }
                                  
                                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                                    return Center(
                                      child: Padding(
                                        padding: const EdgeInsets.all(32.0),
                                        child: Text(
                                          languageProvider.getText('no_transactions'),
                                          style: TextStyle(
                                            color: Color(0xFFF1E3D3), // Beige
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                  
                                  final transactions = snapshot.data!;
                                  return ListView.separated(
                                    shrinkWrap: true,
                                    physics: const NeverScrollableScrollPhysics(),
                                    itemCount: transactions.length,
                                    separatorBuilder: (_, __) => Divider(
                                      color: Colors.white.withOpacity(0.1),
                                      height: 24,
                                    ),
                                    itemBuilder: (context, index) {
                                      final transaction = transactions[index];
                                      final isCredit = transaction.type == 'credit';
                                      
                                      return Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: (isCredit ? Colors.green : Colors.red)
                                                  .withOpacity(0.2),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Icon(
                                              isCredit ? Icons.add : Icons.remove,
                                              color: isCredit ? Colors.green : Colors.red,
                                              size: 20,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  transaction.reason,
                                                  style: const TextStyle(
                                                    color: Color(0xFFF1E3D3), // Beige
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  _formatDate(transaction.timestamp),
                                                  style: TextStyle(
                                                    color: Color(0xFFF1E3D3).withOpacity(0.7), // Beige dimmed
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Text(
                                            '${isCredit ? '+' : '-'}\$${transaction.amount.toStringAsFixed(2)}',
                                            style: TextStyle(
                                              color: isCredit ? Colors.green : Colors.red,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                        
                        // Sign Out Button
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final authProvider = context.read<app_auth.AuthProvider>();
                              await authProvider.signOut();
                              if (context.mounted) {
                                Navigator.of(context).pushAndRemoveUntil(
                                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                                  (route) => false,
                                );
                              }
                            },
                            icon: const Icon(Icons.logout),
                            label: Text(languageProvider.getText('sign_out')),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red.shade300,
                              side: BorderSide(color: Colors.red.shade300.withOpacity(0.5)),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return 'Just now';
        }
        return '${difference.inMinutes}m ago';
      }
      return '${difference.inHours}h ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}

// Edit Profile Dialog
class EditProfileDialog extends StatefulWidget {
  const EditProfileDialog({super.key});

  @override
  State<EditProfileDialog> createState() => _EditProfileDialogState();
}

class _EditProfileDialogState extends State<EditProfileDialog> {
  late TextEditingController _displayNameController;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _displayNameController = TextEditingController(
      text: user?.displayName ?? user?.email?.split('@')[0] ?? '',
    );
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  Future<void> _saveProfile() async {
    final displayName = _displayNameController.text.trim();
    if (displayName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Display name cannot be empty'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      await user?.updateDisplayName(displayName);
      await user?.reload();
      
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Profile updated successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating profile: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    
    return AlertDialog(
      backgroundColor: const Color(0xFF1C1C1C), // Black
      title: Text(
        languageProvider.getText('edit_profile'),
        style: const TextStyle(color: Color(0xFFC89A4E)), // Gold
      ),
      content: TextField(
        controller: _displayNameController,
        style: const TextStyle(color: Color(0xFFF1E3D3)), // Beige
        decoration: InputDecoration(
          labelText: languageProvider.getText('display_name'),
          labelStyle: const TextStyle(color: Color(0xFFC89A4E)), // Gold
          filled: true,
          fillColor: Colors.white.withOpacity(0.1),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFC89A4E)), // Gold
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFC89A4E), width: 2), // Gold
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.pop(context),
          child: Text(
            languageProvider.getText('cancel'),
            style: const TextStyle(color: Color(0xFFF1E3D3)), // Beige
          ),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _saveProfile,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFC89A4E), // Gold
            foregroundColor: const Color(0xFF1C1C1C), // Black
          ),
          child: _isLoading
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : Text(languageProvider.getText('save')),
        ),
      ],
    );
  }
}
