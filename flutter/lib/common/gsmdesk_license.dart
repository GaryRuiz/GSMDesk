import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../common.dart';
import '../models/platform_model.dart';
import '../utils/http_service.dart' as http;
import '../utils/multi_window_manager.dart';

/// GSMDesk: technician licence, shared with GSM Redirector (same key, same
/// mundogsm.net API and same hardware ID, see `hardware_id()` in
/// src/gsmdesk.rs). Without an active licence GSMDesk controls one remote PC
/// at a time; with it, several at once. Receiving connections is always free.
class GsmLicense {
  GsmLicense._();

  // Same endpoints and order as GSM Redirector's ApiService.
  static const _apiUrls = [
    'https://gsmredirector.mundogsm.net/api/mundogsm-login.php',
    'https://mundogsm.net/api/mundogsm-login.php',
  ];
  static const _kKey = 'gsmdesk-license-key';
  static const _kCache = 'gsmdesk-license-cache';

  /// How long a licence confirmed by the server stays usable while the
  /// server cannot be reached.
  static const _offlineGrace = Duration(days: 3);

  static final RxBool active = false.obs;
  static final RxString plan = ''.obs;
  static final RxString expires = ''.obs;
  static Timer? _timer;

  static String get key => bind.mainGetLocalOption(key: _kKey);

  /// Loads the cached state, then re-checks with the server now and every
  /// six hours. Call once from the main window.
  static void start() {
    _loadCache();
    refresh();
    _timer ??= Timer.periodic(const Duration(hours: 6), (_) => refresh());
  }

  static void _set(bool isActive, String planText, String expiresText) {
    active.value = isActive;
    plan.value = planText;
    expires.value = expiresText;
  }

  static void _loadCache() {
    try {
      final cache = jsonDecode(bind.mainGetLocalOption(key: _kCache))
          as Map<String, dynamic>;
      final checked = DateTime.tryParse(cache['checked'] ?? '');
      final until = DateTime.tryParse(cache['expires'] ?? '');
      final now = DateTime.now();
      final usable = cache['valid'] == true &&
          checked != null &&
          now.difference(checked) < _offlineGrace &&
          (until == null || !now.isAfter(until.add(const Duration(days: 1))));
      _set(usable, cache['plan'] ?? '', cache['expires'] ?? '');
    } catch (_) {
      _set(false, '', '');
    }
  }

  static Future<Map<String, dynamic>?> _checkLicense(String licenseKey) async {
    final hwid = await bind.mainGetCommon(key: 'gsmdesk-hwid');
    final body = jsonEncode(
        {'action': 'check_license', 'license_key': licenseKey, 'hw_id': hwid});
    for (final url in _apiUrls) {
      try {
        final resp = await http
            .post(Uri.parse(url),
                headers: {'Content-Type': 'application/json'}, body: body)
            .timeout(const Duration(seconds: 15));
        if (resp.statusCode == 200) {
          return jsonDecode(resp.body) as Map<String, dynamic>;
        }
      } catch (e) {
        debugPrint('GSMDesk licence check failed at $url: $e');
      }
    }
    return null;
  }

  /// Checks [licenseKey] (default: the saved one) with the server and saves
  /// it when valid. Returns null on success, otherwise the reason to show.
  static Future<String?> refresh({String? licenseKey}) async {
    final isNewKey = licenseKey != null;
    final k = (licenseKey ?? key).trim();
    if (k.isEmpty) {
      _set(false, '', '');
      return null;
    }
    final res = await _checkLicense(k);
    if (res == null) {
      // Server unreachable: keep the cached state, within its grace period.
      if (!isNewKey) _loadCache();
      return translate('gsm-license-network-error');
    }
    if (res['valid'] == true) {
      final planText = (res['plan'] ?? '').toString();
      final expiresText = (res['expires'] ?? '').toString();
      await bind.mainSetLocalOption(key: _kKey, value: k);
      await bind.mainSetLocalOption(
          key: _kCache,
          value: jsonEncode({
            'valid': true,
            'plan': planText,
            'expires': expiresText,
            'checked': DateTime.now().toIso8601String(),
          }));
      _set(true, planText, expiresText);
      return null;
    }
    final reason = (res['reason'] ?? '').toString();
    // A rejected new key leaves the current licence alone; a rejected saved
    // key (expired, moved to another PC...) turns the licence off.
    if (!isNewKey) {
      await bind.mainSetLocalOption(
          key: _kCache, value: jsonEncode({'valid': false}));
      _set(false, '', '');
    }
    return reason.isEmpty ? translate('Failed') : reason;
  }

