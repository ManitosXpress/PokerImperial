import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/club_provider.dart';
import 'create_club_screen.dart';
import '../../widgets/club_request_modal.dart';
import 'club_tournaments_screen.dart';
import 'club_leaderboard_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../widgets/poker_loading_indicator.dart';

class ClubDashboardScreen extends StatefulWidget {
  const ClubDashboardScreen({super.key});

  @override
  State<ClubDashboardScreen> createState() => _ClubDashboardScreenState();
}

class _ClubDashboardScreenState extends State<ClubDashboardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  int _totalMemberCredits = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    Future.microtask(() async {
      final provider = Provider.of<ClubProvider>(context, listen: false);
      await provider.fetchClubs();
      if (provider.myClub != null) {
        _fetchTotalMemberCredits(provider.myClub!['id']);
      }
    });
  }

  Future<void> _fetchTotalMemberCredits(String clubId) async {
    try {
      final members = await Provider.of<ClubProvider>(context, listen: false)
          .fetchClubLeaderboard(clubId);
      final total = members.fold<int>(0, (sum, member) => sum + (member['credits'] as int? ?? 0));
      if (mounted) {
        setState(() {
          _totalMemberCredits = total;
        });
      }
    } catch (e) {
      debugPrint('Error calculating total credits: $e');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final clubProvider = Provider.of<ClubProvider>(context);
    final myClub = clubProvider.myClub;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('CLUBS', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.black.withOpacity(0.8), Colors.transparent],
            ),
          ),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/images/poker3_background.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(0.3),
                Colors.black.withOpacity(0.8),
              ],
            ),
          ),
          child: myClub != null
              ? _buildMyClubView(myClub)
              : _buildClubListView(clubProvider),
        ),
      ),
      floatingActionButton: myClub == null
          ? FloatingActionButton.extended(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => const ClubRequestModal(),
                );
              },
              label: const Text('CREATE CLUB', style: TextStyle(fontWeight: FontWeight.bold)),
              icon: const Icon(Icons.add),
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.black,
            )
          : null,
    );
  }

  Widget _buildMyClubView(Map<String, dynamic> club) {
    return Column(
      children: [
        const SizedBox(height: 100), // AppBar spacer
        // Club Header
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFFD700), width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFD700).withOpacity(0.3),
                      blurRadius: 15,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const CircleAvatar(
                  radius: 40,
                  backgroundColor: Color(0xFF1A1A2E),
                  child: Icon(Icons.shield, size: 40, color: Color(0xFFFFD700)),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                club['name'],
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.2,
                  shadows: [Shadow(color: Colors.black, blurRadius: 4, offset: Offset(0, 2))],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                club['description'],
                style: const TextStyle(color: Colors.white70, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 24),
        
        // Club Wallet Card
        // Club Wallet Card (Only visible to Owner)
        Consumer<ClubProvider>(
          builder: (context, provider, child) {
            final currentUserId = FirebaseAuth.instance.currentUser?.uid;
            // Check role from provider (ensure fetchClubs has run)
            final isClubOwner = provider.currentUserRole == 'club' && club['ownerId'] == currentUserId;
            
            // if (!isClubOwner) return const SizedBox.shrink(); // Removed to show balance to all

            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2A2A2A), Color(0xFF1A1A1A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.account_balance_wallet, color: Colors.amber.shade400, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            'CLUB WALLET',
                            style: TextStyle(
                              color: Colors.amber.shade400,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$_totalMemberCredits',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (isClubOwner)
                        InkWell(
                          onTap: () => _showInviteMemberDialog(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.green),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.person_add, color: Colors.green, size: 16),
                                SizedBox(width: 4),
                                Text(
                                  'Add Members',
                                  style: TextStyle(
                                    color: Colors.green,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  // Owner Controls Button
                  if (isClubOwner)
                    ElevatedButton(
                      onPressed: () => _showWalletManagementDialog(context, club['id'], club['name']),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFD700),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      child: const Text('Manage', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            );
          },
        ),

        const SizedBox(height: 24),

        // Tabs
        Container(
          height: 50,
          margin: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: Colors.white10),
          ),
          child: TabBar(
            controller: _tabController,
            indicator: BoxDecoration(
              color: const Color(0xFFFFD700),
              borderRadius: BorderRadius.circular(25),
            ),
            labelColor: Colors.black,
            unselectedLabelColor: Colors.white60,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold),
            tabs: const [
              Tab(text: 'MEMBERS'),
              Tab(text: 'TOURNAMENTS'),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Tab Content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // Members Tab (Embedded Leaderboard)
              ClubLeaderboardScreen(
                clubId: club['id'],
                ownerId: club['ownerId'],
                isEmbedded: true, // We'll add this flag
              ),
              // Tournaments Tab
              ClubTournamentsScreen(
                clubId: club['id'],
                isOwner: club['ownerId'] == Provider.of<ClubProvider>(context, listen: false).myClub?['ownerId'],
                isEmbedded: true, // We'll add this flag
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildClubListView(ClubProvider provider) {
    if (provider.isLoading) {
      return const Center(
        child: PokerLoadingIndicator(
          statusText: 'Loading Clubs...',
          color: Color(0xFFFFD700),
        ),
      );
    }

    if (provider.errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(provider.errorMessage!, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => provider.fetchClubs(),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700), foregroundColor: Colors.black),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (provider.clubs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, color: Colors.white.withOpacity(0.3), size: 64),
            const SizedBox(height: 16),
            const Text(
              'No clubs found',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Create one to get started!',
              style: TextStyle(color: Colors.white54),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => provider.fetchClubs(),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700), foregroundColor: Colors.black),
              child: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFFFFD700),
      backgroundColor: const Color(0xFF1A1A2E),
      onRefresh: () => provider.fetchClubs(),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 100, 16, 16), // Top padding for transparent AppBar
        itemCount: provider.clubs.length,
        itemBuilder: (context, index) {
          final club = provider.clubs[index];
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.white.withOpacity(0.1), Colors.white.withOpacity(0.05)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.amber.withOpacity(0.5)),
                ),
                child: const Icon(Icons.shield, color: Colors.amber),
              ),
              title: Text(
                club['name'],
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              ),
              subtitle: Text(
                '${club['memberCount']} members',
                style: const TextStyle(color: Colors.white54),
              ),
              trailing: ElevatedButton(
                onPressed: () => _showJoinClubDialog(context, club['id'], club['name']),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                ),
                child: const Text('Join'),
              ),
            ),
          );
        },
      ),
    );
  }


  void _showJoinClubDialog(BuildContext context, String clubId, String clubName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: Text('Unirse a $clubName', style: const TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '¡Bienvenido al Club!',
              style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 16),
            const Text(
              'Al unirte a este club, podrás participar en torneos exclusivos y ganar fichas.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            const Text(
              'Importante:',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Para jugar, necesitarás créditos. Debes contactar al líder del club para comprar créditos y recargar tu billetera.',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Provider.of<ClubProvider>(context, listen: false).joinClub(clubId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.black,
            ),
            child: const Text('Entrar al Club'),
          ),
        ],
      ),
    );
  }

  void _showInviteMemberDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => const _InviteMemberDialog(),
    );
  }

  void _showWalletManagementDialog(BuildContext context, String clubId, String clubName) {
    showDialog(
      context: context,
      builder: (context) => _WalletManagementDialog(clubId: clubId, clubName: clubName),
    );
  }
}

