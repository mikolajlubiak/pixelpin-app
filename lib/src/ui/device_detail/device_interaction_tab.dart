import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:edown/src/ble/ble_device_connector.dart';
import 'package:edown/src/ble/ble_device_interactor.dart';
import 'package:functional_data/functional_data.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:typed_data';
import 'dart:convert';
import 'package:image/image.dart' as img;

import 'characteristic_interaction_dialog.dart';

part 'device_interaction_tab.g.dart';

// ignore_for_file: annotate_overrides

class DeviceInteractionTab extends StatelessWidget {
  const DeviceInteractionTab({
    required this.device,
    Key? key,
  }) : super(key: key);

  final DiscoveredDevice device;

  @override
  Widget build(BuildContext context) =>
      Consumer3<BleDeviceConnector, ConnectionStateUpdate, BleDeviceInteractor>(
        builder: (_, deviceConnector, connectionStateUpdate, serviceDiscoverer,
                __) =>
            _DeviceInteractionTab(
          viewModel: DeviceInteractionViewModel(
            deviceId: device.id,
            connectableStatus: device.connectable,
            connectionStatus: connectionStateUpdate.connectionState,
            deviceConnector: deviceConnector,
            discoverServices: () =>
                serviceDiscoverer.discoverServices(device.id),
            readRssi: () => serviceDiscoverer.readRssi(device.id),
          ),
        ),
      );
}

@immutable
@FunctionalData()
class DeviceInteractionViewModel extends $DeviceInteractionViewModel {
  const DeviceInteractionViewModel({
    required this.deviceId,
    required this.connectableStatus,
    required this.connectionStatus,
    required this.deviceConnector,
    required this.discoverServices,
    required this.readRssi,
  });

  final String deviceId;
  final Connectable connectableStatus;
  final DeviceConnectionState connectionStatus;
  final BleDeviceConnector deviceConnector;
  final Future<int> Function() readRssi;

  @CustomEquality(Ignore())
  final Future<List<Service>> Function() discoverServices;

  bool get deviceConnected =>
      connectionStatus == DeviceConnectionState.connected;

  void connect() {
    deviceConnector.connect(deviceId);
  }

  void disconnect() {
    deviceConnector.disconnect(deviceId);
  }
}

class _DeviceInteractionTab extends StatefulWidget {
  const _DeviceInteractionTab({
    required this.viewModel,
    Key? key,
  }) : super(key: key);

  final DeviceInteractionViewModel viewModel;

  @override
  _DeviceInteractionTabState createState() => _DeviceInteractionTabState();
}

// for up to 7.8" display 1872x1404
// int MAX_ROW = 1872;
// int MAX_COL = 1404;
int MAX_ROW = (296).toInt();
int MAX_COL = (128 / 8).toInt();
int BUFFER_SIZE = MAX_ROW * MAX_COL;

class _DeviceInteractionTabState extends State<_DeviceInteractionTab> {
  late List<Service> discoveredServices;

  int _rssi = 0;
  String writeOutput = "Select file to send";

  Uint8List monoBuffer = Uint8List(BUFFER_SIZE);
  Uint8List colorBuffer = Uint8List(BUFFER_SIZE);

  @override
  void initState() {
    discoveredServices = [];
    super.initState();
  }

  Future<void> discoverServices() async {
    final result = await widget.viewModel.discoverServices();
    setState(() {
      discoveredServices = result;
    });
  }

  Future<void> readRssi() async {
    final rssi = await widget.viewModel.readRssi();
    setState(() {
      _rssi = rssi;
    });
  }

  void writeInChunks(
      Uint8List data, int chunkSize, Characteristic characteristic) {
    for (int i = 0; i < data.length; i += chunkSize) {
      // Calculate the end index for the chunk
      int end = (i + chunkSize < data.length) ? i + chunkSize : data.length;

      // Get the chunk
      Uint8List chunk = data.sublist(i, end);

      // Process the chunk
      characteristic.write(chunk);
    }
  }

