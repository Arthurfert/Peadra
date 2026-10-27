import 'dart:async';
import 'dart:convert';

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
import '../../../core/responsive/responsive_layout.dart';
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
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  int? _onboardingStep;
  String _onboardingLanguage = LanguageProvider.defaultLanguage;

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
        if (!mounted) return;
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
          // Fresh install: run the 3-step onboarding (language, name, password).
          _isLoginMode = false;
          _onboardingStep = 0;
          _onboardingLanguage = context.read<LanguageProvider>().language;
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

  void _onboardingNext() {
    final step = _onboardingStep ?? 0;
    if (step < 2) {
      if (step == 1 && _usernameController.text.trim().length < 3) {
        setState(() => _error = Translator.t('msg_username_min_length'));
        return;
      }
      setState(() {
        _error = null;
        _onboardingStep = step + 1;
      });
      return;
    }
    _submit(); // final step: validates password rules and registers
  }

  void _onboardingBack() {
    setState(() {
      _error = null;
      if (_onboardingStep != null && _onboardingStep! > 0) {
        _onboardingStep = _onboardingStep! - 1;
      }
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
    await _setupEncryption(username, password);
    await _db.generateDueRecurring();

    await themeProvider.loadFromSettings(_db);
    // Persist the active language as the user setting before loading it, so
    // a choice made during onboarding isn't reset to the default by the load.
    if (await _db.getSetting('language') == null) {
      await _db.setSetting('language', langProvider.language);
    }
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

  Future<void> _setupEncryption(String username, String password) async {
    if (_db.isEncrypted) return;

    // The salt is deterministic per account (derived from the username), so the
    // same password yields the same key on every device. No salt sync required.
    final salt = EncryptionService.saltForUsername(username);
    final expectedSaltB64 = base64Encode(salt);

    final storedSaltStr = await _db.getSetting('encryption_salt');
    if (storedSaltStr != null && storedSaltStr != expectedSaltB64) {
      // Legacy device encrypted under a random salt. Migrate its data to the
      // deterministic per-account key so it matches every other device for
      // this account, then persist the new salt.
      final oldKey =
          await EncryptionService.deriveKey(password, base64Decode(storedSaltStr));
      final newKey = await EncryptionService.deriveKey(password, salt);
      await _db.migrateEncryptionKey(oldKey, newKey);
    }

    final key = await EncryptionService.deriveKey(password, salt);
    await _db.setEncryptionKey(key);
    await _db.setSetting('encryption_salt', expectedSaltB64);
    await _db.migrateToEncryption();
    final repair = await _db.repairDanglingDescriptionRefs();
    if (repair.repointed > 0 || repair.undecryptable > 0) {
      LogService().log(
          'Description repair at login: repointed=${repair.repointed} '
          'undecryptable=${repair.undecryptable}');
    }
  }

  Widget _buildOnboarding(BuildContext context, PeadraColors colors) {
    final step = _onboardingStep ?? 0;
    final isLast = step == 2;

    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: ResponsiveLayout.pagePaddingAll(context),
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
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(3, (i) {
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 5),
                        width: step == i ? 12 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: step == i ? colors.accent : colors.borderColor,
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 24),
                  ..._onboardingStepContent(step, colors),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(color: colors.error, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      if (step > 0) ...[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _onboardingBack,
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: colors.borderColor),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Text(
                              Translator.t('btn_back'),
                              style: TextStyle(color: colors.textSecondary),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        flex: step > 0 ? 2 : 1,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _onboardingNext,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colors.accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
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
                                  isLast
                                      ? Translator.t('login_signup')
                                      : Translator.t('onboarding_next'),
                                  style: const TextStyle(fontSize: 16),
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _onboardingStepContent(int step, PeadraColors colors) {
    const flagOptions = [('en', '🇬🇧'), ('fr', '🇫🇷'), ('es', '🇪🇸')];
    switch (step) {
      case 0:
        return [
          Text(
            Translator.t('onboarding_language_title'),
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colors.text),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            Translator.t('onboarding_language_desc'),
            style: TextStyle(fontSize: 13, color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (code, flag) in flagOptions)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: GestureDetector(
                    onTap: () {
                      context.read<LanguageProvider>().setLanguage(code);
                      setState(() => _onboardingLanguage = code);
                    },
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: code == _onboardingLanguage
                              ? colors.accent
                              : colors.borderColor,
                          width: 2,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(flag, style: const TextStyle(fontSize: 24)),
                    ),
                  ),
                ),
            ],
          ),
        ];
      case 1:
        return [
          Text(
            Translator.t('onboarding_name_title'),
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colors.text),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _usernameController,
            maxLength: 50,
            autofillHints: const [AutofillHints.username],
            autofocus: true,
            onSubmitted: (_) => _onboardingNext(),
            decoration: InputDecoration(
              labelText: Translator.t('login_username'),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: colors.bg,
            ),
          ),
        ];
      default:
        return [
          Text(
            Translator.t('onboarding_password_title'),
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colors.text),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            Translator.t('onboarding_password_desc'),
            style: TextStyle(fontSize: 13, color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            autofillHints: const [AutofillHints.newPassword],
            onSubmitted: (_) => _onboardingNext(),
            decoration: InputDecoration(
              labelText: Translator.t('login_password'),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              filled: true,
              fillColor: colors.bg,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  color: colors.placeholderColor,
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmController,
            obscureText: _obscureConfirm,
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
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                  color: colors.placeholderColor,
                ),
                onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
              ),
            ),
          ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeName = context.watch<ThemeProvider>().themeName;
    final colors = PeadraTheme.getColors(themeName);
    // Watch so language changes (onboarding step 1) re-render immediately.
    context.watch<LanguageProvider>();

    if (_isInitializing) {
      return Scaffold(
        backgroundColor: colors.bg,
        body: Center(
          child: CircularProgressIndicator(color: colors.accent),
        ),
      );
    }

    if (_onboardingStep != null) {
      return _buildOnboarding(context, colors);
    }

    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: ResponsiveLayout.pagePaddingAll(context),
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
                      color: colors.textSecondary,
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
                    obscureText: _obscurePassword,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: Translator.t('login_password'),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: colors.bg,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off : Icons.visibility,
                          color: colors.placeholderColor,
                        ),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                  ),

                  if (!_isLoginMode) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _confirmController,
                      obscureText: _obscureConfirm,
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
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirm ? Icons.visibility_off : Icons.visibility,
                            color: colors.placeholderColor,
                          ),
                          onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                        ),
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
