import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cryptography/cryptography.dart';

import '../../../core/i18n/translator.dart';
import '../../../core/providers/auth_provider.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/providers/language_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/database/database_manager.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/biometric_service.dart';
import '../../../core/services/encryption_service.dart';
import '../../../core/services/log_service.dart';
import '../../../core/theme/peadra_colors.dart';
import '../../../sync/sync_service.dart';
import '../../dashboard/presentation/dashboard_shell.dart';

class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _db = DatabaseManager.instance;
  final _authService = AuthService(DatabaseManager.instance);
  final _biometricService = BiometricService();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isLoginMode = true;
  bool _isInitializing = true;
  bool _isLoading = false;
  String? _error;
  List<String> _existingUsers = [];
  String? _selectedUser;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    try {
      final users = await _authService.getAllUsernames();
      final lastUser = await _db.getAppSetting('last_username');
      final savedLang = await _db.getAppSetting('last_language');
      final biometricAvailable = await _biometricService.isAvailable();
      final credentials = biometricAvailable
          ? await _biometricService.loadCredentials()
          : null;

      if (!mounted) return;

      if (savedLang != null) {
        context.read<LanguageProvider>().setLanguage(savedLang);
      }
      if (lastUser != null) {
        final savedTheme = await _db.getThemeForUser(lastUser);
        if (savedTheme != null) {
          context.read<ThemeProvider>().setTheme(savedTheme);
        }
      }

      final selectedUser = users.isEmpty
          ? null
          : (lastUser != null && users.contains(lastUser) ? lastUser : null);
      final storedUsername = credentials?['username'] as String?;
      final biometricEnabled = biometricAvailable &&
          storedUsername != null &&
          users.contains(storedUsername);

      setState(() {
        _existingUsers = users;
        _selectedUser = selectedUser;
        _biometricAvailable = biometricAvailable;
        _biometricEnabled = biometricEnabled;
        if (users.isEmpty) {
          _isLoginMode = false;
        }
        _isInitializing = false;
      });
    } catch (e) {
      LogService().error('Failed to load login state: $e', '');
      if (mounted) {
        setState(() => _isInitializing = false);
      }
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

  Future<void> _submit() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      if (_isLoginMode) {
        await _login();
      } else {
        await _register();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _login() async {
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

    await _onLoginSuccess(userId, username, password);
  }

  Future<void> _register() async {
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

    final userId = await _authService.registerUser(username, password);
    await _onLoginSuccess(userId, username, password);
  }

  Future<void> _onLoginSuccess(String userId, String username, String password) async {
    final authProvider = context.read<AuthProvider>();
    final themeProvider = context.read<ThemeProvider>();
    final langProvider = context.read<LanguageProvider>();
    final settingsProvider = context.read<SettingsProvider>();

    // After sync reconciliation the stored userId may have been remapped to
    // the peer's canonical id.  Re-resolve so queries hit the right rows.
    userId = await _authService.resolveUserId(userId, username);

    authProvider.login(userId, username, _db);
    await _setupEncryption(password);
    await _db.generateDueRecurring();

    await themeProvider.loadFromSettings(_db);
    await langProvider.loadFromSettings(_db);
    await settingsProvider.loadFromSettings(_db);

    await _db.setAppSetting('last_username', username);
    await _db.setAppSetting('last_language', langProvider.language);

    // Keep biometric credentials in sync only when the user has enabled
    // biometric login; otherwise drop any stale credentials so the button
    // never shows on the login screen for an opted-out user.
    if (settingsProvider.biometricEnabled) {
      await _biometricService.saveCredentials(userId, username, encryptionKey: _db.encryptionKey);
    } else {
      await _biometricService.clearCredentials();
    }

    _db.fetchExchangeRates();
    unawaited(SyncService.instance.start());

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const DashboardShell()),
      );
    }
  }

  void _biometricLogin() async {
    LogService().log('Biometric login: starting');
    final authenticated = await _biometricService.authenticate(
      reason: Translator.t('param_biometric_desc'),
    );
    if (!authenticated) {
      LogService().log('Biometric login: authentication failed');
      if (mounted) {
        setState(() => _error = Translator.t('param_biometric_failed'));
      }
      return;
    }

    LogService().log('Biometric login: auth succeeded, loading credentials');
    final credentials = await _biometricService.loadCredentials();
    if (credentials == null) {
      LogService().log('Biometric login: no stored credentials');
      if (mounted) {
        setState(() => _error = Translator.t('param_biometric_re_enable'));
      }
      return;
    }

    final userId = credentials['userId'] as String?;
    final username = credentials['username'];
    if (userId == null || username == null) {
      LogService().log('Biometric login: invalid credentials (userId=$userId, username=$username)');
      if (mounted) {
        setState(() => _error = Translator.t('param_biometric_re_enable'));
      }
      return;
    }

    final keyBase64 = credentials['encryptionKey'] as String?;
    if (keyBase64 != null) {
      final keyBytes = base64Decode(keyBase64);
      _db.setEncryptionKey(SecretKey(keyBytes));
      LogService().log('Biometric login: encryption key restored');
    } else {
      LogService().log('Biometric login: no encryption key in storage');
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    _onLoginSuccess(userId, username, '');
  }

  Future<void> _setupEncryption(String password) async {
    if (_db.isEncrypted) return;
    final saltStr = await _db.getSetting('encryption_salt');
    Uint8List salt;
    if (saltStr == null) {
      salt = EncryptionService.generateSalt();
      await _db.setSetting('encryption_salt', base64Encode(salt));
    } else {
      salt = base64Decode(saltStr);
    }
    final key = await EncryptionService.deriveKey(password, salt);
    await _db.setEncryptionKey(key);
    await _db.migrateToEncryption();
  }

  @override
  Widget build(BuildContext context) {
    final themeName = context.watch<ThemeProvider>().themeName;
    final colors = PeadraTheme.getColors(themeName);
    final isDark = context.watch<ThemeProvider>().isDark;

    if (_isInitializing) {
      return Scaffold(
        backgroundColor: colors.bg,
        body: Center(
          child: CircularProgressIndicator(color: colors.accent),
        ),
      );
    }

    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        child: Center(
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
              child: AutofillGroup(
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
                    if (_existingUsers.isNotEmpty) ...[
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
                        maxLength: 50,
                        autofillHints: const [AutofillHints.username],
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
                  ] else ...[
                    TextField(
                      controller: _usernameController,
                      maxLength: 50,
                      autofillHints: const [AutofillHints.username],
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
                    maxLength: 128,
                    autofillHints: const [AutofillHints.password],
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
                      maxLength: 128,
                      autofillHints: const [AutofillHints.newPassword],
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

                  if (_isLoginMode && _biometricAvailable && _biometricEnabled) ...[
                    const SizedBox(height: 16),
                    Center(
                      child: OutlinedButton.icon(
                        onPressed: _isLoading ? null : _biometricLogin,
                        icon: Icon(Icons.fingerprint, color: colors.accent),
                        label: Text(
                          Translator.t('param_biometric'),
                          style: TextStyle(color: colors.accent),
                        ),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: colors.accent),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        ),
                      ),
                    ),
                  ],

                  if (_isLoginMode) ...[
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
        ),
      ),
    );
  }
}
