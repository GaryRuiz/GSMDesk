import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../common.dart';
import '../models/platform_model.dart';

/// GSMDesk: looks for a new version when the app opens and every few hours,
/// and downloads it. Installing takes one tap, so an update never cuts an open
/// session by surprise. The Rust side verifies the signature of each download.
class GsmUpdate {
  GsmUpdate._();

  static final status = ''.obs;
  static final version = ''.obs;
  static final notes = ''.obs;
  static final progress = 0.0.obs;
  static Timer? _checkTimer;
  static Timer? _pollTimer;
  static DateTime? _lastCheck;

  static void start() {
    if (_checkTimer != null || !(isWindows || isAndroid)) return;
    // A copy that is not installed has nothing to update.
    if (isWindows && !bind.mainIsInstalled()) return;
    _check();
    _checkTimer = Timer.periodic(const Duration(hours: 6), (_) => _check());
  }

  /// Closing the window leaves the app running, so reopening it would not look
  /// for updates without this.
  static void checkOnReopen() {
    final last = _lastCheck;
    if (_checkTimer == null ||
        (last != null &&
            DateTime.now().difference(last) < const Duration(minutes: 10))) {
      return;
    }
    _check();
  }

  static void _check() {
    _lastCheck = DateTime.now();
    bind.mainSetCommon(key: 'gsm-update-check', value: '');
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      final state = jsonDecode(await bind.mainGetCommon(key: 'gsm-update-state'))
          as Map<String, dynamic>;
      status.value = state['status'] as String;
      version.value = state['version'] as String;
      notes.value = state['notes'] as String;
      final total = state['total'] as int;
      progress.value = total > 0 ? (state['downloaded'] as int) / total : 0;
      if (status.value != 'checking' && status.value != 'downloading') {
        timer.cancel();
      }
    });
  }

  static void showInstallDialog() {
    gFFI.dialogManager.show((setState, close, context) {
      final tip = notes.value.isEmpty ? '' : '\n\n${notes.value}';
      return CustomAlertDialog(
        title: Text('${translate('gsm-update-title')} ${version.value}'),
        content: Text(
            '${translate(isWindows ? 'gsm-update-tip-windows' : 'gsm-update-tip-android')}$tip'),
        actions: [
          dialogButton('gsm-update-later', onPressed: close, isOutline: true),
          dialogButton('gsm-update-now', onPressed: () {
            close();
            _install();
          }),
        ],
        onCancel: close,
      );
    });
  }

  static Future<void> _install() async {
    if (isWindows) {
      await bind.mainSetCommon(key: 'gsm-update-install', value: '');
    } else if (isAndroid) {
      final file = await bind.mainGetCommon(key: 'gsm-update-file');
      if (file.isEmpty || await gFFI.invokeMethod('install_apk', file) != true) {
        showToast(translate('gsm-update-failed'));
      }
    }
  }
}

/// GSMDesk: small indicator in the header. Empty unless there is an update.
Widget gsmUpdateChip(BuildContext context) {
  return Obx(() {
    if (GsmUpdate.status.value == 'downloading') {
      final percent = (GsmUpdate.progress.value * 100).round();
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 6),
            Text('${translate('gsm-update-downloading')} $percent %',
                style:
                    TextStyle(fontSize: 13, color: MyTheme.gsmMuted(context))),
          ],
        ),
      );
    }
    if (GsmUpdate.status.value == 'ready') {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: SizedBox(
          height: 28,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.system_update_alt, size: 15),
            label: Text(translate('gsm-update-button'),
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            onPressed: GsmUpdate.showInstallDialog,
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  });
}
