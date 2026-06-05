import 'package:keqdroid/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<StorageService> buildStorageService({
  Map<String, Object> initialValues = const {},
}) async {
  SharedPreferences.setMockInitialValues(initialValues);
  final prefs = await SharedPreferences.getInstance();
  return StorageService(prefs);
}