  static Future<void> remove() async {
    await bind.mainSetLocalOption(key: _kKey, value: '');
    await bind.mainSetLocalOption(key: _kCache, value: '');
    _set(false, '', '');
  }

  /// Whether a remote desktop session to [id] may be opened: always with an
  /// active licence, otherwise only while no other PC is being controlled.
  static Future<bool> canOpenRemoteDesktop(String id) async {
    if (active.value) return true;
    final open = await rustDeskWinManager.getOpenRemoteDesktopPeers();
    open.remove(id);
    if (open.isEmpty) return true;
    await windowOnTop(null);
    showFreeLimitDialog();
    return false;
  }

  static void showFreeLimitDialog() {
    gFFI.dialogManager.show((setState, close, context) {
      return CustomAlertDialog(
        title: Row(children: [
          Icon(Icons.lock_outline, color: MyTheme.accent),
          const SizedBox(width: 10),
          Flexible(child: Text(translate('gsm-free-limit-title'))),
        ]),
        content: Text(translate('gsm-free-limit-tip')),
        actions: [
          dialogButton('Close',
              icon: const Icon(Icons.close_rounded),
              isOutline: true,
              onPressed: close),
          dialogButton('gsm-license-activate',
              icon: const Icon(Icons.workspace_premium_outlined),
              onPressed: () {
            close();
            showActivateDialog();
          }),
        ],
        onCancel: close,
      );
    });
  }

  static void showActivateDialog() {
    final controller = TextEditingController(text: key);
    var errMsg = '';
    var busy = false;
    gFFI.dialogManager.show((setState, close, context) {
      submit() async {
        final k = controller.text.trim();
        if (k.isEmpty || busy) return;
        setState(() {
          busy = true;
          errMsg = '';
        });
        final err = await refresh(licenseKey: k);
        if (err == null) {
          close();
          showToast(translate('gsm-license-activated'));
        } else {
          setState(() {
            busy = false;
            errMsg = err;
          });
        }
      }

      return CustomAlertDialog(
        title: Row(children: [
          Icon(Icons.workspace_premium_outlined, color: MyTheme.accent),
          const SizedBox(width: 10),
          Flexible(child: Text(translate('gsm-license-activate'))),
        ]),
        content: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(translate('gsm-license-dialog-tip')),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                enabled: !busy,
                decoration: InputDecoration(
                  labelText: translate('gsm-license-key'),
                  errorText: errMsg.isEmpty ? null : errMsg,
                  errorMaxLines: 3,
                ),
                onSubmitted: (_) => submit(),
              ),
              if (busy) const LinearProgressIndicator().marginOnly(top: 10),
            ],
          ),
        ),
        actions: [
          if (active.value)
            dialogButton('gsm-license-remove',
                icon: const Icon(Icons.delete_outline_rounded),
                isOutline: true, onPressed: () async {
              await remove();
              close();
            }),
          dialogButton('Cancel',
              icon: const Icon(Icons.close_rounded),
              isOutline: true,
              onPressed: close),
          dialogButton('gsm-license-activate',
              icon: const Icon(Icons.done_rounded),
              onPressed: busy ? null : submit),
        ],
        onSubmit: submit,
        onCancel: close,
      );
    });
  }
}
