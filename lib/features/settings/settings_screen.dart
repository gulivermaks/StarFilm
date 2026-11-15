import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/app_state.dart';
import '../../app/theme.dart';
import '../../core/models/media_key.dart';
import '../../core/models/profile.dart';
import '../discovery/gemini_client.dart';
import '../players/mobile_players.dart';
import '../startv/startv_pairing_dialog.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String _versionLabel = '';
  bool _checkingUpdates = false;
  bool _syncingTv = false;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) {
        setState(() => _versionLabel = 'v${info.version} (${info.buildNumber})');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final s = state.strings;
    final activeTv = state.activeTv;

    return Scaffold(
      appBar: AppBar(title: Text(s.t('settings'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionHeader(s.t('profiles')),
          for (final p in state.profiles)
            ListTile(
              leading: Icon(
                p.id == state.activeProfileId ? Icons.check_circle : Icons.person_outline,
                color: p.id == state.activeProfileId ? StarFilmColors.lime : null,
              ),
              title: Text(p.name),
              subtitle: Text(p.isMain ? 'Основний' : p.id),
              onTap: () => ref.read(appControllerProvider.notifier).switchProfile(p.id),
              trailing: p.isMain
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () =>
                          ref.read(appControllerProvider.notifier).deleteProfile(p.id),
                    ),
            ),
          if (state.profiles.length < UserProfile.maxProfiles)
            OutlinedButton.icon(
              onPressed: () => _addProfile(context),
              icon: const Icon(Icons.person_add_alt_1),
              label: Text(s.t('add_profile')),
            ),
          const Divider(height: 32),

          _sectionHeader('${s.t('tmdb_key')} / ${s.t('gemini_key')}'),
          ListTile(
            title: Text(s.t('tmdb_key')),
            subtitle: Text(state.tmdbKey.isEmpty ? 'Не налаштовано' : 'Налаштовано (локально)'),
            trailing: const Icon(Icons.edit),
            onTap: () => _editKeyDialog(isTmdb: true, current: state.tmdbKey),
          ),
          ListTile(
            title: Text(s.t('gemini_key')),
            subtitle: Text(state.geminiKey.isEmpty ? 'Не налаштовано' : 'Налаштовано (локально)'),
            trailing: const Icon(Icons.edit),
            onTap: () => _editKeyDialog(isTmdb: false, current: state.geminiKey),
          ),
          ListTile(
            title: Text(s.t('gemini_model')),
            subtitle: Text(state.geminiModel),
            trailing: DropdownButton<String>(
              value: GeminiClient.defaultModels.contains(state.geminiModel)
                  ? state.geminiModel
                  : GeminiClient.defaultModels.first,
              items: [
                for (final m in GeminiClient.defaultModels)
                  DropdownMenuItem(value: m, child: Text(m)),
              ],
              onChanged: (v) {
                if (v != null) {
                  ref.read(appControllerProvider.notifier).setGeminiModel(v);
                }
              },
            ),
          ),
          const Divider(height: 32),

          _sectionHeader('${s.t('ui_language')} / ${s.t('content_language')}'),
          ListTile(
            title: Text(s.t('ui_language')),
            trailing: DropdownButton<String>(
              value: state.uiLanguage,
              items: const [
                DropdownMenuItem(value: 'uk', child: Text('Українська')),
                DropdownMenuItem(value: 'ru', child: Text('Русский')),
                DropdownMenuItem(value: 'en', child: Text('English')),
              ],
              onChanged: (v) {
                if (v != null) ref.read(appControllerProvider.notifier).setUiLanguage(v);
              },
            ),
          ),
          ListTile(
            title: Text(s.t('content_language')),
            trailing: DropdownButton<String>(
              value: state.activeProfile.preferences.contentLanguage,
              items: const [
                DropdownMenuItem(value: 'uk', child: Text('uk-UA')),
                DropdownMenuItem(value: 'ru', child: Text('ru-RU')),
                DropdownMenuItem(value: 'en', child: Text('en-US')),
              ],
              onChanged: (v) {
                if (v != null) {
                  ref.read(appControllerProvider.notifier).updateProfilePreferences(
                        state.activeProfile.preferences.copyWith(contentLanguage: v),
                      );
                }
              },
            ),
          ),
          ListTile(
            title: Text(s.t('excluded_genres')),
            subtitle: Text('${state.activeProfile.preferences.excludedGenres.length} вибрано'),
            trailing: const Icon(Icons.tune),
            onTap: () => _editExcludedGenres(context, state),
          ),
          TextButton(
            onPressed: () => ref.read(appControllerProvider.notifier).resetTasteFilters(),
            child: Text(s.t('reset_taste')),
          ),
          const Divider(height: 32),

          _sectionHeader(s.t('onboarding_sync_title')),
          ListTile(
            leading: Icon(
              state.cloudUid.isNotEmpty ? Icons.cloud_done : Icons.cloud_off_outlined,
              color: state.cloudUid.isNotEmpty ? StarFilmColors.lime : null,
            ),
            title: Text(
              state.cloudUid.isNotEmpty
                  ? state.cloudEmail
                  : (state.firebaseConfigured ? s.t('sync_offline') : 'Локальний режим'),
            ),
            subtitle: Text(
              state.firebaseConfigured
                  ? 'Очікує синхронізації: ${state.pendingSyncCount}'
                  : 'Очікує google-services.json для Firebase Spark',
            ),
          ),
          const SizedBox(height: 6),
          if (state.cloudUid.isEmpty)
            FilledButton(
              onPressed: state.firebaseConfigured
                  ? () => ref.read(appControllerProvider.notifier).signInWithGoogle()
                  : null,
              child: Text(s.t('google_signin')),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        ref.read(appControllerProvider.notifier).syncCloudNow(),
                    child: Text(s.t('sync_now')),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextButton(
                    onPressed: () =>
                        ref.read(appControllerProvider.notifier).signOutFromGoogle(),
                    child: Text(s.t('google_signout')),
                  ),
                ),
              ],
            ),
          const Divider(height: 32),

          _sectionHeader(s.t('startv_section')),
          for (final tv in state.pairedDevices)
            ListTile(
              leading: Icon(
                Icons.tv,
                color: tv.tvId == activeTv?.tvId ? StarFilmColors.lime : null,
              ),
              title: Text(tv.deviceName),
              subtitle: Text(
                '${tv.ip}:${tv.port} • ${tv.canSyncLibrary ? s.t('startv_home_mode') : s.t('startv_guest_mode')}',
              ),
              onTap: () => ref.read(appControllerProvider.notifier).selectStarTv(tv),
              trailing: IconButton(
                icon: const Icon(Icons.link_off),
                onPressed: () => ref.read(appControllerProvider.notifier).removeStarTv(tv),
              ),
            ),
          OutlinedButton.icon(
            onPressed: () => StarTvPairingDialog.show(context),
            icon: const Icon(Icons.qr_code_scanner),
            label: Text(s.t('startv_connect')),
          ),
          if (activeTv != null) ...[
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: !activeTv.canSyncLibrary || _syncingTv ? null : _syncTv,
              icon: const Icon(Icons.sync),
              label: Text(s.t('startv_sync')),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: !activeTv.canTransferKeys ? null : _transferKeys,
              icon: const Icon(Icons.vpn_key_outlined),
              label: Text(s.t('startv_send_keys')),
            ),
          ],
          const Divider(height: 32),

          _sectionHeader(s.t('mobile_player')),
          DropdownButtonFormField<MobilePlayerId>(
            initialValue: state.preferredPlayer,
            decoration: const InputDecoration(isDense: true),
            items: [
              for (final p in MobilePlayerId.values)
                DropdownMenuItem(value: p, child: Text(p.label)),
            ],
            onChanged: (v) {
              if (v != null) ref.read(appControllerProvider.notifier).setPreferredPlayer(v);
            },
          ),
          const Divider(height: 32),

          _sectionHeader('${s.t('backup_export')} / ${s.t('diagnostics')}'),
          OutlinedButton.icon(
            onPressed: _exportBackup,
            icon: const Icon(Icons.upload_file),
            label: Text(s.t('backup_export')),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _importBackup,
            icon: const Icon(Icons.download_for_offline_outlined),
            label: Text(s.t('backup_import')),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _showDiagnostics(context),
            icon: const Icon(Icons.bug_report_outlined),
            label: Text(s.t('diagnostics')),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _checkingUpdates ? null : _checkUpdates,
            icon: const Icon(Icons.system_update_outlined),
            label: Text('${s.t('check_updates')} $_versionLabel'),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: StarFilmColors.lime,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
  }

  Future<void> _addProfile(BuildContext context) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StarFilmColors.surface,
        title: const Text('Новий профіль'),
        content: TextField(controller: ctrl, maxLength: 24, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Скасувати')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('ОК')),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await ref.read(appControllerProvider.notifier).createProfile(name);
    }
  }

  Future<void> _editKeyDialog({required bool isTmdb, required String current}) async {
    final ctrl = TextEditingController(text: current);
    bool verifying = false;
    bool? ok;
    String? verifyError;

    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          backgroundColor: StarFilmColors.surface,
          title: Text(isTmdb ? 'TMDB API Key' : 'Gemini API Key'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: isTmdb ? 'v3 API Key або v4 Read Access Token' : 'AIza...',
                  suffixIcon: ok == null
                      ? null
                      : Icon(
                          ok! ? Icons.check_circle : Icons.error,
                          color: ok! ? StarFilmColors.success : StarFilmColors.error,
                        ),
                ),
              ),
              if (verifyError != null) ...[
                const SizedBox(height: 8),
                Text(
                  verifyError!,
                  style: const TextStyle(color: StarFilmColors.error, fontSize: 12),
                ),
              ] else if (ok == true) ...[
                const SizedBox(height: 8),
                const Text(
                  'Ключ перевірено успішно',
                  style: TextStyle(color: StarFilmColors.success, fontSize: 12),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: verifying
                  ? null
                  : () async {
                      setModalState(() {
                        verifying = true;
                        verifyError = null;
                      });
                      try {
                        final services = ref.read(appServicesProvider);
                        final val = ctrl.text.trim();
                        final valid = isTmdb
                            ? await services.tmdb.verifyKey(val)
                            : await services.gemini.verifyKey(
                                val,
                                model: ref.read(appControllerProvider).geminiModel,
                              );
                        setModalState(() {
                          verifying = false;
                          ok = valid;
                          verifyError = valid ? null : 'Ключ не прийнято сервером';
                        });
                      } catch (e) {
                        setModalState(() {
                          verifying = false;
                          ok = false;
                          verifyError = 'Помилка перевірки: $e';
                        });
                      }
                    },
              child: Text(verifying ? '...' : 'Перевірити'),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Скасувати')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('Зберегти'),
            ),
          ],
        ),
      ),
    );
    if (next != null) {
      await ref.read(appControllerProvider.notifier).setApiKeys(
            tmdbKey: isTmdb ? next : null,
            geminiKey: isTmdb ? null : next,
          );
    }
  }

  Future<void> _editExcludedGenres(BuildContext context, AppControllerState state) async {
    final selected = state.activeProfile.preferences.excludedGenres.toSet();
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          backgroundColor: StarFilmColors.surface,
          title: Text(state.strings.t('excluded_genres')),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final g in kStandardGenres)
                    FilterChip(
                      label: Text(g.labelFor(state.uiLanguage)),
                      selected: selected.contains(g.id),
                      onSelected: (on) {
                        setModalState(() {
                          if (on) {
                            selected.add(g.id);
                          } else {
                            selected.remove(g.id);
                          }
                        });
                      },
                    ),
                ],
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () {
                final sorted = selected.toList()..sort();
                ref.read(appControllerProvider.notifier).updateProfilePreferences(
                      state.activeProfile.preferences.copyWith(excludedGenres: sorted),
                    );
                Navigator.pop(ctx);
              },
              child: const Text('ОК'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _syncTv() async {
    setState(() => _syncingTv = true);
    try {
      final count = await ref.read(appControllerProvider.notifier).syncWithHomeTv();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Синхронізовано записів: $count')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _syncingTv = false);
    }
  }

  Future<void> _transferKeys() async {
    try {
      await ref.read(appControllerProvider.notifier).transferKeysToHomeTv();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ключі передано на StarTV')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _exportBackup() async {
    final json = await ref.read(appControllerProvider.notifier).exportBackupJson();
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/starfilm_backup.json');
    await file.writeAsString(json);
    await Share.shareXFiles([XFile(file.path)]);
  }

  Future<void> _importBackup() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    final path = res?.files.single.path;
    if (path == null) return;
    final raw = await File(path).readAsString();
    final count = await ref.read(appControllerProvider.notifier).importBackupJson(raw);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Імпортовано записів: $count')),
      );
    }
  }

  void _showDiagnostics(BuildContext context) {
    final logText = ref.read(appServicesProvider).log.exportText();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StarFilmColors.surface,
        title: const Text('Діагностика'),
        content: SingleChildScrollView(
          child: SelectableText(logText.isEmpty ? 'Журнал порожній' : logText),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрити')),
        ],
      ),
    );
  }

  Future<void> _checkUpdates() async {
    setState(() => _checkingUpdates = true);
    try {
      final info = await PackageInfo.fromPlatform();
      final latest = await ref
          .read(appServicesProvider)
          .updater
          .checkLatest(currentVersion: info.version);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            latest == null
                ? 'У вас актуальна версія (${info.version})'
                : 'Доступне оновлення StarFilm ${latest.versionName}',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _checkingUpdates = false);
    }
  }
}
