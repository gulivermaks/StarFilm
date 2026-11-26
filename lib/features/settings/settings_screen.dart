import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../library/rating_csv_import.dart';
import '../players/mobile_players.dart';
import '../startv/startv_client.dart';
import '../startv/startv_pairing_dialog.dart';
import 'ota_updater.dart';

enum _SettingsKeyKind { tmdb, gemini, backupAi, kinopoisk }

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  static Future<bool> interactiveGoogleSignIn(
    BuildContext context,
    WidgetRef ref,
  ) async {
    return ref.read(appControllerProvider.notifier).signInWithGoogle(
      onLocalDataConflict: (summary, email) async {
        if (!context.mounted) return SignInMergeChoice.mergeLocalWithCloud;
        final s = ref.read(appControllerProvider).strings;
        final choice = await showDialog<SignInMergeChoice>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            backgroundColor: StarFilmColors.surface,
            title: Text(s.t('cloud_conflict_title')),
            content: Text(
              s.t('cloud_conflict_body', {
                'entries': summary.entriesCount,
                'collections': summary.collectionsCount,
                'profiles': summary.extraProfilesCount,
                'email': email,
              }),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, SignInMergeChoice.cancel),
                child: Text(s.t('cancel')),
              ),
              OutlinedButton(
                onPressed: () =>
                    Navigator.pop(ctx, SignInMergeChoice.replaceLocalWithCloud),
                child: Text(s.t('cloud_conflict_replace')),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(ctx, SignInMergeChoice.mergeLocalWithCloud),
                child: Text(s.t('cloud_conflict_merge')),
              ),
            ],
          ),
        );
        return choice ?? SignInMergeChoice.cancel;
      },
    );
  }

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

  /// Formats GitHub release notes by stripping raw Markdown symbols for readable dialog display.
  static String formatReleaseNotes(String raw) {
    final lines = raw.trim().split('\n');
    final cleaned = <String>[];
    for (final line in lines) {
      var text = line.trimRight();
      text = text.replaceFirst(RegExp(r'^\s*#{1,6}\s*'), '');
      text = text.replaceFirst(RegExp(r'^\s*[-*]\s+'), '• ');
      text = text.replaceAll('**', '').replaceAll('`', '');
      cleaned.add(text);
    }
    return cleaned.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
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
    final notes = formatReleaseNotes(release.releaseNotes);
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
  bool _checkingReleases = false;
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
              title: Text(state.displayProfileName(p)),
              subtitle: Text(
                p.isMain ? s.t('profile_main') : s.t('profile_subtitle'),
              ),
              onTap: () => ref.read(appControllerProvider.notifier).switchProfile(p.id),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: s.t('rename_profile'),
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    onPressed: () => _renameProfile(context, p),
                  ),
                  if (!p.isMain)
                    IconButton(
                      tooltip: s.t('delete'),
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () => _confirmDeleteProfile(context, p),
                    ),
                ],
              ),
            ),
          if (state.profiles.length < UserProfile.maxProfiles)
            OutlinedButton.icon(
              onPressed: () => _addProfile(context),
              icon: const Icon(Icons.person_add_alt_1),
              label: Text(s.t('add_profile')),
            ),
          const Divider(height: 32),

          _sectionHeader('${s.t('tmdb_key')} / ${s.t('gemini_key')} / ${s.t('kp_key')}'),
          ListTile(
            title: Text(s.t('tmdb_key')),
            subtitle: Text(
              state.tmdbKey.isEmpty ? s.t('key_missing') : s.t('key_saved_local'),
            ),
            trailing: const Icon(Icons.edit),
            onTap: () => _editKeyDialog(kind: _SettingsKeyKind.tmdb, current: state.tmdbKey),
          ),
          ListTile(
            title: Text(s.t('gemini_key')),
            subtitle: Text(
              state.geminiKey.isEmpty ? s.t('key_missing') : s.t('key_saved_local'),
            ),
            trailing: const Icon(Icons.edit),
            onTap: () => _editKeyDialog(kind: _SettingsKeyKind.gemini, current: state.geminiKey),
          ),
          ListTile(
            title: Text(s.t('backup_ai_key')),
            subtitle: Text(
              state.backupAiKey.trim().isEmpty
                  ? s.t('key_missing')
                  : s.t('backup_ai_saved_provider', {
                      'provider': GeminiClient.parseKeyList(state.backupAiKey)
                          .map((k) => GeminiClient.detectProvider(k).displayLabel)
                          .toSet()
                          .join(', '),
                    }),
            ),
            trailing: const Icon(Icons.edit),
            onTap: () => _editKeyDialog(
              kind: _SettingsKeyKind.backupAi,
              current: state.backupAiKey,
            ),
          ),
          ListTile(
            title: Text(s.t('kp_key')),
            subtitle: Text(
              state.kinopoiskKey.isEmpty ? s.t('key_missing') : s.t('key_saved_local'),
            ),
            trailing: const Icon(Icons.edit),
            onTap: () =>
                _editKeyDialog(kind: _SettingsKeyKind.kinopoisk, current: state.kinopoiskKey),
          ),
          ListTile(
            title: Text(s.t('gemini_model')),
            subtitle: DropdownButton<String>(
              isExpanded: true,
              value: state.geminiModel,
              items: [
                for (final m in GeminiClient.defaultModels)
                  DropdownMenuItem(value: m, child: Text(m)),
                if (!GeminiClient.defaultModels.contains(state.geminiModel))
                  DropdownMenuItem(
                    value: state.geminiModel,
                    child: Text(state.geminiModel),
                  ),
                DropdownMenuItem(
                  value: '_custom_',
                  child: Text(s.t('custom_gemini_model')),
                ),
              ],
              onChanged: (v) async {
                if (v == null) return;
                if (v == '_custom_') {
                  await _editCustomGeminiModel(context, state.geminiModel);
                } else {
                  await ref.read(appControllerProvider.notifier).setGeminiModel(v);
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
                  ? () => SettingsScreen.interactiveGoogleSignIn(context, ref)
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
                    onPressed: () => _confirmAndSignOut(context),
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
                DropdownMenuItem(value: p, child: Text(p.localizedLabel(s))),
            ],
            onChanged: (v) {
              if (v != null) ref.read(appControllerProvider.notifier).setPreferredPlayer(v);
            },
          ),
          const Divider(height: 32),

          _sectionHeader(s.t('release_alerts_toggle')),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(s.t('release_alerts_toggle')),
            subtitle: Text(s.t('release_alerts_desc'), style: const TextStyle(fontSize: 12)),
            value: state.releaseNotificationsEnabled,
            onChanged: (v) =>
                ref.read(appControllerProvider.notifier).setReleaseNotificationsEnabled(v),
          ),
          OutlinedButton.icon(
            onPressed: _checkingReleases ? null : _checkReleasesNow,
            icon: _checkingReleases
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.notifications_active_outlined),
            label: Text(s.t('release_check_now')),
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
            onPressed: _importCsvRatings,
            icon: const Icon(Icons.table_rows_outlined),
            label: Text(s.t('csv_import_btn')),
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
          const SizedBox(height: 20),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Image.asset(
                'assets/images/starfilm_logo.png',
                height: 32,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
          Text(
            s.t('tmdb_attribution'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: StarFilmColors.textSecondary,
              fontSize: 12,
            ),
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

  Future<void> _confirmAndSignOut(BuildContext context) async {
    final state = ref.read(appControllerProvider);
    final s = state.strings;
    final pending = state.pendingSyncCount;
    final body = pending > 0
        ? s.t('signout_pending_body', {'n': pending})
        : s.t('signout_confirm_body');

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StarFilmColors.surface,
        title: Text(s.t('signout_confirm_title')),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: Text(s.t('cancel')),
          ),
          if (pending > 0)
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, 'sync_first'),
              child: Text(s.t('signout_sync_first')),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'signout'),
            child: Text(s.t('signout_action')),
          ),
        ],
      ),
    );

    if (action == 'sync_first') {
      final res = await ref.read(appControllerProvider.notifier).syncCloudNow();
      if (!mounted) return;
      if (res.state == SyncStatusState.synced) {
        await ref.read(appControllerProvider.notifier).signOutFromGoogle();
      } else {
        ScaffoldMessenger.of(this.context).showSnackBar(
          SnackBar(content: Text('${res.state.name}: ${res.message}')),
        );
      }
      return;
    }

    if (action == 'signout') {
      await ref.read(appControllerProvider.notifier).signOutFromGoogle();
    }
  }

  Future<void> _addProfile(BuildContext context) async {
    final s = ref.read(appControllerProvider).strings;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _SingleTextDialog(
        title: s.t('new_profile'),
        cancelLabel: s.t('cancel'),
        okLabel: s.t('ok'),
        maxLength: 24,
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await ref.read(appControllerProvider.notifier).createProfile(name);
    }
  }

  Future<void> _renameProfile(BuildContext context, UserProfile profile) async {
    final state = ref.read(appControllerProvider);
    final s = state.strings;
    final nextName = await showDialog<String>(
      context: context,
      builder: (_) => _SingleTextDialog(
        title: s.t('rename_profile'),
        initialValue: state.displayProfileName(profile),
        cancelLabel: s.t('cancel'),
        okLabel: s.t('ok'),
        maxLength: 24,
      ),
    );
    if (nextName != null && nextName.trim().isNotEmpty) {
      await ref
          .read(appControllerProvider.notifier)
          .renameProfile(profile, nextName.trim());
    }
  }

  Future<void> _confirmDeleteProfile(
    BuildContext context,
    UserProfile profile,
  ) async {
    final s = ref.read(appControllerProvider).strings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StarFilmColors.surface,
        title: Text(s.t('delete_profile_confirm_title')),
        content: Text(s.t('delete_profile_confirm_body', {'name': profile.name})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.t('delete')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(appControllerProvider.notifier).deleteProfile(profile.id);
    }
  }

  Future<void> _editCustomGeminiModel(
    BuildContext context,
    String currentModel,
  ) async {
    final s = ref.read(appControllerProvider).strings;
    final model = await showDialog<String>(
      context: context,
      builder: (_) => _SingleTextDialog(
        title: s.t('custom_gemini_title'),
        initialValue: currentModel,
        hintText: GeminiClient.fallbackModel,
        cancelLabel: s.t('cancel'),
        okLabel: s.t('save'),
      ),
    );
    if (model != null && model.trim().isNotEmpty) {
      await ref.read(appControllerProvider.notifier).setGeminiModel(model.trim());
    }
  }

  Future<void> _editKeyDialog({
    required _SettingsKeyKind kind,
    required String current,
  }) async {
    final s = ref.read(appControllerProvider).strings;
    final title = switch (kind) {
      _SettingsKeyKind.tmdb => s.t('tmdb_key'),
      _SettingsKeyKind.gemini => s.t('gemini_key'),
      _SettingsKeyKind.backupAi => s.t('backup_ai_key'),
      _SettingsKeyKind.kinopoisk => s.t('kp_key'),
    };
    final hint = switch (kind) {
      _SettingsKeyKind.tmdb => s.t('tmdb_key_hint'),
      _SettingsKeyKind.gemini => 'AIza...',
      _SettingsKeyKind.backupAi => s.t('backup_ai_hint'),
      _SettingsKeyKind.kinopoisk => 'UUID / X-API-KEY',
    };

    final next = await showDialog<String>(
      context: context,
      builder: (_) => _EditKeyDialog(
        title: title,
        hint: hint,
        initialValue: current,
        strings: s,
        multiline: kind == _SettingsKeyKind.backupAi,
        verifyCallback: (val) async {
          final services = ref.read(appServicesProvider);
          return switch (kind) {
            _SettingsKeyKind.tmdb => services.tmdb.verifyKey(val),
            _SettingsKeyKind.gemini => services.gemini.verifyKey(
                val,
                model: ref.read(appControllerProvider).geminiModel,
              ),
            _SettingsKeyKind.backupAi => services.gemini.verifyBackupKey(val),
            _SettingsKeyKind.kinopoisk => services.kinopoisk.verifyKey(val),
          };
        },
      ),
    );
    if (next != null) {
      await ref.read(appControllerProvider.notifier).setApiKeys(
            tmdbKey: kind == _SettingsKeyKind.tmdb ? next : null,
            geminiKey: kind == _SettingsKeyKind.gemini ? next : null,
            backupAiKey: kind == _SettingsKeyKind.backupAi ? next : null,
            kinopoiskKey: kind == _SettingsKeyKind.kinopoisk ? next : null,
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
    } on StarTvException catch (e) {
      if (mounted) {
        if (e.statusCode == 401 || e.statusCode == 403) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s.t('startv_error_auth'))),
          );
          await StarTvPairingDialog.show(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s.t('startv_error_network'))),
          );
        }
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
    } on StarTvException catch (e) {
      if (mounted) {
        if (e.statusCode == 401 || e.statusCode == 403) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s.t('startv_error_auth'))),
          );
          await StarTvPairingDialog.show(context);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s.t('startv_error_network'))),
          );
        }
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

  Future<void> _checkReleasesNow() async {
    final s = ref.read(appControllerProvider).strings;
    setState(() => _checkingReleases = true);
    try {
      final matches = await ref
          .read(appControllerProvider.notifier)
          .checkMovieDigitalReleases(manual: true);
      if (!mounted) return;
      final msg = matches.isEmpty
          ? s.t('release_none_found')
          : s.t('release_found_banner', {
              'titles': matches.take(3).map((m) => m.entry.title).join(', '),
            });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _checkingReleases = false);
    }
  }

  Future<void> _importCsvRatings() async {
    final s = ref.read(appControllerProvider).strings;
    await showDialog<void>(
      context: context,
      builder: (_) => _CsvImportDialog(
        strings: s,
        onImport: (rawText, onProgress) => ref
            .read(appControllerProvider.notifier)
            .importCsvRatings(rawText, onProgress: onProgress),
      ),
    );
  }

  void _showDiagnostics(BuildContext context) {
    final state = ref.read(appControllerProvider);
    final s = state.strings;
    final ok = s.t('diag_ok');
    final no = s.t('diag_not_set');
    final statusLine = s.t('diag_status_line', {
      'tmdb': state.tmdbKey.trim().isNotEmpty ? ok : no,
      'gemini': state.geminiKey.trim().isNotEmpty ? ok : no,
      'kp': state.kinopoiskKey.trim().isNotEmpty ? ok : no,
      'cloud': state.cloudUid.isNotEmpty ? ok : no,
      'profiles': state.profiles.length,
      'entries': state.entries.length,
      'tv': state.activeTv?.deviceName ?? no,
    });
    final backupProviders = GeminiClient.parseKeyList(state.backupAiKey)
        .map((k) => GeminiClient.detectProvider(k).displayLabel)
        .toSet()
        .join('/');
    final backupLine =
        'Backup AI: ${backupProviders.isNotEmpty ? backupProviders : no} • Model: ${state.geminiModel}';
    final logText = ref.read(appServicesProvider).log.exportText();
    final body = logText.isEmpty ? s.t('diagnostics_empty') : logText;
    final fullReport = '$statusLine\n$backupLine\n\n$body';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: StarFilmColors.surface,
        title: Text(s.t('diagnostics')),
        content: SingleChildScrollView(
          child: SelectableText(fullReport),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: fullReport));
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text(s.t('copied_diagnostics'))),
                );
              }
            },
            icon: const Icon(Icons.copy, size: 16),
            label: Text(s.t('copy_diagnostics')),
          ),
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

