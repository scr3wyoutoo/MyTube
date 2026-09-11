import 'dart:async';

import 'package:flutter/widgets.dart';

import '../services/app_log.dart';

class AppLogLifecycleScope extends StatefulWidget {
  const AppLogLifecycleScope({super.key, required this.child});

  final Widget child;

  @override
  State<AppLogLifecycleScope> createState() => _AppLogLifecycleScopeState();
}

class _AppLogLifecycleScopeState extends State<AppLogLifecycleScope>
    with WidgetsBindingObserver {
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
    AppLog.instance.info(
      'app.lifecycle.changed',
      fields: <String, Object?>{'state': state.name},
    );
    if (state != AppLifecycleState.resumed) {
      unawaited(AppLog.instance.flush());
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
