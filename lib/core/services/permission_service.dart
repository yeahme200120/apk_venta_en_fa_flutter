import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  Future<bool> requestStartupPermissions() async {
    final statuses = await [Permission.location].request();
    return statuses[Permission.location]?.isGranted ?? false;
  }

  Future<bool> requestBluetoothPermissions() async {
    final statuses = await [Permission.bluetoothScan, Permission.bluetoothConnect].request();
    return statuses.values.every((status) => status.isGranted);
  }
}
