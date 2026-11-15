import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_state.dart';
import '../../app/theme.dart';
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

  Future<void> _pair() async {
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
          throw const FormatException('Некоректний QR/URL локальної приставки');
        }
        ip = parsed.ip;
        port = parsed.port;
        pin = parsed.pin;
      }

      final client = ref.read(appServicesProvider).starTv;
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
      await ref.read(appControllerProvider.notifier).saveStarTvDevice(device, auth.token);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
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
      title: Text(s.t('startv_connect')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _qrUrlController,
              decoration: const InputDecoration(
                labelText: 'URL з QR (опціонально)',
                hintText: 'http://192.168.1.50:8088/?pin=123456',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _ipController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'IP приставки (LAN)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _pinController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '6-значний PIN'),
            ),
            const SizedBox(height: 14),
            RadioListTile<StarTvTrustMode>(
              value: StarTvTrustMode.home,
              groupValue: _trustMode,
              onChanged: (v) => setState(() => _trustMode = v!),
              title: Text(s.t('startv_home_mode')),
              subtitle: const Text('Запуск, синхронізація бібліотеки та передача ключів'),
            ),
            RadioListTile<StarTvTrustMode>(
              value: StarTvTrustMode.guest,
              groupValue: _trustMode,
              onChanged: (v) => setState(() => _trustMode = v!),
              title: Text(s.t('startv_guest_mode')),
              subtitle: const Text('Лише запуск відео/трейлерів без змішування бази'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: StarFilmColors.error)),
            ],
          ],
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