class _SingleTextDialog extends StatefulWidget {
  const _SingleTextDialog({
    required this.title,
    required this.cancelLabel,
    required this.okLabel,
    this.initialValue = '',
    this.hintText,
    this.maxLength,
  });

  final String title;
  final String cancelLabel;
  final String okLabel;
  final String initialValue;
  final String? hintText;
  final int? maxLength;

  @override
  State<_SingleTextDialog> createState() => _SingleTextDialogState();
}

class _SingleTextDialogState extends State<_SingleTextDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: StarFilmColors.surface,
      title: Text(widget.title),
      content: TextField(
        controller: _ctrl,
        maxLength: widget.maxLength,
        autofocus: true,
        decoration: InputDecoration(
          hintText: widget.hintText,
        ),
        buildCounter: widget.maxLength == null
            ? null
            : (_, {required currentLength, required isFocused, required maxLength}) =>
                Text(
                  '$currentLength/$maxLength',
                  style: const TextStyle(
                    fontSize: 12,
                    color: StarFilmColors.textSecondary,
                  ),
                ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          child: Text(widget.okLabel),
        ),
      ],
    );
  }
}

class _EditKeyDialog extends StatefulWidget {
  const _EditKeyDialog({
    required this.title,
    required this.hint,
    required this.initialValue,
    required this.strings,
    required this.verifyCallback,
    this.multiline = false,
  });

