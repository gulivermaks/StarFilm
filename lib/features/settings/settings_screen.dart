import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_state.dart';
import '../../app/l10n.dart';
import '../../app/theme.dart';
import '../../core/models/media_key.dart';
import '../../core/models/profile.dart';
import '../cloud_sync/cloud_sync_models.dart';
import '../discovery/gemini_client.dart';
import '../library/backup_codec.dart';
import '../players/mobile_players.dart';
import '../startv/startv_pairing_dialog.dart';
import 'ota_updater.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  static Future<BackupImportMode?> showBackupImportModeDialog(
    BuildContext context, {
    required BackupBundle bundle,
    required AppStrings strings,
  }) {
    final entriesCount = bundle.profiles.fold<int>(
      0,
      (sum, p) => sum + p.entries.length,
    );
    final sourceLabel =
        bundle.sourceFormat == 'startv' ? 'StarTV' : 'StarFilm';
    return showDialog<BackupImportMode>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StarFilmColors.surface,
        title: Text(strings.t('backup_import_mode_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              strings.t('backup_import_summary', {
                'source': sourceLabel,
                'profiles': bundle.profiles.length,
                'entries': entriesCount,
              }),
              style: const TextStyle(
                color: StarFilmColors.textSecondary,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, BackupImportMode.merge),
              child: Text(strings.t('backup_import_merge')),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, BackupImportMode.replace),
              child: Text(strings.t('backup_import_replace')),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(strings.t('cancel')),
          ),
        ],
      ),
    );
  }

  /// Displays release details with in-app SHA-256 and certificate-verified
  /// APK installation plus an external browser fallback link.
  static Future<void> showUpdateAvailableDialog(
    BuildContext context, {
    required ReleaseAssetInfo release,
    required AppStrings strings,
    OtaUpdater? updater,
    Future<Directory> Function()? getUpdatesDir,
    Future<String> Function(String apkPath)? onInstallApk,
    Future<bool> Function(Uri uri)? onOpenBrowser,
  }) {
    final notes = release.releaseNotes.trim();
    var downloading = false;
    var verifying = false;
    double? progress;
    String? errorText;

    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final busy = downloading || verifying;

          Future<void> startInAppInstall() async {
            if (busy) return;
            setDialogState(() {
              downloading = true;
              verifying = false;
              progress = null;
              errorText = null;
            });

            File? downloadedFile;
            try {
              final activeUpdater = updater;
              if (activeUpdater == null) {
                throw OtaDownloadException('no_updater');
              }
              final updatesDir = getUpdatesDir != null
                  ? await getUpdatesDir()
                  : Directory('${(await getTemporaryDirectory()).path}/updates');

              downloadedFile = await activeUpdater.downloadAndVerifyApk(
                release: release,
                updatesDir: updatesDir,
                onProgress: (received, total) {
                  if (!ctx.mounted) return;
                  setDialogState(() {
                    progress = total > 0 ? (received / total).clamp(0.0, 1.0) : null;
                  });
                },
              );

              if (!ctx.mounted) return;
              setDialogState(() {
                downloading = false;
                verifying = true;
              });

              final result = onInstallApk != null
                  ? await onInstallApk(downloadedFile.path)
                  : await OtaApkInstaller.verifyAndInstall(downloadedFile.path);

              if (!ctx.mounted) return;
              if (result == 'ok') {
                Navigator.pop(ctx);
                return;
              }
              if (result == 'signature_mismatch') {
                if (await downloadedFile.exists()) {
                  await downloadedFile.delete();
                }
                setDialogState(() {
                  downloading = false;
                  verifying = false;
                  errorText = strings.t('update_sig_error');
                });
                return;
              }
              if (result == 'permission_required') {
                setDialogState(() {
                  downloading = false;
                  verifying = false;
                  errorText = strings.t('update_install_permission');
                });
                return;
              }
              setDialogState(() {
                downloading = false;
                verifying = false;
                errorText = strings.t('update_download_error', {'e': result});
              });
            } on OtaDownloadException catch (e) {
              if (downloadedFile != null && await downloadedFile.exists()) {
                await downloadedFile.delete();
              }
              if (!ctx.mounted) return;
              setDialogState(() {
                downloading = false;
                verifying = false;
                errorText = e.code == 'checksum_mismatch'
                    ? strings.t('update_checksum_error')
                    : strings.t('update_download_error', {'e': e.code});
              });
            } catch (e) {
              if (!ctx.mounted) return;
              setDialogState(() {
                downloading = false;
                verifying = false;
                errorText = strings.t('update_download_error', {'e': '$e'});
              });
            }
          }

          return AlertDialog(
            backgroundColor: StarFilmColors.surface,
            title: Text(strings.t('update_available_title', {'v': release.versionName})),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (notes.isNotEmpty)
                    Flexible(
                      child: SingleChildScrollView(
                        child: Text(notes, style: const TextStyle(height: 1.4)),
                      ),
                    ),
                  if (busy) ...[
                    if (notes.isNotEmpty) const SizedBox(height: 12),
                    LinearProgressIndicator(value: verifying ? null : progress),
                    const SizedBox(height: 8),
                    Text(
                      verifying
                          ? strings.t('update_verifying')
                          : strings.t('update_downloading', {
                              'pct': ((progress ?? 0) * 100).round(),
                            }),
                      style: const TextStyle(
                        color: StarFilmColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  if (errorText != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      errorText!,
                      style: const TextStyle(color: StarFilmColors.error, fontSize: 13),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(ctx),
                child: Text(strings.t('close')),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        final uri = Uri.tryParse(release.downloadUrl);
                        Navigator.pop(ctx);
                        if (uri != null) {
                          if (onOpenBrowser != null) {
                            await onOpenBrowser(uri);
                          } else {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        }
                      },
                child: Text(strings.t('update_open_browser')),
              ),
              FilledButton.icon(
                onPressed: busy ? null : startInAppInstall,
                icon: const Icon(Icons.system_update_alt),
                label: Text(strings.t('update_install_apk')),
              ),
            ],
          );
        },
      ),
    );
  }

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
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
          _sectionHeader(s.t('profiles')),
          for (final p in state.profiles)
            ListTile(
              leading: Icon(
                p.id == state.activeProfileId ? Icons.check_circle : Icons.person_outline,
                color: p.id == state.activeProfileId ? StarFilmColors.lime : null,
              ),
              title: Text(p.name),
              subtitle: Text(p.isMain ? s.t('profile_main') : p.id),
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
            subtitle: Text(
              state.tmdbKey.isEmpty ? s.t('key_missing') : s.t('key_saved_local'),
            ),
            trailing: const Icon(Icons.edit),
            onTap: () => _editKeyDialog(isTmdb: true, current: state.tmdbKey),
          ),
          ListTile(
            title: Text(s.t('gemini_key')),
            subtitle: Text(
              state.geminiKey.isEmpty ? s.t('key_missing') : s.t('key_saved_local'),
            ),
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
            subtitle: Text(
              s.t('excluded_count', {'n': state.activeProfile.preferences.excludedGenres.length}),
            ),
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
                  : (state.firebaseConfigured ? s.t('sync_offline') : s.t('local_mode')),
            ),
            subtitle: Text(
              state.firebaseConfigured
                  ? s.t('sync_pending', {'n': state.pendingSyncCount})
                  : s.t('firebase_missing'),
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
                    onPressed: _syncCloud,
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
    final s = ref.read(appControllerProvider).strings;
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StarFilmColors.surface,
        title: Text(s.t('new_profile')),
        content: TextField(controller: ctrl, maxLength: 24, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.t('cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: Text(s.t('ok'))),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await ref.read(appControllerProvider.notifier).createProfile(name);
    }
  }

  Future<void> _editKeyDialog({required bool isTmdb, required String current}) async {
    final s = ref.read(appControllerProvider).strings;
    final ctrl = TextEditingController(text: current);
    bool verifying = false;
    bool? ok;
    String? verifyError;

    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          backgroundColor: StarFilmColors.surface,
          title: Text(isTmdb ? s.t('tmdb_key') : s.t('gemini_key')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: isTmdb ? s.t('tmdb_key_hint') : 'AIza...',
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
                Text(
                  s.t('key_verified_ok'),
                  style: const TextStyle(color: StarFilmColors.success, fontSize: 12),
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
                        if (val.isEmpty) {
                          setModalState(() {
                            verifying = false;
                            ok = false;
                            verifyError = s.t('key_empty');
                          });
                          return;
                        }
                        final valid = isTmdb
                            ? await services.tmdb.verifyKey(val)
                            : await services.gemini.verifyKey(
                                val,
                                model: ref.read(appControllerProvider).geminiModel,
                              );
                        setModalState(() {
                          verifying = false;
                          ok = valid;
                          verifyError = valid ? null : s.t('key_rejected');
                        });
                      } catch (e) {
                        setModalState(() {
                          verifying = false;
                          ok = false;
                          verifyError = s.t('key_verify_error', {'e': '$e'});
                        });
                      }
                    },
              child: Text(verifying ? '...' : s.t('verify')),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.t('cancel'))),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: Text(s.t('save')),
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
              child: Text(state.strings.t('ok')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _syncCloud() async {
    final s = ref.read(appControllerProvider).strings;
    final res = await ref.read(appControllerProvider.notifier).syncCloudNow();
    if (!mounted) return;
    final msg = switch (res.state) {
      SyncStatusState.synced => s.t('sync_done', {
          'pushed': res.pushedCount,
          'pulled': res.pulledCount,
        }),
      SyncStatusState.quotaExceeded => s.t('sync_quota'),
      SyncStatusState.error => s.t('sync_error', {'e': res.message}),
      SyncStatusState.notConfigured => s.t('sync_offline'),
      SyncStatusState.offlineLocal => s.t('local_mode'),
      SyncStatusState.syncing => s.t('sync_now'),
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _syncTv() async {
    final s = ref.read(appControllerProvider).strings;
    setState(() => _syncingTv = true);
    try {
      final count = await ref.read(appControllerProvider.notifier).syncWithHomeTv();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.t('tv_synced_count', {'n': count}))),
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
    final s = ref.read(appControllerProvider).strings;
    try {
      await ref.read(appControllerProvider.notifier).transferKeysToHomeTv();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.t('tv_keys_sent'))),
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
    final s = ref.read(appControllerProvider).strings;
    final BackupBundle bundle;
    try {
      final raw = await File(path).readAsString();
      bundle = BackupCodec.decodeBackup(raw);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.t('backup_import_error', {'e': '$e'}))),
        );
      }
      return;
    }

    if (!mounted) return;
    final mode = await SettingsScreen.showBackupImportModeDialog(
      context,
      bundle: bundle,
      strings: s,
    );
    if (mode == null) return;

    final count = await ref
        .read(appControllerProvider.notifier)
        .importBackupBundle(bundle, mode: mode);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.t('backup_imported_count', {'n': count}))),
      );
    }
  }

  void _showDiagnostics(BuildContext context) {
    final state = ref.read(appControllerProvider);
    final s = state.strings;
    final ok = s.t('diag_ok');
    final no = s.t('diag_not_set');
    final statusLine = s.t('diag_status_line', {
      'tmdb': state.tmdbKey.trim().isNotEmpty ? ok : no,
      'gemini': state.geminiKey.trim().isNotEmpty ? ok : no,
      'cloud': state.cloudUid.isNotEmpty ? ok : no,
      'profiles': state.profiles.length,
      'entries': state.entries.length,
      'tv': state.activeTv?.deviceName ?? no,
    });
    final logText = ref.read(appServicesProvider).log.exportText();
    final body = logText.isEmpty ? s.t('diagnostics_empty') : logText;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StarFilmColors.surface,
        title: Text(s.t('diagnostics')),
        content: SingleChildScrollView(
          child: SelectableText('$statusLine\n\n$body'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.t('close'))),
        ],
      ),
    );
  }

  Future<void> _checkUpdates() async {
    final s = ref.read(appControllerProvider).strings;
    final updater = ref.read(appServicesProvider).updater;
    setState(() => _checkingUpdates = true);
    try {
      final info = await PackageInfo.fromPlatform();
      final latest = await updater.checkLatest(currentVersion: info.version);
      if (!mounted) return;
      if (latest == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.t('update_up_to_date', {'v': info.version}))),
        );
      } else {
        await SettingsScreen.showUpdateAvailableDialog(
          context,
          release: latest,
          strings: s,
          updater: updater,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _checkingUpdates = false);
    }
  }
}
