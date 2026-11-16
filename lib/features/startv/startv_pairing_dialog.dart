import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_state.dart';
import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../core/network/lan_guard.dart';
import 'qr_scanner_screen.dart';
import 'startv_client.dart';
import 'startv_models.dart';

class StarTvPairingDialog extends ConsumerStatefulWidget {
  const StarTvPairingDialog({super.key});

  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (_) => const StarTvPairingDialog(),
    );
  }

  @override
  ConsumerState<StarTvPairingDialog> createState() => _StarTvPairingDialogState();
}

class _StarTvPairingDialogState extends ConsumerState<StarTvPairingDialog> {
  final _ipController = TextEditingController(text: '192.168.');
  final _pinController = TextEditingController();
  final _qrUrlController = TextEditingController();
  StarTvTrustMode _trustMode = StarTvTrustMode.home;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ipController.dispose();
    _pinController.dispose();
    _qrUrlController.dispose();
    super.dispose();
  }

  Future<void> _scanQr() async {
    final s = ref.read(appControllerProvider).strings;
    final scanned = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => QrScannerScreen(
          title: s.t('scan_qr_title'),
          hint: s.t('scan_qr_hint'),
        ),
      ),
    );
    if (!mounted || scanned == null || scanned.isEmpty) return;
    _qrUrlController.text = scanned;
    await _pair();
  }

  String _formatFriendlyError(Object e, AppStrings s) {
    if (e is LanGuardException) {
      return s.t('startv_error_lan');
    }
    if (e is FormatException) {
      return s.t('startv_invalid_qr');
    }
    if (e is StarTvException) {
      if (e.statusCode == 401 || e.statusCode == 403) {
        return s.t('startv_error_auth');
      }
      return s.t('startv_error_network');
    }
    return s.t('startv_error_network');
  }

  Future<void> _pair() async {
    final s = ref.read(appControllerProvider).strings;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      String ip = _ipController.text.trim();
      int port = 8088;
      String pin = _pinController.text.trim();

      final qrRaw = _qrUrlController.text.trim();
      if (qrRaw.isNotEmpty) {
        final parsed = StarTvQrPayload.tryParse(qrRaw);
        if (parsed == null) {
          throw const FormatException('invalid_qr');
        }
        ip = parsed.ip;
        port = parsed.port;
        pin = parsed.pin;
      }

      final client = ref.read(appServicesProvider).starTv;
      await client.fetchStatus(ip: ip, port: port);
      final auth = await client.authenticate(ip: ip, port: port, pin: pin);
      final device = StarTvDevice(
        tvId: auth.tvId,
        ip: ip,
        port: port,
        deviceName: auth.deviceName,
        trustMode: _trustMode,
        installedPlayers: auth.installedPlayers,
        syncApiVersion: auth.syncApiVersion,
      );
      await ref
          .read(appControllerProvider.notifier)
          .saveStarTvDevice(device, auth.token);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _formatFriendlyError(e, s);
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appControllerProvider).strings;
    return AlertDialog(
      backgroundColor: StarFilmColors.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      title: Text(s.t('startv_connect')),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _scanQr,
                icon: const Icon(Icons.qr_code_scanner, size: 18),
                label: Text(s.t('scan_qr_btn')),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _qrUrlController,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: s.t('startv_qr_label'),
                  hintText: 'http://192.168.1.50:8088/?pin=123456',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _ipController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: s.t('startv_ip_label'),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _pinController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  isDense: true,
                  labelText: s.t('startv_pin_label'),
                ),
              ),
              const SizedBox(height: 6),
              RadioListTile<StarTvTrustMode>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                value: StarTvTrustMode.home,
                groupValue: _trustMode,
                onChanged: (v) => setState(() => _trustMode = v!),
                title: Text(s.t('startv_home_mode')),
                subtitle: Text(
                  s.t('startv_home_desc'),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              RadioListTile<StarTvTrustMode>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                value: StarTvTrustMode.guest,
                groupValue: _trustMode,
                onChanged: (v) => setState(() => _trustMode = v!),
                title: Text(s.t('startv_guest_mode')),
                subtitle: Text(
                  s.t('startv_guest_desc'),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(color: StarFilmColors.error, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: Text(s.t('cancel')),
        ),
        FilledButton(
          onPressed: _busy ? null : _pair,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(s.t('ok')),
        ),
      ],
    );
  }
}