  void convertImage(img.Image image) {
    int width = image.width;
    int height = image.height;

    Uint8List rgbBytes = image.getBytes(order: img.ChannelOrder.rgb);

    int red, green, blue;
    bool whitish = false;
    bool colored = false;
    bool with_color = true;
    int out_byte = 0xFF; // white (for w%8!=0 border)
    int out_color_byte = 0xFF; // white (for w%8!=0 border)
    int out_col_idx = 0;

    for (int row = 0; row < height; row++) {
      out_col_idx = 0;
      for (int col = 0; col < width; col++) {
        int index = (row * width + col) * 3;
        red = rgbBytes[index];
        green = rgbBytes[index + 1];
        blue = rgbBytes[index + 2];

        whitish =
            (red * 0.299 + green * 0.587 + blue * 0.114) > 0x80; // whitish

        colored = ((red > 0x80) &&
                (((red > green + 0x40) && (red > blue + 0x40)) ||
                    (red + 0x10 > green + blue))) ||
            (green > 0xC8 &&
                red > 0xC8 &&
                blue < 0x40); // reddish or yellowish?

        if (whitish) {
          // keep white
        } else if (colored && with_color) {
          out_color_byte &= ~(0x80 >> col % 8); // colored
        } else {
          out_byte &= ~(0x80 >> col % 8); // black
        }
        if ((7 == col % 8) ||
            (col == width - 1)) // write that last byte! (for w%8!=0 border)
        {
          monoBuffer[row * MAX_COL + out_col_idx] = out_byte;
          colorBuffer[row * MAX_COL + out_col_idx] = out_color_byte;
          out_col_idx++;
          out_byte = 0xFF; // white (for w%8!=0 border)
          out_color_byte = 0xFF; // white (for w%8!=0 border)
        }
      }
    }
  }

  Future<void> sendFile() async {
    if (!widget.viewModel.deviceConnected) {
      widget.viewModel.connect();
    }

    while (!widget.viewModel.deviceConnected) {
      await Future.delayed(Duration(seconds: 1));
    }

    await discoverServices();

    final Service service = discoveredServices
        .where((service) =>
            service.id == Uuid.parse("4fafc201-1fb5-459e-8fcc-c5c9c331914b"))
        .single;

    final Characteristic characteristic = service.characteristics
        .where((characteristic) =>
            characteristic.id ==
            Uuid.parse("beb5483e-36e1-4688-b7f5-ea07361b26a8"))
        .single;

    FilePickerResult? result = await FilePicker.platform.pickFiles();

    if (result != null && result.files.single.path != null) {
      setState(() {
        writeOutput = "Decoding image.";
      });
      img.Image image = img.copyResize(
          (await img.decodeImageFile(result.files.single.path!))!,
          width: 128);

      setState(() {
        writeOutput = "Converting image.";
      });
      convertImage(image);

      setState(() {
        writeOutput = "Sending image.";
      });
      await characteristic.write(utf8.encode("BEGIN"));

      await characteristic.write(utf8.encode("MONO BUFFER"));
      writeInChunks(monoBuffer, 16, characteristic);

      await characteristic.write(utf8.encode("COLOR BUFFER"));
      writeInChunks(colorBuffer, 16, characteristic);

      setState(() {
        writeOutput = "Image sent.";
      });
    } else {
      setState(() {
        writeOutput = "No file selected";
      });
    }

    await characteristic.write(utf8.encode("END"));
    await characteristic.write(utf8.encode("DRAW"));

    setState(() {
      writeOutput = "Image drawn";
    });
  }