class _WalletManagementDialog extends StatefulWidget {
  final String clubId;
  final String clubName;

  const _WalletManagementDialog({
    required this.clubId,
    required this.clubName,
  });

  @override
  State<_WalletManagementDialog> createState() => _WalletManagementDialogState();
}

class _WalletManagementDialogState extends State<_WalletManagementDialog> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _members = [];
  String? _selectedMemberId;
  final TextEditingController _amountController = TextEditingController();
  static const String telegramBotUrl = 'http://t.me/AgenteBingobot';

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    setState(() => _isLoading = true);
    try {
      // Reuse leaderboard fetch to get members
      final members = await Provider.of<ClubProvider>(context, listen: false)
          .fetchClubLeaderboard(widget.clubId);
      if (mounted) {
        setState(() {
          _members = members;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar miembros: $e')),
        );
      }
    }
  }

  Future<void> _transferCredits() async {
    if (_selectedMemberId == null || _amountController.text.isEmpty) return;

    final amount = int.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor ingresa una cantidad válida')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await Provider.of<ClubProvider>(context, listen: false)
          .transferClubToMember(widget.clubId, _selectedMemberId!, amount);
      
      if (mounted) {
        Navigator.pop(context); // Close dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('¡Transferencia exitosa!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error en la transferencia: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _requestCreditsViaTelegram() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final amountText = _amountController.text.isEmpty ? '0.00' : _amountController.text;
    
    // 1. Create message with specific format
    final message = 'Solicitud de recarga:\n'
        'ID: ${user.uid}\n'
        'Email: ${user.email ?? "No email"}\n'
        'Monto: $amountText';
    
    // 2. Copy to clipboard
    await Clipboard.setData(ClipboardData(text: message));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mensaje copiado. Pégalo en Telegram.')),
      );
      
      // 3. Close dialog
      Navigator.pop(context);
    }

    // 4. Launch Telegram
    final Uri url = Uri.parse(telegramBotUrl);
    try {
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw Exception('No se pudo abrir Telegram');
      }
    } catch (e) {
      debugPrint('Error launching Telegram: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A2E),
      title: const Text('Gestionar Billetera del Club', style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: double.maxFinite,
        child: _isLoading && _members.isEmpty
            ? const Center(child: PokerLoadingIndicator(size: 40))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Transferir a Miembro',
                    style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _selectedMemberId,
                    dropdownColor: const Color(0xFF16213E),
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Seleccionar Miembro',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.amber),
                      ),
                    ),
                    items: _members.map((member) {
                      return DropdownMenuItem(
                        value: member['uid'] as String,
                        child: Text(
                          member['displayName'] ?? 'Desconocido',
                          style: const TextStyle(color: Colors.white),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) => setState(() => _selectedMemberId = value),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _amountController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Cantidad',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.amber),
                      ),
                      suffixText: 'Créditos',
                      suffixStyle: TextStyle(color: Colors.amber),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Divider(color: Colors.white24),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _requestCreditsViaTelegram,
                      icon: const Icon(Icons.telegram, size: 28),
                      label: const Text('Solicitar Recarga (Telegram)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0088cc), // Telegram Blue
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar', style: TextStyle(color: Colors.white54)),
        ),
        ElevatedButton(
          onPressed: _isLoading ? null : _transferCredits,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFD700),
            foregroundColor: Colors.black,
          ),
          child: _isLoading
              ? const SizedBox(width: 20, height: 20, child: PokerLoadingIndicator(size: 20, color: Colors.black))
              : const Text('Transferir'),
        ),
      ],
    );
  }
}

