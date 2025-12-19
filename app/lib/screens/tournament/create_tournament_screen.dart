import 'package:flutter/material.dart';
import '../../widgets/imperial_currency.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../providers/tournament_provider.dart';
import '../../widgets/tournament_scope_card.dart';
import '../../widgets/tournament_speed_selector.dart';
import '../../widgets/tournament/prize_pool_calculator.dart';

class CreateTournamentScreen extends StatefulWidget {
  final String? clubId;

  const CreateTournamentScreen({super.key, this.clubId});

  @override
  State<CreateTournamentScreen> createState() => _CreateTournamentScreenState();
}

class _CreateTournamentScreenState extends State<CreateTournamentScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // Form fields
  String _selectedScope = 'CLUB'; // Default to CLUB
  String _selectedType = 'FREEZEOUT'; // 🧊 FREEZEOUT, 🔄 REBUY, 🥊 BOUNTY, ⚡ TURBO
  String _selectedBlindSpeed = 'NORMAL'; // SLOW, NORMAL, TURBO
  bool _rebuyAllowed = false;
  int _bountyAmount = 0; // Para torneos BOUNTY
  final _nameController = TextEditingController();
  final _buyInController = TextEditingController(text: '100');
  int _estimatedPlayers = 10;
  
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    // Si viene de un club, forzar CLUB scope
    if (widget.clubId != null) {
      _selectedScope = 'CLUB';
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _buyInController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _createTournament() async {
    if (_nameController.text.isEmpty || _buyInController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor completa todos los campos'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Validación de Club
    if (_selectedScope == 'CLUB' && widget.clubId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Debes administrar un club para crear este torneo'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      final buyIn = int.parse(_buyInController.text);
      
      // Construir settings según el tipo de torneo
      final settings = {
        'rebuyAllowed': _rebuyAllowed,
        'bountyAmount': _selectedType == 'BOUNTY' ? _bountyAmount : 0,
        'blindSpeed': _selectedBlindSpeed,
      };
      
      await Provider.of<TournamentProvider>(context, listen: false).createTournamentPremium(
        name: _nameController.text,
        buyIn: buyIn,
        scope: _selectedScope,
        type: _selectedType,
        settings: settings,
        clubId: _selectedScope == 'CLUB' ? widget.clubId : null,
        estimatedPlayers: _estimatedPlayers,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('¡Torneo creado exitosamente!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        // Extraer mensaje de error limpio si es posible
        String errorMessage = e.toString();
        if (errorMessage.contains('permission-denied')) {
          errorMessage = 'Permisos insuficientes para crear este torneo.';
        } else if (errorMessage.contains(']')) {
           // Intenta limpiar errores tipo [firebase_functions/...]
           errorMessage = errorMessage.split(']').last.trim();
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $errorMessage'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'CREAR TORNEO IMPERIAL',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1A1A2E), Color(0xFF16213E), Color(0xFF0F0F1E)],
          ),
        ),
        child: Stack(
          children: [
            // Background Image
            Positioned.fill(
              child: Image.asset(
                'assets/images/tournament_bg.jpg',
                fit: BoxFit.cover,
              ),
            ),
            // Dark Overlay
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.85),
              ),
            ),
            // Content
            Padding(
              padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top + kToolbarHeight),
              child: Column(
                children: [
                  // Progress Indicator
                  _buildProgressIndicator(),
                  // PageView
                  Expanded(
                    child: PageView(
                      controller: _pageController,
                      physics: const NeverScrollableScrollPhysics(),
                      onPageChanged: (index) {
                        setState(() => _currentPage = index);
                      },
                      children: [
                        _buildScopeSelectionPage(),
                        _buildConfigurationPage(),
                        _buildConfirmationPage(),
                      ],
                    ),
                  ),
                  // Navigation Buttons
                  _buildNavigationButtons(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 40),
      child: Row(
        children: [
          _buildProgressDot(0, 'Alcance'),
          _buildProgressLine(0),
          _buildProgressDot(1, 'Config'),
          _buildProgressLine(1),
          _buildProgressDot(2, 'Confirmar'),
        ],
      ),
    );
  }

  Widget _buildProgressDot(int step, String label) {
    final isActive = _currentPage >= step;
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: isActive
                  ? const LinearGradient(
                      colors: [Color(0xFFD4AF37), Color(0xFFFFD700)],
                    )
                  : null,
              color: isActive ? null : Colors.white.withOpacity(0.1),
              border: Border.all(
                color: isActive ? const Color(0xFFD4AF37) : Colors.white.withOpacity(0.3),
                width: 2,
              ),
            ),
            child: Center(
              child: Text(
                '${step + 1}',
                style: TextStyle(
                  color: isActive ? Colors.white : Colors.white.withOpacity(0.5),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              color: isActive ? const Color(0xFFD4AF37) : Colors.white.withOpacity(0.5),
              fontSize: 12,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressLine(int step) {
    final isActive = _currentPage > step;
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 30),
        decoration: BoxDecoration(
          gradient: isActive
              ? const LinearGradient(
                  colors: [Color(0xFFD4AF37), Color(0xFFFFD700)],
                )
              : null,
          color: isActive ? null : Colors.white.withOpacity(0.1),
        ),
      ),
    );
  }

  Widget _buildScopeSelectionPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Selecciona el Alcance',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Decide quién puede participar en tu torneo',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: TournamentScopeCard(
                  scope: 'GLOBAL',
                  isSelected: _selectedScope == 'GLOBAL',
                  onTap: () => setState(() => _selectedScope = 'GLOBAL'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TournamentScopeCard(
                  scope: 'CLUB',
                  isSelected: _selectedScope == 'CLUB',
                  onTap: () => setState(() => _selectedScope = 'CLUB'),
                ),
              ),
            ],
          ),
          if (_selectedScope == 'GLOBAL') ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF00D4FF).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF00D4FF).withOpacity(0.3),
                ),
              ),
              child: Row(
                children: const [
                  Icon(Icons.info_outline, color: Color(0xFF00D4FF), size: 24),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Torneos GLOBAL están abiertos a todos los usuarios de la plataforma.',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConfigurationPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Configuración Pro',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Define los detalles del torneo',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 32),
          // Nombre del Torneo
          TextField(
            controller: _nameController,
            style: const TextStyle(color: Colors.white, fontSize: 18),
            decoration: InputDecoration(
              labelText: 'Nombre del Torneo',
              labelStyle: const TextStyle(color: Color(0xFFD4AF37)),
              prefixIcon: const Icon(Icons.emoji_events, color: Color(0xFFD4AF37)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.3), width: 2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 2),
              ),
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
            ),
          ),
          const SizedBox(height: 24),
          // Tournament Type Selector
          _buildTournamentTypeSelector(),
          const SizedBox(height: 24),
          // Blind Speed Selector (solo si no es TURBO type)
          if (_selectedType != 'TURBO') _buildBlindSpeedSelector(),
          if (_selectedType != 'TURBO') const SizedBox(height: 24),
          // Settings específicos según tipo
          if (_selectedType == 'REBUY') _buildRebuySettings(),
          if (_selectedType == 'BOUNTY') _buildBountySettings(),
          if (_selectedType == 'REBUY' || _selectedType == 'BOUNTY') const SizedBox(height: 24),
          // Buy-in
          TextField(
            controller: _buyInController,
            style: const TextStyle(color: Colors.white, fontSize: 18),
            keyboardType: TextInputType.number,
            onChanged: (value) => setState(() {}), // Trigger rebuild for prize pool
            decoration: InputDecoration(
              labelText: 'Buy-in',
              labelStyle: const TextStyle(color: Color(0xFFD4AF37)),
              prefixIcon: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Image.asset('assets/images/imperial_coin.png', width: 24, height: 24),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.3), width: 2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFD4AF37), width: 2),
              ),
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
            ),
          ),
          const SizedBox(height: 24),
          // Estimated Players Slider
          const Text(
            'Jugadores Estimados',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withOpacity(0.1),
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Icon(Icons.people, color: Color(0xFFD4AF37)),
                    Text(
                      '$_estimatedPlayers jugadores',
                      style: const TextStyle(
                        color: Color(0xFFD4AF37),
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Icon(Icons.people, color: Color(0xFFD4AF37)),
                  ],
                ),
                Slider(
                  value: _estimatedPlayers.toDouble(),
                  min: 2,
                  max: 100,
                  divisions: 98,
                  activeColor: const Color(0xFFD4AF37),
                  inactiveColor: Colors.white.withOpacity(0.2),
                  onChanged: (value) {
                    setState(() => _estimatedPlayers = value.toInt());
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Prize Pool Calculator
          PrizePoolCalculator(
            buyIn: double.tryParse(_buyInController.text) ?? 0,
            estimatedPlayers: _estimatedPlayers,
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmationPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Confirmación',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Revisa los detalles antes de crear',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 32),
          // Summary Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.white.withOpacity(0.1),
                  Colors.white.withOpacity(0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFFD4AF37).withOpacity(0.3),
                width: 2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.emoji_events, color: Color(0xFFD4AF37), size: 32),
                    SizedBox(width: 12),
                    Text(
                      'Resumen del Torneo',
                      style: TextStyle(
                        color: Color(0xFFD4AF37),
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const Divider(color: Colors.white24, height: 32),
                _buildSummaryRow('Nombre', _nameController.text.isEmpty ? '(Sin nombre)' : _nameController.text),
                _buildSummaryRow('Alcance', _selectedScope == 'GLOBAL' ? '🌍 Global (Todos los usuarios)' : '🏰 Club (Solo miembros)'),
                _buildSummaryRow('Tipo', _getTypeLabel(_selectedType)),
                if (_selectedType != 'TURBO') _buildSummaryRow('Ciegas', _getBlindSpeedLabel(_selectedBlindSpeed)),
                if (_selectedType == 'REBUY') _buildSummaryRow('Rebuy', _rebuyAllowed ? '✅ Permitido' : '❌ No permitido'),
                if (_selectedType == 'BOUNTY') _buildSummaryWidgetRow('Bounty', ImperialCurrency(amount: _bountyAmount, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
                _buildSummaryWidgetRow('Buy-in', ImperialCurrency(amount: _buyInController.text, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
                _buildSummaryRow('Jugadores Estimados', '$_estimatedPlayers'),
                const Divider(color: Colors.white24, height: 32),
                PrizePoolCalculator(
                  buyIn: double.tryParse(_buyInController.text) ?? 0,
                  estimatedPlayers: _estimatedPlayers,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryWidgetRow(String label, Widget valueWidget) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 16,
            ),
          ),
          valueWidget,
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 16,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  String _getTypeLabel(String type) {
    switch (type) {
      case 'FREEZEOUT':
        return '🧊 Freezeout';
      case 'REBUY':
        return '🔄 Rebuy/Add-on';
      case 'BOUNTY':
        return '🥊 Progressive KO';
      case 'TURBO':
        return '⚡ Turbo';
      default:
        return type;
    }
  }

  String _getBlindSpeedLabel(String speed) {
    switch (speed) {
      case 'SLOW':
        return '🐌 Lento';
      case 'NORMAL':
        return '⏱️ Normal';
      case 'TURBO':
        return '⚡ Turbo';
      default:
        return speed;
    }
  }

  Widget _buildTournamentTypeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Tipo de Torneo',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 4.0, // Much smaller height
          children: [
            _buildTypeCard('FREEZEOUT', '🧊', 'Freezeout', 'Clásico sin recompras'),
            _buildTypeCard('REBUY', '🔄', 'Rebuy', 'Permite recompras'),
            _buildTypeCard('BOUNTY', '🥊', 'Bounty', 'Recompensas por KO'),
            _buildTypeCard('TURBO', '⚡', 'Turbo', 'Ciegas muy rápidas'),
          ],
        ),
      ],
    );
  }

  Widget _buildTypeCard(String type, String emoji, String title, String subtitle) {
    final isSelected = _selectedType == type;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedType = type;
          // Si es TURBO, forzar blindSpeed a TURBO
          if (type == 'TURBO') {
            _selectedBlindSpeed = 'TURBO';
          }
          // Si es REBUY, activar rebuy por defecto
          if (type == 'REBUY') {
            _rebuyAllowed = true;
          }
          // Si es BOUNTY, calcular bounty default (10% del buy-in)
          if (type == 'BOUNTY') {
            final buyIn = int.tryParse(_buyInController.text) ?? 100;
            _bountyAmount = (buyIn * 0.1).round();
          }
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: [Color(0xFFD4AF37), Color(0xFFFFD700)],
                )
              : null,
          color: isSelected ? null : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFFD4AF37) : Colors.white.withOpacity(0.2),
            width: 2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              emoji,
              style: const TextStyle(fontSize: 20),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: isSelected ? Colors.black : Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: isSelected ? Colors.black87 : Colors.white70,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlindSpeedSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Velocidad de Ciegas',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildSpeedOption('SLOW', '🐌', 'Lento')),
            const SizedBox(width: 12),
            Expanded(child: _buildSpeedOption('NORMAL', '⏱️', 'Normal')),
            const SizedBox(width: 12),
            Expanded(child: _buildSpeedOption('TURBO', '⚡', 'Turbo')),
          ],
        ),
      ],
    );
  }

  Widget _buildSpeedOption(String speed, String emoji, String label) {
    final isSelected = _selectedBlindSpeed == speed;
    return GestureDetector(
      onTap: () => setState(() => _selectedBlindSpeed = speed),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          gradient: isSelected
              ? const LinearGradient(
                  colors: [Color(0xFFD4AF37), Color(0xFFFFD700)],
                )
              : null,
          color: isSelected ? null : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFFD4AF37) : Colors.white.withOpacity(0.2),
            width: 2,
          ),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.black : Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRebuySettings() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF00D4FF).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF00D4FF).withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.cached, color: Color(0xFF00D4FF)),
              SizedBox(width: 8),
              Text(
                'Configuración de Rebuy',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: const Text(
              'Permitir Rebuy',
              style: TextStyle(color: Colors.white),
            ),
            subtitle: const Text(
              'Los jugadores podrán recomprar fichas',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            value: _rebuyAllowed,
            activeColor: const Color(0xFF00D4FF),
            onChanged: (value) => setState(() => _rebuyAllowed = value),
          ),
        ],
      ),
    );
  }

  Widget _buildBountySettings() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFF5722).withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFFF5722).withOpacity(0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.military_tech, color: Color(0xFFFF5722)),
              SizedBox(width: 8),
              Text(
                'Configuración de Bounty',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            style: const TextStyle(color: Colors.white),
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Bounty por Eliminación (\$)',
              labelStyle: const TextStyle(color: Color(0xFFFF5722)),
              hintText: 'Ej: ${(int.tryParse(_buyInController.text) ?? 100) * 0.1}',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFFF5722)),
              ),
              filled: true,
              fillColor: Colors.white.withOpacity(0.05),
            ),
            onChanged: (value) {
              setState(() {
                _bountyAmount = int.tryParse(value) ?? 0;
              });
            },
          ),
          const SizedBox(height: 8),
          Text(
            'Sugerido: 10-20% del Buy-in',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationButtons() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        border: Border(
          top: BorderSide(
            color: Colors.white.withOpacity(0.1),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          if (_currentPage > 0)
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _previousPage,
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                label: const Text('Atrás'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.1),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.white.withOpacity(0.3)),
                  ),
                ),
              ),
            ),
          if (_currentPage > 0) const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _isCreating
                  ? null
                  : (_currentPage < 2 ? _nextPage : _createTournament),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                backgroundColor: const Color(0xFFD4AF37), // Imperial Gold
                foregroundColor: Colors.black,
                disabledBackgroundColor: Colors.grey,
              ),
              child: _isCreating
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _currentPage < 2 ? 'Siguiente' : '🎉 Crear Torneo',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                        if (_currentPage < 2) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.arrow_forward, color: Colors.black),
                        ],
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
