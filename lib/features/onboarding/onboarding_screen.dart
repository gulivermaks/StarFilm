import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_state.dart';
import '../../app/theme.dart';
import '../../core/models/media_key.dart';
import '../startv/startv_pairing_dialog.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;
  final _tmdbController = TextEditingController();
  final _geminiController = TextEditingController();
  bool? _tmdbOk;
  bool? _geminiOk;
  String? _tmdbMessage;
  String? _geminiMessage;
  bool _verifyingTmdb = false;
  bool _verifyingGemini = false;

  @override
  void dispose() {
    _tmdbController.dispose();
    _geminiController.dispose();
    super.dispose();
  }

  Future<void> _verifySingleKey({required bool isTmdb}) async {
    final s = ref.read(appControllerProvider).strings;
    final controller = isTmdb ? _tmdbController : _geminiController;
    final val = controller.text.trim();

    if (val.isEmpty) {
      setState(() {
        if (isTmdb) {
          _tmdbOk = false;
          _tmdbMessage = s.t('key_empty');
        } else {
          _geminiOk = false;
          _geminiMessage = s.t('key_empty');
        }
      });
      return;
    }

    setState(() {
      if (isTmdb) {
        _verifyingTmdb = true;
        _tmdbMessage = null;
      } else {
        _verifyingGemini = true;
        _geminiMessage = null;
      }
    });

    bool ok = false;
    String message;
    try {
      final services = ref.read(appServicesProvider);
      ok = isTmdb
          ? await services.tmdb.verifyKey(val)
          : await services.gemini.verifyKey(
              val,
              model: ref.read(appControllerProvider).geminiModel,
            );
      if (ok) {
        await ref.read(appControllerProvider.notifier).setApiKeys(
              tmdbKey: isTmdb ? val : null,
              geminiKey: isTmdb ? null : val,
            );
        message = s.t('key_verified_ok');
      } else {
        message = s.t('key_rejected');
      }
    } catch (e) {
      ok = false;
      message = s.t('key_verify_error', {'e': '$e'});
    }

    if (!mounted) return;
    setState(() {
      if (isTmdb) {
        _verifyingTmdb = false;
        _tmdbOk = ok;
        _tmdbMessage = message;
      } else {
        _verifyingGemini = false;
        _geminiOk = ok;
        _geminiMessage = message;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final s = state.strings;

    return Scaffold(
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(s.t('onboarding_title')),
        ),
        actions: [
          TextButton(
            onPressed: () => ref.read(appControllerProvider.notifier).completeOnboarding(),
            child: Text(s.t('skip')),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LinearProgressIndicator(
                value: (_step + 1) / 5,
                backgroundColor: StarFilmColors.surfaceElevated,
                color: StarFilmColors.lime,
              ),
              const SizedBox(height: 20),
              Expanded(child: _buildStep(state)),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (_step > 0) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(() => _step--),
                        child: Text(s.t('back')),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        if (_step == 1) {
                          await ref.read(appControllerProvider.notifier).setApiKeys(
                                tmdbKey: _tmdbController.text.trim(),
                                geminiKey: _geminiController.text.trim(),
                              );
                        }
                        if (_step < 4) {
                          setState(() => _step++);
                        } else {
                          await ref
                              .read(appControllerProvider.notifier)
                              .completeOnboarding();
                        }
                      },
                      child: Text(_step < 4 ? s.t('next') : s.t('onboarding_start')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep(AppControllerState state) {
    final s = state.strings;
    switch (_step) {
      case 0:
        return ListView(
          children: [
            Text(
              s.t('ui_language'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            for (final item in [
              ('uk', s.t('onboarding_lang_uk_default')),
              ('ru', 'Русский'),
              ('en', 'English'),
            ])
              RadioListTile<String>(
                value: item.$1,
                groupValue: state.uiLanguage,
                title: Text(item.$2),
                onChanged: (v) {
                  if (v != null) {
                    ref.read(appControllerProvider.notifier).setUiLanguage(v);
                  }
                },
              ),
          ],
        );

      case 1:
        return ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          children: [
            Text(
              s.t('onboarding_keys_title'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              s.t('onboarding_keys_privacy'),
              style: const TextStyle(color: StarFilmColors.textSecondary),
            ),
            const SizedBox(height: 16),
            _buildKeyFieldSection(
              keyFieldId: 'onboarding_tmdb',
              controller: _tmdbController,
              label: s.t('tmdb_key'),
              linkLabel: s.t('onboarding_get_tmdb'),
              linkUri: Uri.https('www.themoviedb.org', '/settings/api'),
              verifying: _verifyingTmdb,
              ok: _tmdbOk,
              statusMessage: _tmdbMessage,
              verifyLabel: s.t('verify'),
              onVerify: () => _verifySingleKey(isTmdb: true),
              onChanged: () {
                if (_tmdbOk != null || _tmdbMessage != null) {
                  setState(() {
                    _tmdbOk = null;
                    _tmdbMessage = null;
                  });
                }
              },
            ),
            const SizedBox(height: 14),
            _buildKeyFieldSection(
              keyFieldId: 'onboarding_gemini',
              controller: _geminiController,
              label: '${s.t('gemini_key')} (${s.t('optional')})',
              linkLabel: s.t('onboarding_get_gemini'),
              linkUri: Uri.https('aistudio.google.com', '/apikey'),
              verifying: _verifyingGemini,
              ok: _geminiOk,
              statusMessage: _geminiMessage,
              verifyLabel: s.t('verify'),
              onVerify: () => _verifySingleKey(isTmdb: false),
              onChanged: () {
                if (_geminiOk != null || _geminiMessage != null) {
                  setState(() {
                    _geminiOk = null;
                    _geminiMessage = null;
                  });
                }
              },
            ),
          ],
        );

      case 2:
        return ListView(
          children: [
            Text(
              s.t('onboarding_sync_title'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              s.t('onboarding_sync_desc'),
              style: const TextStyle(color: StarFilmColors.textSecondary),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: state.firebaseConfigured
                  ? () async {
                      await ref.read(appControllerProvider.notifier).signInWithGoogle();
                    }
                  : null,
              icon: const Icon(Icons.cloud_outlined),
              label: Text(
                state.cloudUid.isNotEmpty
                    ? state.cloudEmail
                    : (state.firebaseConfigured
                        ? s.t('google_signin')
                        : '${s.t('google_signin')} (${s.t('google_signin_waiting')})'),
              ),
            ),
          ],
        );

      case 3:
        final excluded = state.activeProfile.preferences.excludedGenres.toSet();
        return ListView(
          children: [
            Text(
              s.t('excluded_genres'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              s.t('onboarding_excluded_hint'),
              style: const TextStyle(color: StarFilmColors.textSecondary),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final g in kStandardGenres)
                  FilterChip(
                    label: Text(g.labelFor(state.uiLanguage)),
                    selected: excluded.contains(g.id),
                    onSelected: (selected) {
                      final next = {...excluded};
                      if (selected) {
                        next.add(g.id);
                      } else {
                        next.remove(g.id);
                      }
                      final sorted = next.toList()..sort();
                      ref.read(appControllerProvider.notifier).updateProfilePreferences(
                            state.activeProfile.preferences.copyWith(
                              excludedGenres: sorted,
                            ),
                          );
                    },
                  ),
              ],
            ),
          ],
        );

      default:
        return ListView(
          children: [
            Text(
              s.t('startv_section'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              s.t('onboarding_startv_desc'),
              style: const TextStyle(color: StarFilmColors.textSecondary),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => StarTvPairingDialog.show(context),
              icon: const Icon(Icons.qr_code_2),
              label: Text(s.t('startv_connect')),
            ),
            if (state.pairedDevices.isNotEmpty) ...[
              const SizedBox(height: 12),
              for (final tv in state.pairedDevices)
                ListTile(
                  leading: const Icon(Icons.tv, color: StarFilmColors.lime),
                  title: Text(tv.deviceName),
                  subtitle: Text('${tv.ip}:${tv.port} • ${tv.trustMode.wireValue}'),
                ),
            ],
          ],
        );
    }
  }

  Widget _buildKeyFieldSection({
    required String keyFieldId,
    required TextEditingController controller,
    required String label,
    required String linkLabel,
    required Uri linkUri,
    required bool verifying,
    required bool? ok,
    required String? statusMessage,
    required String verifyLabel,
    required VoidCallback onVerify,
    required VoidCallback onChanged,
  }) {
    final statusColor = ok == true ? StarFilmColors.success : StarFilmColors.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: Key('${keyFieldId}_field'),
          controller: controller,
          onChanged: (_) => onChanged(),
          decoration: InputDecoration(
            labelText: label,
            suffixIcon: ok == null
                ? null
                : Icon(
                    ok ? Icons.check_circle : Icons.error,
                    color: statusColor,
                  ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            OutlinedButton.icon(
              key: Key('${keyFieldId}_verify'),
              onPressed: verifying ? null : onVerify,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 38),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              icon: verifying
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified_outlined, size: 18),
              label: Text(verifyLabel),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => launchUrl(
                    linkUri,
                    mode: LaunchMode.externalApplication,
                  ),
                  child: Text(
                    linkLabel,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (statusMessage != null) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                ok == true ? Icons.check_circle_outline : Icons.error_outline,
                size: 15,
                color: statusColor,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  statusMessage,
                  key: Key('${keyFieldId}_status'),
                  style: TextStyle(color: statusColor, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
