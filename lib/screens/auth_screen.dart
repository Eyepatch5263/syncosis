import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/user_service.dart';
import 'session_hub_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _loginEmailCtrl = TextEditingController();
  final _loginPassCtrl = TextEditingController();
  final _signupNameCtrl = TextEditingController();
  final _signupEmailCtrl = TextEditingController();
  final _signupPassCtrl = TextEditingController();

  bool _isLoading = false;
  bool _obscureLoginPass = true;
  bool _obscureSignupPass = true;
  bool _rememberMe = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabController.dispose();
    _loginEmailCtrl.dispose();
    _loginPassCtrl.dispose();
    _signupNameCtrl.dispose();
    _signupEmailCtrl.dispose();
    _signupPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final email = _loginEmailCtrl.text.trim();
    final password = _loginPassCtrl.text.trim();

    if (email.isEmpty) {
      _showError('Please enter email');
      return;
    }
    if (password.isEmpty) {
      _showError('Please enter password');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final userService = context.read<UserService>();
      await userService.login(email, password);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const SessionHubScreen()),
        );
      }
    } on Exception catch (e) {
      if (mounted) _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSignup() async {
    final name = _signupNameCtrl.text.trim();
    final email = _signupEmailCtrl.text.trim();
    final password = _signupPassCtrl.text.trim();

    if (name.isEmpty) {
      _showError('Please enter full name');
      return;
    }
    if (email.isEmpty) {
      _showError('Please enter email');
      return;
    }
    if (password.isEmpty) {
      _showError('Please enter password');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final userService = context.read<UserService>();
      await userService.createUser(email, password, Colors.cyan);
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const SessionHubScreen()),
        );
      }
    } on Exception catch (e) {
      if (mounted) _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final isLogin = _tabController.index == 0;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A1A2E), Color(0xFF2D1B3D)],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top dark section: back button + title ──
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Back button
                    GestureDetector(
                      onTap: () => Navigator.of(context).maybePop(),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Colors.white.withAlpha(20),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withAlpha(40),
                            width: 1,
                          ),
                        ),
                        child: const Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Title
                    Text(
                      isLogin
                          ? 'Go ahead and set up\nyour account'
                          : 'Create your\naccount',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Subtitle
                    Text(
                      'Sign in-up to enjoy the best managing experience',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withAlpha(140),
                        fontFamily: GoogleFonts.inriaSans().fontFamily,
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),

              // ── White card section ──
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(30),
                      topRight: Radius.circular(30),
                    ),
                  ),
                  child: Column(
                    children: [
                      // Tab toggle
                      Padding(
                        padding: const EdgeInsets.fromLTRB(40, 28, 40, 0),
                        child: Container(
                          height: 48,
                          decoration: BoxDecoration(
                            color: Theme.of(context).dividerColor.withOpacity(0.05),
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: TabBar(
                            controller: _tabController,
                            indicatorSize: TabBarIndicatorSize.tab,
                            dividerColor: Colors.transparent,
                            indicator: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(25),
                              border: Border.all(
                                color: Theme.of(context).dividerColor.withOpacity(0.1),
                                width: 1,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withAlpha(15),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            labelColor: Theme.of(context).textTheme.bodyLarge?.color,
                            unselectedLabelColor: const Color(0xFF9E9E9E),
                            labelStyle: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                            unselectedLabelStyle: const TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                            ),
                            tabs: const [
                              Tab(text: 'Login'),
                              Tab(text: 'Register'),
                            ],
                          ),
                        ),
                      ),

                      // Tab content
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [_buildLoginTab(), _buildSignupTab()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Login Tab ────────────────────────────────────────────────
  Widget _buildLoginTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        children: [
          _buildTextField(
            controller: _loginEmailCtrl,
            hint: 'Username',
            icon: Icons.mail_outline_rounded,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _loginPassCtrl,
            hint: 'Password',
            icon: Icons.lock_outline_rounded,
            obscure: _obscureLoginPass,
            onIconPressed: () =>
                setState(() => _obscureLoginPass = !_obscureLoginPass),
          ),
          const SizedBox(height: 12),

          // Remember me + Forgot Password row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: Checkbox(
                      value: _rememberMe,
                      onChanged: (v) =>
                          setState(() => _rememberMe = v ?? false),
                      activeColor: const Color(0xFFE85D5D),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                      side: const BorderSide(
                        color: Color(0xFFBDBDBD),
                        width: 1.5,
                      ),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Remember me',
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 28),

          // Login button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleLogin,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE85D5D),
                disabledBackgroundColor: const Color(0xFFE85D5D).withAlpha(150),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : Text(
                      'Login',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        fontFamily: GoogleFonts.inriaSans().fontFamily,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 28),

          // "Or login with" divider
          Row(
            children: [
              Expanded(
                child: Container(height: 1, color: const Color(0xFFE0E0E0)),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Or login with',
                  style: TextStyle(color: Color(0xFFBDBDBD), fontSize: 12),
                ),
              ),
              Expanded(
                child: Container(height: 1, color: const Color(0xFFE0E0E0)),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Social login buttons
          Row(
            children: [
              _buildSocialButton(Icons.g_mobiledata_rounded, 'Google'),
              const SizedBox(width: 16),
              _buildSocialButton(Icons.apple, 'Apple'),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Register Tab ─────────────────────────────────────────────
  Widget _buildSignupTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        children: [
          _buildTextField(
            controller: _signupNameCtrl,
            hint: 'Username',
            icon: Icons.person_outline_rounded,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _signupEmailCtrl,
            hint: 'Email-ID',
            icon: Icons.mail_outline_rounded,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _signupPassCtrl,
            hint: 'Password',
            icon: Icons.lock_outline_rounded,
            obscure: _obscureSignupPass,
            onIconPressed: () =>
                setState(() => _obscureSignupPass = !_obscureSignupPass),
          ),
          const SizedBox(height: 28),

          // Register button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _handleSignup,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE85D5D),
                disabledBackgroundColor: const Color(0xFFE85D5D).withAlpha(150),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(26),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : Text(
                      'Register',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        fontFamily: GoogleFonts.inriaSans().fontFamily,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 28),

          // "Or Signup with" divider
          Row(
            children: [
              Expanded(
                child: Container(height: 1, color: const Color(0xFFE0E0E0)),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Or signup with',
                  style: TextStyle(color: Color(0xFFBDBDBD), fontSize: 12),
                ),
              ),
              Expanded(
                child: Container(height: 1, color: const Color(0xFFE0E0E0)),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Social login buttons
          Row(
            children: [
              _buildSocialButton(Icons.g_mobiledata_rounded, 'Google'),
              const SizedBox(width: 16),
              _buildSocialButton(Icons.apple, 'Apple'),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Shared text field ────────────────────────────────────────
  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    VoidCallback? onIconPressed,
  }) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: Theme.of(context).dividerColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.1), width: 1),
          ),
          hintStyle: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 14),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(left: 14, right: 10),
            child: Icon(icon, color: const Color(0xFF9E9E9E), size: 20),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 44,
            minHeight: 20,
          ),
          suffixIcon: onIconPressed != null
              ? IconButton(
                  icon: Icon(
                    obscure
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: const Color(0xFF9E9E9E),
                    size: 20,
                  ),
                  onPressed: onIconPressed,
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  // ─── Social login button ─────────────────────────────────────
  Widget _buildSocialButton(IconData icon, String label) {
    return Expanded(
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.1), width: 1),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              // Handle social login
            },
            borderRadius: BorderRadius.circular(14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: Theme.of(context).textTheme.bodyLarge?.color?.withOpacity(0.6), size: 22),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodyLarge?.color?.withOpacity(0.8),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