  @override
  Widget build(BuildContext context) => CustomScrollView(
        slivers: [
          SliverList(
            delegate: SliverChildListDelegate.fixed(
              [
                /*
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                      top: 8.0, bottom: 16.0, start: 16.0),
                  child: Text(
                    "ID: ${widget.viewModel.deviceId}",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 16.0),
                  child: Text(
                    "Connectable: ${widget.viewModel.connectableStatus}",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 16.0),
                  child: Text(
                    "Connection: ${widget.viewModel.connectionStatus}",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 16.0),
                  child: Text(
                    "Rssi: $_rssi dB",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                */
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 16.0),
                  child: Text(
                    "Status: $writeOutput",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: Wrap(
                    alignment: WrapAlignment.spaceEvenly,
                    children: <Widget>[
                      /*
                      ElevatedButton(
                        onPressed: !widget.viewModel.deviceConnected
                            ? widget.viewModel.connect
                            : null,
                        child: const Text("Connect"),
                      ),
                      ElevatedButton(
                        onPressed: widget.viewModel.deviceConnected
                            ? widget.viewModel.disconnect
                            : null,
                        child: const Text("Disconnect"),
                      ),
                      ElevatedButton(
                        onPressed: widget.viewModel.deviceConnected
                            ? discoverServices
                            : null,
                        child: const Text("Discover Services"),
                      ),
                      ElevatedButton(
                        onPressed:
                            widget.viewModel.deviceConnected ? readRssi : null,
                        child: const Text("Get RSSI"),
                      ),
                      */
                      ElevatedButton(
                        onPressed: sendFile,
                        child: const Text("Send file"),
                      ),
                    ],
                  ),
                ),
                /*
                if (widget.viewModel.deviceConnected)
                  _ServiceDiscoveryList(
                    deviceId: widget.viewModel.deviceId,
                    discoveredServices: discoveredServices,
                  ),
                  */
              ],
            ),
          ),
        ],
      );
}

class _ServiceDiscoveryList extends StatefulWidget {
  const _ServiceDiscoveryList({
    required this.deviceId,
    required this.discoveredServices,
    Key? key,
  }) : super(key: key);

  final String deviceId;
  final List<Service> discoveredServices;

  @override
  _ServiceDiscoveryListState createState() => _ServiceDiscoveryListState();
}

class _ServiceDiscoveryListState extends State<_ServiceDiscoveryList> {
  late final List<int> _expandedItems;

  @override
  void initState() {
    _expandedItems = [];
    super.initState();
  }

  String _characteristicSummary(Characteristic c) {
    final props = <String>[];
    if (c.isReadable) {
      props.add("read");
    }
    if (c.isWritableWithoutResponse) {
      props.add("write without response");
    }
    if (c.isWritableWithResponse) {
      props.add("write with response");
    }
    if (c.isNotifiable) {
      props.add("notify");
    }
    if (c.isIndicatable) {
      props.add("indicate");
    }

    return props.join("\n");
  }

  Widget _characteristicTile(Characteristic characteristic) => ListTile(
        onTap: () => showDialog<void>(
          context: context,
          builder: (context) =>
              CharacteristicInteractionDialog(characteristic: characteristic),
        ),
        title: Text(
          '${characteristic.id}\n(${_characteristicSummary(characteristic)})',
          style: const TextStyle(
            fontSize: 14,
          ),
        ),
      );

  List<ExpansionPanel> buildPanels() {
    final panels = <ExpansionPanel>[];

    widget.discoveredServices.asMap().forEach(
          (index, service) => panels.add(
            ExpansionPanel(
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsetsDirectional.only(start: 16.0),
                    child: Text(
                      'Characteristics',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: service.characteristics
                        .map(_characteristicTile)
                        .toList(),
                  ),
                ],
              ),
              headerBuilder: (context, isExpanded) => ListTile(
                title: Text(
                  '${service.id}',
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              isExpanded: _expandedItems.contains(index),
            ),
          ),
        );

    return panels;
  }

  @override
  Widget build(BuildContext context) => widget.discoveredServices.isEmpty
      ? const SizedBox()
      : SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsetsDirectional.only(
              top: 20.0,
              start: 20.0,
              end: 20.0,
            ),
            child: ExpansionPanelList(
              expansionCallback: (int index, bool isExpanded) {
                setState(() {
                  if (!isExpanded) {
                    _expandedItems.remove(index);
                  } else {
                    _expandedItems.add(index);
                  }
                });
              },
              children: buildPanels(),
            ),
          ),
        );
}
