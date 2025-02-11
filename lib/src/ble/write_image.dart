import 'dart:typed_data';
import 'dart:math';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

Future<void> writeInChunks(
    Uint8List data, int chunkSize, Characteristic characteristic) async {
  for (int i = 0; i < data.length; i += chunkSize) {
    // Calculate the end index for the chunk
    int end = min(i + chunkSize, data.length);

    // Get the chunk
    Uint8List chunk = data.sublist(i, end);

    // Process the chunk
    await characteristic.write(chunk);
  }
}
