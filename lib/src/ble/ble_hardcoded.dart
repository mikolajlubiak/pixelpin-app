import 'package:reactive_ble_platform_interface/src/model/uuid.dart';

enum DeviceType { TFT, EPD }

final Uuid SERVICE_UUID = Uuid.parse("3c9a8264-7d7e-41d3-963f-798e23f8b28f");
final Uuid CHARACTERISTIC_UUID =
    Uuid.parse("59dee772-cb42-417b-82fe-3542909614bb");

final BLE_MTU = 512;

final DEVICE_TYPE = DeviceType.TFT;
