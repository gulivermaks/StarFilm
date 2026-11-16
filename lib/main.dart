import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app_state.dart';
import 'app/theme.dart';
import 'features/discovery/discovery_tab.dart';
import 'features/library/library_tab.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/search/search_tab.dart';
import 'features/settings/settings_screen.dart';
import 'features/startv/startv_pairing_dialog.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    ),
  );
  runApp(const ProviderScope(child: StarFilmApp()));
}

class StarFilmApp extends ConsumerWidget {
  const StarFilmApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    return MaterialApp(
      title: 'StarFilm',
      debugShowCheckedModeBanner: false,
      theme: buildStarFilmTheme(),
      locale: Locale(state.uiLanguage),
      supportedLocales: const [
        Locale('uk'),
        Locale('ru'),
        Locale('en'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: !state.initialized
          ? const Scaffold(
              body: Center(child: CircularProgressIndicator(color: StarFilmColors.lime)),
            )
          : (state.onboardingCompleted ? const HomeShell() : const OnboardingScreen()),
    );
  }
}

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> with WidgetsBindingObserver {
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(appControllerProvider.notifier).onAppResumed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final s = state.strings;
    final activeTv = state.activeTv;

    ref.listen<AppControllerState>(appControllerProvider, (prev, next) {
      if ((prev?.recentDigitalReleases.isEmpty ?? true) &&
          next.recentDigitalReleases.isNotEmpty) {
        final titles =
            next.recentDigitalReleases.map((m) => m.entry.title).take(3).join(', ');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.t('release_found_banner', {'titles': titles}))),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            const Text('StarFilm', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(width: 10),
            Flexible(
              child: PopupMenuButton<String>(
              onSelected: (id) {
                if (id == '_guest_toggle') {
                  ref
                      .read(appControllerProvider.notifier)
                      .toggleGuestEvening(!state.guestEvening);
                } else {
                  ref.read(appControllerProvider.notifier).switchProfile(id);
                }
              },
              itemBuilder: (_) => [
                for (final p in state.profiles)
                  PopupMenuItem<String>(
                    value: p.id,
                    child: Row(
                      children: [
                        Icon(
                          p.id == state.activeProfileId
                              ? Icons.check
                              : Icons.person_outline,
                          size: 18,
                          color: StarFilmColors.lime,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            state.displayProfileName(p),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                const PopupMenuDivider(),
                PopupMenuItem<String>(
                  value: '_guest_toggle',
                  child: Row(
                    children: [
                      Icon(
                        state.guestEvening ? Icons.check_box : Icons.check_box_outline_blank,
                        size: 18,
                        color: StarFilmColors.lime,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          s.t('guest_evening'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: state.guestEvening
                      ? StarFilmColors.lime
                      : StarFilmColors.surfaceElevated,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: StarFilmColors.border),
                ),
                child: Text(
                  state.guestEvening
                      ? s.t('guest_evening_short')
                      : state.displayProfileName(state.activeProfile),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: state.guestEvening
                        ? StarFilmColors.onLime
                        : StarFilmColors.textPrimary,
                  ),
                ),
              ),
            ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: s.t('startv_section'),
            icon: Icon(
              Icons.tv,
              color: activeTv != null ? StarFilmColors.lime : StarFilmColors.textSecondary,
            ),
            onPressed: () => StarTvPairingDialog.show(context),
          ),
          IconButton(
            tooltip: s.t('settings'),
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tabIndex,
        children: const [
          DiscoveryTab(),
          SearchTab(),
          LibraryTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (idx) => setState(() => _tabIndex = idx),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.auto_awesome_outlined),
            selectedIcon: const Icon(Icons.auto_awesome),
            label: s.t('tab_pick'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.search),
            selectedIcon: const Icon(Icons.search),
            label: s.t('tab_search'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.bookmarks_outlined),
            selectedIcon: const Icon(Icons.bookmarks),
            label: s.t('tab_library'),
          ),
        ],
      ),
    );
  }
}