  final String title;
  final String hint;
  final String initialValue;
  final AppStrings strings;
  final Future<bool> Function(String val) verifyCallback;
  final bool multiline;

  @override
  State<_EditKeyDialog> createState() => _EditKeyDialogState();
}

class _EditKeyDialogState extends State<_EditKeyDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initialValue);
  bool _verifying = false;
  bool? _ok;
  String? _verifyError;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    return AlertDialog(
      backgroundColor: StarFilmColors.surface,
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            minLines: 1,
            maxLines: widget.multiline ? 3 : 1,
            decoration: InputDecoration(
              hintText: widget.hint,
              suffixIcon: _ok == null
                  ? null
                  : Icon(
                      _ok! ? Icons.check_circle : Icons.error,
                      color: _ok! ? StarFilmColors.success : StarFilmColors.error,
                    ),
            ),
          ),
          if (_verifyError != null) ...[
            const SizedBox(height: 8),
            Text(
              _verifyError!,
              style: const TextStyle(color: StarFilmColors.error, fontSize: 12),
            ),
          ] else if (_ok == true) ...[
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
          onPressed: _verifying
              ? null
              : () async {
                  setState(() {
                    _verifying = true;
                    _verifyError = null;
                  });
                  try {
                    final val = _ctrl.text.trim();
                    if (val.isEmpty) {
                      setState(() {
                        _verifying = false;
                        _ok = false;
                        _verifyError = s.t('key_empty');
                      });
                      return;
                    }
                    final valid = await widget.verifyCallback(val);
                    if (mounted) {
                      setState(() {
                        _verifying = false;
                        _ok = valid;
                        _verifyError = valid ? null : s.t('key_rejected');
                      });
                    }
                  } catch (e) {
                    if (mounted) {
                      setState(() {
                        _verifying = false;
                        _ok = false;
                        _verifyError = s.t('key_verify_error', {'e': '$e'});
                      });
                    }
                  }
                },
          child: Text(_verifying ? '...' : s.t('verify')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.t('cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          child: Text(s.t('save')),
        ),
      ],
    );
  }
}

