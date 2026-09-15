import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'code_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // Register app to run at Windows startup
  await _ensureAutoStart();

  // Check status BEFORE showing window — only show if locked
  final status = await CodeManager.checkStatus();
  final shouldShow = status.isLocked && !status.isDisabled;

  await windowManager.waitUntilReadyToShow();
  await windowManager.setTitle('SaleCentra Lease');
  await windowManager.setSize(const Size(500, 450));
  await windowManager.center();
  await windowManager.setAlwaysOnTop(shouldShow);
  await windowManager.setSkipTaskbar(!shouldShow);

  if (shouldShow) {
    await windowManager.show();
  }
  // If not locked, window stays hidden — no lock screen shown

  runApp(const SaleCentraLockApp());
}

/// Registers this app in the Windows registry to auto-start at boot.
/// Uses HKCU\Software\Microsoft\Windows\CurrentVersion\Run
/// No admin rights required (current user only).
Future<void> _ensureAutoStart() async {
  try {
    final exePath = Platform.resolvedExecutable;
    const regKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
    const regValue = 'SaleCentraLock';

    // Check if already registered
    final checkResult = await Process.run('reg', ['query', regKey, '/v', regValue]);
    if (checkResult.exitCode == 0 && checkResult.stdout.toString().contains(exePath)) {
      return; // Already registered
    }

    // Add to registry
    await Process.run('reg', ['add', regKey, '/v', regValue, '/t', 'REG_SZ', '/d', '"$exePath"', '/f']);
  } catch (_) {
    // If registry fails, try startup folder as fallback
    try {
      final exePath = Platform.resolvedExecutable;
      final startupDir = '${Platform.environment['APPDATA']}\\Microsoft\\Windows\\Start Menu\\Programs\\Startup';
      final shortcutPath = '$startupDir\\SaleCentraLock.lnk';
      final file = File(shortcutPath);
      if (!await file.exists()) {
        // Create a simple batch file as fallback
        final batPath = '$startupDir\\SaleCentraLock.bat';
        await File(batPath).writeAsString('start "" "$exePath"');
      }
    } catch (_) {}
  }
}

class SaleCentraLockApp extends StatelessWidget {
  const SaleCentraLockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SaleCentra Lease',
      debugShowCheckedModeBanner: false,
      home: const LockScreen(),
    );
  }
}

class LockScreen extends StatefulWidget {
  const LockScreen({super.key});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> with WindowListener {
  final _codeController = TextEditingController();
  LockStatus? _status;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _message;
  Color? _messageColor;
  Timer? _checkTimer;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    _checkStatus();
    // Check once per day to catch expiry
    _checkTimer = Timer.periodic(const Duration(days: 1), (_) => _checkStatus());
  }

  @override
  void dispose() {
    _checkTimer?.cancel();
    windowManager.removeListener(this);
    _codeController.dispose();
    super.dispose();
  }

  @override
  void onWindowClose() async {
    // Prevent closing if locked
    if (_status != null && _status!.isLocked && !_status!.isDisabled) {
      await windowManager.show();
      await windowManager.setAlwaysOnTop(true);
    } else {
      await windowManager.destroy();
    }
  }

  Future<void> _checkStatus() async {
    final status = await CodeManager.checkStatus();
    if (!mounted) return;

    setState(() {
      _status = status;
      _isLoading = false;
    });

    if (status.isDisabled) {
      // Permanently disabled — exit app
      await windowManager.setAlwaysOnTop(false);
      await windowManager.close();
    } else if (status.isLocked) {
      // Locked — ensure window is visible and on top
      await windowManager.show();
      await windowManager.setAlwaysOnTop(true);
      await windowManager.focus();
    } else {
      // Unlocked — hide window completely
      await windowManager.setAlwaysOnTop(false);
      await windowManager.hide();
    }
  }

  Future<void> _submitCode() async {
    if (_codeController.text.trim().isEmpty) return;

    setState(() {
      _isSubmitting = true;
      _message = null;
    });

    final result = await CodeManager.validateCode(_codeController.text);

    if (!mounted) return;

    setState(() {
      _isSubmitting = false;
      _message = result.message;
      _messageColor = result.success ? Colors.green : Colors.red;
    });

    if (result.success) {
      _codeController.clear();
      await _checkStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // If disabled, show nothing (app should close)
    if (_status != null && _status!.isDisabled) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_open, size: 64, color: Colors.green),
              SizedBox(height: 16),
              Text('Lease Complete', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('Thank you for completing your payment!'),
            ],
          ),
        ),
      );
    }

    // If unlocked, show minimal status
    if (_status != null && !_status!.isLocked) {
      return Scaffold(
        backgroundColor: Colors.green.shade50,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, size: 64, color: Colors.green),
              const SizedBox(height: 16),
              Text(
                'Access Active',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.green.shade700),
              ),
              const SizedBox(height: 8),
              Text(
                '${_status!.daysRemaining} days remaining',
                style: TextStyle(fontSize: 16, color: Colors.green.shade600),
              ),
              const SizedBox(height: 8),
              Text(
                'Expires: ${_status!.expiresAt != null ? _formatDate(_status!.expiresAt!) : 'N/A'}',
                style: TextStyle(fontSize: 13, color: Colors.green.shade600),
              ),
            ],
          ),
        ),
      );
    }

    // Locked screen
    return Scaffold(
      backgroundColor: Colors.grey.shade900,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock, size: 72, color: Colors.orange),
              const SizedBox(height: 24),
              const Text(
                'SaleCentra Lease',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Enter your monthly access code to continue',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade400),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: 300,
                child: TextField(
                  controller: _codeController,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    letterSpacing: 4,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    hintText: 'ENTER CODE',
                    hintStyle: TextStyle(color: Colors.grey.shade600, letterSpacing: 4),
                    filled: true,
                    fillColor: Colors.grey.shade800,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade600),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.orange, width: 2),
                    ),
                  ),
                  textCapitalization: TextCapitalization.characters,
                  onSubmitted: (_) => _submitCode(),
                ),
              ),
              const SizedBox(height: 16),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _message!,
                    style: TextStyle(color: _messageColor, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ),
              SizedBox(
                width: 300,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submitCode,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Unlock', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Code #${_status?.currentCodeIndex ?? 0 + 1} required',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
