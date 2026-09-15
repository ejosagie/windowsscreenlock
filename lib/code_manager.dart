import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

/// Manages monthly access codes for the lease lock system.
///
/// Code system:
/// - First code: 40 days
/// - Subsequent codes: 30 days each
/// - Disable code: permanently removes the lock
///
/// Codes are pre-generated using a secret salt and stored locally.
/// The app validates entered codes against the expected next code.
class CodeManager {
  static const String _secretSalt = 'SaleCentra_Lease_2024_SecureKey';
  static const String _disableCode = 'SC-DISABLE-FINAL-PAYMENT-DONE';

  static const String _stateFileName = 'lease_state.json';

  /// Generate a code for a given index.
  static String generateCode(int index) {
    final input = '$_secretSalt-$index';
    final hash = sha256.convert(utf8.encode(input)).toString();
    return hash.substring(0, 8).toUpperCase();
  }

  /// First code (index 0): 40 days, subsequent: 30 days.
  static int getDurationDays(int index) {
    if (index == 0) return 40;
    return 30;
  }

  /// The permanent disable code.
  static String get disableCode => _disableCode;

  /// Load the current state from disk.
  static Future<Map<String, dynamic>> loadState() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$_stateFileName');
      if (await file.exists()) {
        final contents = await file.readAsString();
        return jsonDecode(contents) as Map<String, dynamic>;
      }
    } catch (_) {}
    return {
      'current_code_index': 0,
      'activated_at': null,
      'disabled': false,
    };
  }

  /// Save state to disk.
  static Future<void> saveState(Map<String, dynamic> state) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$_stateFileName');
      await file.writeAsString(jsonEncode(state));
    } catch (_) {}
  }

  /// Validate an entered code.
  static Future<CodeValidationResult> validateCode(String enteredCode) async {
    final code = enteredCode.trim().toUpperCase();

    if (code == _disableCode) {
      final state = await loadState();
      state['disabled'] = true;
      await saveState(state);
      return CodeValidationResult(
        success: true,
        disabled: true,
        message: 'Lock permanently disabled. Thank you for completing your payment!',
      );
    }

    final state = await loadState();

    if (state['disabled'] == true) {
      return CodeValidationResult(
        success: true,
        disabled: true,
        message: 'Lock is already permanently disabled.',
      );
    }

    final currentIndex = (state['current_code_index'] as num?)?.toInt() ?? 0;
    final expectedCode = generateCode(currentIndex);

    if (code == expectedCode) {
      final now = DateTime.now().toIso8601String();
      final durationDays = getDurationDays(currentIndex);
      state['activated_at'] = now;
      state['current_code_index'] = currentIndex + 1;
      await saveState(state);

      return CodeValidationResult(
        success: true,
        disabled: false,
        message: 'Access granted for $durationDays days.',
        activatedAt: DateTime.parse(now),
        durationDays: durationDays,
      );
    }

    if (currentIndex > 0) {
      final previousCode = generateCode(currentIndex - 1);
      if (code == previousCode) {
        return CodeValidationResult(
          success: false,
          disabled: false,
          message: 'This code has already been used. Please enter the new code for this period.',
        );
      }
    }

    return CodeValidationResult(
      success: false,
      disabled: false,
      message: 'Invalid code. Please check and try again.',
    );
  }

  /// Check if the system is currently locked or unlocked.
  static Future<LockStatus> checkStatus() async {
    final state = await loadState();

    if (state['disabled'] == true) {
      return LockStatus(
        isLocked: false,
        isDisabled: true,
        activatedAt: null,
        expiresAt: null,
        daysRemaining: 0,
        currentCodeIndex: 0,
      );
    }

    final activatedAtStr = state['activated_at'] as String?;
    if (activatedAtStr == null) {
      final currentIndex = (state['current_code_index'] as num?)?.toInt() ?? 0;
      return LockStatus(
        isLocked: true,
        isDisabled: false,
        activatedAt: null,
        expiresAt: null,
        daysRemaining: 0,
        currentCodeIndex: currentIndex,
      );
    }

    final activatedAt = DateTime.parse(activatedAtStr);
    final currentIndex = (state['current_code_index'] as num?)?.toInt() ?? 1;
    final usedCodeIndex = currentIndex - 1;
    final durationDays = getDurationDays(usedCodeIndex);
    final expiresAt = activatedAt.add(Duration(days: durationDays));
    final now = DateTime.now();

    if (now.isAfter(expiresAt)) {
      return LockStatus(
        isLocked: true,
        isDisabled: false,
        activatedAt: activatedAt,
        expiresAt: expiresAt,
        daysRemaining: 0,
        currentCodeIndex: currentIndex,
      );
    }

    final daysRemaining = expiresAt.difference(now).inDays;
    return LockStatus(
      isLocked: false,
      isDisabled: false,
      activatedAt: activatedAt,
      expiresAt: expiresAt,
      daysRemaining: daysRemaining,
      currentCodeIndex: currentIndex,
    );
  }

  /// Generate a printable list of codes for the lessor.
  static List<Map<String, dynamic>> generateCodeList(int count) {
    final List<Map<String, dynamic>> codes = [];
    for (int i = 0; i < count; i++) {
      codes.add({
        'index': i,
        'code': generateCode(i),
        'duration_days': getDurationDays(i),
      });
    }
    return codes;
  }
}

class CodeValidationResult {
  final bool success;
  final bool disabled;
  final String message;
  final DateTime? activatedAt;
  final int? durationDays;

  CodeValidationResult({
    required this.success,
    required this.disabled,
    required this.message,
    this.activatedAt,
    this.durationDays,
  });
}

class LockStatus {
  final bool isLocked;
  final bool isDisabled;
  final DateTime? activatedAt;
  final DateTime? expiresAt;
  final int daysRemaining;
  final int currentCodeIndex;

  LockStatus({
    required this.isLocked,
    required this.isDisabled,
    required this.activatedAt,
    required this.expiresAt,
    required this.daysRemaining,
    required this.currentCodeIndex,
  });
}
