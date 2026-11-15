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
  bool _verifying = false;

  @override
  void dispose() {
    _tmdbController.dispose();
    _geminiController.dispose();
    super.dispose();
  }

  Future<void> _verifyKeys() async {
    setState(() => _verifying = true);
    final services = ref.read(appServicesProvider);
    final tmdb = _tmdbController.text.trim();
    final gemini = _geminiController.text.trim();
    bool? tOk;
    bool? gOk;
    if (tmdb.isNotEmpty) {
      tOk = await services.tmdb.verifyKey(tmdb);
    }
    if (gemini.isNotEmpty) {
      gOk = await services.gemini.verifyKey(
        gemini,
        model: ref.read(appControllerProvider).geminiModel,
      );
    }
    await ref.read(appControllerProvider.notifier).setApiKeys(
          tmdbKey: tmdb,
          geminiKey: gemini,
        );
    if (mounted) {
      setState(() {
        _tmdbOk = tOk;
        _geminiOk = gOk;
        _verifying = false;
      });
    }
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
                        child: const Text('Назад'),
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
                      child: Text(_step < 4 ? 'Далі' : s.t('onboarding_start')),
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
            for (final item in const [
              ('uk', 'Українська (за замовчуванням)'),
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
          children: [
            Text(
              s.t('onboarding_keys_title'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Особисті ключі зберігаються лише на вашому пристрої і ніколи не передаються в Firebase.',
              style: TextStyle(color: StarFilmColors.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _tmdbController,
              decoration: InputDecoration(
                labelText: s.t('tmdb_key'),
                suffixIcon: _tmdbOk == null
                    ? null
                    : Icon(
                        _tmdbOk! ? Icons.check_circle : Icons.error,
                        color: _tmdbOk! ? StarFilmColors.success : StarFilmColors.error,
                      ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => launchUrl(
                  Uri.https('www.themoviedb.org', '/settings/api'),
                  mode: LaunchMode.externalApplication,
                ),
                child: const Text('Отримати TMDB API key →'),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _geminiController,
              decoration: InputDecoration(
                labelText: '${s.t('gemini_key')} (опціонально)',
                suffixIcon: _geminiOk == null
                    ? null
                    : Icon(
                        _geminiOk! ? Icons.check_circle : Icons.error,
                        color: _geminiOk! ? StarFilmColors.success : StarFilmColors.error,
                      ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => launchUrl(
                  Uri.https('aistudio.google.com', '/apikey'),
                  mode: LaunchMode.externalApplication,
                ),
                child: const Text('Отримати Gemini API key →'),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _verifying ? null : _verifyKeys,
              icon: _verifying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified_outlined),
              label: Text(s.t('verify')),
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
            const Text(
              'Локальна бібліотека завжди доступна без хмари. Хмарна синхронізація запрацює після підключення Firebase.',
              style: TextStyle(color: StarFilmColors.textSecondary),
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
                        : '${s.t('google_signin')} (очікує google-services.json)'),
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
            const Text(
              'Оберіть жанри, які не потрібно пропонувати у підборі:',
              style: TextStyle(color: StarFilmColors.textSecondary),
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
            const Text(
              'За бажанням прив’яжіть приставку StarTV у домашній мережі Wi-Fi. Можна пропустити і зробити це пізніше.',
              style: TextStyle(color: StarFilmColors.textSecondary),
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
}
