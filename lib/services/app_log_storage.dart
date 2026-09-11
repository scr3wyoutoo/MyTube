import 'app_log_storage_base.dart';
import 'app_log_storage_stub.dart'
    if (dart.library.io) 'app_log_storage_io.dart'
    as backend;

Future<AppLogStorage> createAppLogStorage() => backend.createAppLogStorage();