class _CsvImportDialog extends StatefulWidget {
  const _CsvImportDialog({
    required this.strings,
    required this.onImport,
  });

  final AppStrings strings;
  final Future<RatingImportBatchResult> Function(
    String rawText,
    void Function(int done, int total) onProgress,
  ) onImport;

  @override
  State<_CsvImportDialog> createState() => _CsvImportDialogState();
}

class _CsvImportDialogState extends State<_CsvImportDialog> {
  final _textCtrl = TextEditingController();
  bool _importing = false;
  int _doneCount = 0;
  int _totalCount = 0;
  RatingImportBatchResult? _result;
  String? _errorMessage;

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  String _friendlyParseError(FormatException e) {
    final s = widget.strings;
    final msg = e.message;
    if (msg.contains('Empty rating list')) return s.t('csv_error_empty');
    if (msg.contains('Maximum 100') || msg.contains('too large')) {
      return s.t('csv_error_too_many');
    }
    return s.t('csv_error_format');
  }

  Future<void> _runImport() async {
    final s = widget.strings;
    final raw = _textCtrl.text;
    if (raw.trim().isEmpty) {
      setState(() {
        _errorMessage = s.t('csv_error_empty');
        _result = null;
      });
      return;
    }
    final List<RatingImportRow> parsed;
    try {
      parsed = RatingCsvParser.parse(raw);
    } on FormatException catch (e) {
      setState(() {
        _errorMessage = _friendlyParseError(e);
        _result = null;
      });
      return;
    }

    setState(() {
      _importing = true;
      _doneCount = 0;
      _totalCount = parsed.length;
      _result = null;
      _errorMessage = null;
    });

    try {
      final batch = await widget.onImport(raw, (d, t) {
        if (mounted) {
          setState(() {
            _doneCount = d;
            _totalCount = t;
          });
        }
      });
      if (mounted) {
        setState(() {
          _importing = false;
          _result = batch;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _importing = false;
          _errorMessage = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    return AlertDialog(
      backgroundColor: StarFilmColors.surface,
      title: Text(s.t('csv_import_btn')),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                s.t('csv_import_hint'),
                style: const TextStyle(color: StarFilmColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _importing
                    ? null
                    : () async {
                        final picked = await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: const ['csv', 'tsv', 'txt'],
                        );
                        final path = picked?.files.single.path;
                        if (path == null) return;
                        final bytes = await File(path).readAsBytes();
                        _textCtrl.text = RatingCsvParser.decodeBytesWithFallback(bytes);
                        if (mounted) setState(() => _errorMessage = null);
                      },
                icon: const Icon(Icons.folder_open),
                label: Text(s.t('csv_pick_file')),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _textCtrl,
                minLines: 4,
                maxLines: 8,
                enabled: !_importing,
                onChanged: (_) {
                  if (_errorMessage != null) setState(() => _errorMessage = null);
                },
                decoration: InputDecoration(
                  hintText: s.t('csv_paste_label'),
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 10),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: StarFilmColors.error, fontSize: 13),
                ),
              ],
              if (_importing) ...[
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: _totalCount > 0 ? _doneCount / _totalCount : null,
                ),
                const SizedBox(height: 6),
                Text(
                  s.t('csv_import_progress', {'done': _doneCount, 'total': _totalCount}),
                  style: const TextStyle(fontSize: 12, color: StarFilmColors.textSecondary),
                ),
              ],
              if (_result != null) ...[
                const SizedBox(height: 12),
                Text(
                  s.t('csv_import_done', {
                    'n': _result!.resolved.length,
                    'skip': _result!.skippedTitles.length,
                  }),
                  style: TextStyle(
                    fontSize: 13,
                    color: _result!.resolved.isNotEmpty
                        ? StarFilmColors.success
                        : StarFilmColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _importing ? null : () => Navigator.pop(context),
          child: Text(s.t('close')),
        ),
        FilledButton(
          onPressed: _importing ? null : _runImport,
          child: Text(s.t('csv_import_run')),
        ),
      ],
    );
  }
}
