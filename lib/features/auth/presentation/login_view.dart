import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/i18n/translator.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/providers/language_provider.dart';
import '../../../core/database/database_manager.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/theme/peadra_colors.dart';
import '../../dashboard/presentation/dashboard_shell.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _db = DatabaseManager.instance;
  final _authService = AuthService(DatabaseManager.instance);
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isLoginMode = true;
  bool _isLoading = false;
  String? _error;
  List<String> _existingUsers = [];
  String? _selectedUser;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    final users = await _authService.getAllUsernames();
    final lastUser = await _db.getAppSetting('last_username');
    if (mounted) {
      setState(() {
        _existingUsers = users;
        if (users.isEmpty) {
          _isLoginMode = false;
        } else if (lastUser != null && users.contains(lastUser)) {
          _selectedUser = lastUser;
        }
      });
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _toggleMode() {
    setState(() {
      _isLoginMode = !_isLoginMode;
      _error = null;
    });
  }

  void _submit() {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (_isLoginMode) {
        _login();
      } else {
        _register();
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _login() async {
    final username = _selectedUser ?? _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty) {
      setState(() {
        _error = Translator.t('msg_user_select_required');
        _isLoading = false;
      });
      return;
    }
    if (password.isEmpty) {
      setState(() {
        _error = Translator.t('msg_password_required');
        _isLoading = false;
      });
      return;
    }

    final userId = await _authService.authenticateUser(username, password);
    if (userId == null) {
      setState(() {
        _error = Translator.t('msg_incorrect_credentials');
        _isLoading = false;
      });
      return;
    }

    _onLoginSuccess(userId, username);
  }

  void _register() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (username.length < 3) {
      setState(() {
        _error = Translator.t('msg_username_min_length');
        _isLoading = false;
      });
      return;
    }
    if (password.length < 6) {
      setState(() {
        _error = Translator.t('msg_password_min_length');
        _isLoading = false;
      });
      return;
    }
    if (password != confirm) {
      setState(() {
        _error = Translator.t('msg_passwords_not_match');
        _isLoading = false;
      });
      return;
    }

    try {
      final userId = await _authService.registerUser(username, password);
      _onLoginSuccess(userId, username);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _onLoginSuccess(int userId, String username) async {
    final authProvider = context.read<AuthProvider>();
    final themeProvider = context.read<ThemeProvider>();
    final langProvider = context.read<LanguageProvider>();

    authProvider.login(userId, username, _db);
    await themeProvider.loadFromSettings(_db);
    await langProvider.loadFromSettings(_db);

    await _db.setAppSetting('last_username', username);

    _db.fetchExchangeRates();

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const DashboardShell()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeName = context.watch<ThemeProvider>().themeName;
    final colors = PeadraTheme.getColors(themeName);
    final isDark = context.watch<ThemeProvider>().isDark;

    return Scaffold(
      backgroundColor: colors.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colors.borderColor),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  Translator.t('login_title'),
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: colors.text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  Translator.t('login_subtitle'),
                  style: TextStyle(
                    fontSize: 14,
                    color: colors.placeholderColor,
                  ),
                ),
                const SizedBox(height: 32),

                if (_isLoginMode) ...[
                  if (_existingUsers.isNotEmpty)
                    DropdownButtonFormField<String>(
                      key: ValueKey(_selectedUser),
                      initialValue: _selectedUser,
                      hint: Text(
                        Translator.t('login_user'),
                        style: TextStyle(color: colors.placeholderColor),
                      ),
                      items: _existingUsers
                          .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedUser = v),
                      decoration: InputDecoration(
                        labelText: Translator.t('login_username'),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        filled: true,
                        fillColor: colors.bg,
                      ),
                    ),
                ] else ...[
                  TextField(
                    controller: _usernameController,
                    decoration: InputDecoration(
                      labelText: Translator.t('login_username'),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: colors.bg,
                    ),
                  ),
                ],

                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: Translator.t('login_password'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: colors.bg,
                  ),
                ),

                if (!_isLoginMode) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _confirmController,
                    obscureText: true,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: Translator.t('login_confirm_password'),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: colors.bg,
                    ),
                  ),
                ],

                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(color: colors.error, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],

                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _isLoginMode
                                ? Translator.t('login_signin')
                                : Translator.t('login_signup'),
                            style: const TextStyle(fontSize: 16),
                          ),
                  ),
                ),

                if (_isLoginMode && _existingUsers.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton(
                      onPressed: _toggleMode,
                      child: Text(
                        Translator.t('login_create_account'),
                        style: TextStyle(color: colors.accent),
                      ),
                    ),
                  ),
                ],

                if (!_isLoginMode && _existingUsers.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton(
                      onPressed: _toggleMode,
                      child: Text(
                        Translator.t('login_connect_account'),
                        style: TextStyle(color: colors.accent),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