class _InviteMemberDialog extends StatefulWidget {
  const _InviteMemberDialog();

  @override
  State<_InviteMemberDialog> createState() => _InviteMemberDialogState();
}

class _InviteMemberDialogState extends State<_InviteMemberDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  String _selectedRole = 'player';
  bool _isLoading = false;
  String? _inviteLink;

  Future<void> _generateLink() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final link = await Provider.of<ClubProvider>(context, listen: false)
          .createClubInvite(_selectedRole, _nameController.text);
      
      if (mounted) {
        setState(() {
          _inviteLink = link;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A2E),
      title: const Text('Invitar Miembro', style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: double.maxFinite,
        child: _inviteLink != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 48),
                  const SizedBox(height: 16),
                  const Text(
                    '¡Link Generado!',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: SelectableText(
                      _inviteLink!,
                      style: const TextStyle(color: Colors.amber),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _inviteLink!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Link copiado al portapapeles')),
                      );
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copiar Link'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD700),
                      foregroundColor: Colors.black,
                    ),
                  ),
                ],
              )
            : Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      controller: _nameController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Nombre de Referencia (Apodo)',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.amber),
                        ),
                      ),
                      validator: (v) => v?.isEmpty == true ? 'Requerido' : null,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      value: _selectedRole,
                      dropdownColor: const Color(0xFF16213E),
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Rol',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.white24),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.amber),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'player', child: Text('Jugador')),
                        DropdownMenuItem(value: 'seller', child: Text('Vendedor')),
                      ],
                      onChanged: (v) => setState(() => _selectedRole = v!),
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar', style: TextStyle(color: Colors.white54)),
        ),
        if (_inviteLink == null)
          ElevatedButton(
            onPressed: _isLoading ? null : _generateLink,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFFD700),
              foregroundColor: Colors.black,
            ),
            child: _isLoading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Generar Link'),
          ),
      ],
    );
  }
}
