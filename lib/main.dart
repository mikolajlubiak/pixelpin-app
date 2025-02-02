import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:edown/src/ble/ble_device_connector.dart';
import 'package:edown/src/ble/ble_device_interactor.dart';
import 'package:edown/src/ble/ble_scanner.dart';
import 'package:edown/src/ble/ble_status_monitor.dart';
import 'package:edown/src/ui/ble_status_screen.dart';
import 'package:edown/src/ui/device_list.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'src/ble/ble_logger.dart';

const _themeColor = Colors.lightGreen;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await requestPermissions();

  final _ble = FlutterReactiveBle();
  final _bleLogger = BleLogger(ble: _ble);
  final _scanner = BleScanner(ble: _ble, logMessage: _bleLogger.addToLog);
  final _monitor = BleStatusMonitor(_ble);
  final _connector = BleDeviceConnector(
    ble: _ble,
    logMessage: _bleLogger.addToLog,
  );
  final _serviceDiscoverer = BleDeviceInteractor(
    bleDiscoverServices: (deviceId) async {
      await _ble.discoverAllServices(deviceId);
      return _ble.getDiscoveredServices(deviceId);
    },
    logMessage: _bleLogger.addToLog,
    readRssi: _ble.readRssi,
  );
  runApp(
    MultiProvider(
      providers: [
        Provider.value(value: _scanner),
        Provider.value(value: _monitor),
        Provider.value(value: _connector),
        Provider.value(value: _serviceDiscoverer),
        Provider.value(value: _bleLogger),
        StreamProvider<BleScannerState?>(
          create: (_) => _scanner.state,
          initialData: const BleScannerState(
            discoveredDevices: [],
            scanIsInProgress: false,
          ),
        ),
        StreamProvider<BleStatus?>(
          create: (_) => _monitor.state,
          initialData: BleStatus.unknown,
        ),
        StreamProvider<ConnectionStateUpdate>(
          create: (_) => _connector.state,
          initialData: const ConnectionStateUpdate(
            deviceId: 'Unknown device',
            connectionState: DeviceConnectionState.disconnected,
            failure: null,
          ),
        ),
      ],
      child: MaterialApp(
        title: 'EDown',
        color: _themeColor,
        theme: ThemeData(primarySwatch: _themeColor),
        home: const HomeScreen(),
      ),
    ),
  );
}

Future<void> requestPermissions() async {
  await Permission.location.request();
  await Permission.bluetooth.request();
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) => Consumer<BleStatus?>(
        builder: (_, status, __) {
          if (status == BleStatus.ready) {
            return const DeviceListScreen();
          } else {
            return BleStatusScreen(status: status ?? BleStatus.unknown);
          }
        },
      );
}
