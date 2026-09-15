import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Standalone code generator — no Flutter dependencies.
/// Run from this IDE: dart run tool/generate_codes.dart

const String _secretSalt = 'SaleCentra_Lease_2024_SecureKey';
const int _disableCodeIndex = -1;

String generateCode(int index) {
  final input = '$_secretSalt-$index';
  final hash = sha256.convert(utf8.encode(input)).toString();
  return hash.substring(0, 8).toUpperCase();
}

int getDurationDays(int index) {
  if (index == 0) return 40;
  return 30;
}

String get disableCode => generateCode(_disableCodeIndex);

void main() {
  final count = 12;

  print('');
  print('========================================');
  print('  SaleCentra Lease - Access Codes');
  print('========================================');
  print('');

  for (int i = 0; i < count; i++) {
    final code = generateCode(i);
    final days = getDurationDays(i);
    final label = i == 0 ? 'FIRST CODE (40 days)' : 'Code #${i + 1} ($days days)';
    print('  $label');
    print('  Code: $code');
    print('');
  }

  print('========================================');
  print('  DISABLE CODE (share when fully paid):');
  print('  $disableCode');
  print('========================================');
  print('');
  print('Share codes one at a time after each');
  print('monthly payment is received.');
}
