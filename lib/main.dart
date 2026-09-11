import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:media_kit/media_kit.dart';

import 'l10n/app_localizations.dart';
import 'models/user_profile.dart';
import 'screens/youtube_search_page.dart';
import 'services/app_log.dart';
import 'services/profile_controller.dart';
import 'services/youtube_catalog_repository.dart';
import 'services/youtube_search_repository.dart';
import 'services/youtube_video_details_repository.dart';
import 'theme/mytube_theme.dart';
import 'widgets/mytube_startup_splash.dart';
import 'widgets/app_log_lifecycle_scope.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _installGlobalErrorLogging();
  AppLog.instance.info('app.bootstrap.started');
  unawaited(AppLog.instance.initialize());
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    runApp(const MyTubeAndroidBootstrap());
    return;
  }
  MediaKit.ensureInitialized();
  AppLog.instance.info(
    'app.media.initialized',
    fields: {'backend': 'mediaKit'},
  );
  final stopwatch = Stopwatch()..start();
  final profileController = await ProfileController.load();
  AppLog.instance.info(
    'profile.storage.loaded',
    fields: {
      'durationMs': stopwatch.elapsedMilliseconds,
      'profileCount': profileController.profiles.length,
      'hasActiveProfile': profileController.activeProfile != null,
    },
  );
  runApp(BrowserApp(profileController: profileController));
}

void _installGlobalErrorLogging() {
  final previousFlutterErrorHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    AppLog.instance.error(
      'app.flutter.error',
      error: details.exception,
      stackTrace: details.stack,
      fields: {'library': details.library},
    );
    if (previousFlutterErrorHandler != null) {
      previousFlutterErrorHandler(details);
    } else {
      FlutterError.presentError(details);
    }
  };
  final previousPlatformErrorHandler = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    AppLog.instance.error(
      'app.platform.error',
      error: error,
      stackTrace: stackTrace,
    );
    return previousPlatformErrorHandler?.call(error, stackTrace) ?? false;
  };
}

typedef MyTubeMediaInitializer = void Function();
typedef MyTubeProfileLoader = Future<ProfileController> Function();

class MyTubeAndroidBootstrap extends StatefulWidget {
  const MyTubeAndroidBootstrap({
    super.key,
    this.initializeMedia,
    this.loadProfile,
  });

  final MyTubeMediaInitializer? initializeMedia;
  final MyTubeProfileLoader? loadProfile;

  @override
  State<MyTubeAndroidBootstrap> createState() => _MyTubeAndroidBootstrapState();
}

class _MyTubeAndroidBootstrapState extends State<MyTubeAndroidBootstrap> {
  ProfileController? _profileController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  Future<void> _initialize() async {
    final stopwatch = Stopwatch()..start();
    try {
      (widget.initializeMedia ?? MediaKit.ensureInitialized)();
      AppLog.instance.info(
        'app.media.initialized',
        fields: {'backend': 'mediaKit'},
      );
    } on Object catch (error, stackTrace) {
      AppLog.instance.error(
        'app.media.initialization_failed',
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
    ProfileController profileController;
    try {
      profileController =
          await (widget.loadProfile ?? ProfileController.load)();
      AppLog.instance.info(
        'profile.storage.loaded',
        fields: {
          'durationMs': stopwatch.elapsedMilliseconds,
          'profileCount': profileController.profiles.length,
          'hasActiveProfile': profileController.activeProfile != null,
        },
      );
    } on Object catch (error, stackTrace) {
      AppLog.instance.error(
        'profile.storage.load_failed',
        error: error,
        stackTrace: stackTrace,
        fields: {'fallback': 'memory'},
      );
      profileController = ProfileController.inMemory();
    }
    if (!mounted) {
      profileController.dispose();
      return;
    }
    setState(() => _profileController = profileController);
  }

  @override
  void dispose() {
    _profileController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profileController = _profileController;
    if (profileController == null) {
      return MaterialApp(
        title: 'MyTube',
        debugShowCheckedModeBanner: false,
        theme: buildMyTubeTheme(),
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const MyTubeSplashArtwork(),
      );
    }
    return BrowserApp(
      profileController: profileController,
      showStartupSplash: true,
    );
  }
}

class BrowserApp extends StatelessWidget {
  const BrowserApp({
    super.key,
    this.searchRepository,
    this.musicSearchRepository,
    this.profileController,
    this.videoDetailsRepository,
    this.catalogRepository,
    this.showStartupSplash = false,
  });

  final YouTubeSearchRepository? searchRepository;
  final YouTubeSearchRepository? musicSearchRepository;
  final ProfileController? profileController;
  final YouTubeVideoDetailsRepository? videoDetailsRepository;
  final YouTubeCatalogRepository? catalogRepository;
  final bool showStartupSplash;

  @override
  Widget build(BuildContext context) {
    final controller = profileController;
    if (controller == null) {
      return _buildLocalizedApp(ProfileLanguage.english);
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => _buildLocalizedApp(
        controller.activeProfile?.language ?? ProfileLanguage.english,
      ),
    );
  }

  Widget _buildLocalizedApp(ProfileLanguage language) {
    final home = AppLogLifecycleScope(
      child: YouTubeSearchPage(
        searchRepository: searchRepository,
        musicSearchRepository: musicSearchRepository,
        profileController: profileController,
        videoDetailsRepository: videoDetailsRepository,
        catalogRepository: catalogRepository,
      ),
    );
    return MaterialApp(
      title: 'MyTube',
      debugShowCheckedModeBanner: false,
      theme: buildMyTubeTheme(),
      locale: Locale(language.code),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: showStartupSplash ? MyTubeStartupSplash(child: home) : home,
    );
  }
}
