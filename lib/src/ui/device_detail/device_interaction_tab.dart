import 'package:flutter/material.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:edown/src/ble/ble_device_connector.dart';
import 'package:edown/src/ble/ble_device_interactor.dart';
import 'package:functional_data/functional_data.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'package:image/image.dart' as img;
import 'package:edown/src/img/img.dart';
import 'characteristic_interaction_dialog.dart';
import 'package:edown/src/ble/write_image.dart';
import 'package:flutter/services.dart';

part 'device_interaction_tab.g.dart';

final Uuid SERVICE_UUID = Uuid.parse("4fafc201-1fb5-459e-8fcc-c5c9c331914b");
final Uuid CHARACTERISTIC_UUID =
    Uuid.parse("beb5483e-36e1-4688-b7f5-ea07361b26a8");

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

class _DeviceInteractionTabState extends State<_DeviceInteractionTab> {
  late List<Service> discoveredServices;

  late Uint8List monoBuffer;
  late Uint8List colorBuffer;

  String writeOutput = "Select file to send";

  Image? selectedImage = null;
  Image? ditheredImage = null;

  img.Image Function(img.Image) ditherFunction = noDither;

  static const List<img.Image Function(img.Image)> ditherFunctions = <img.Image
      Function(img.Image)>[
    noDither,
    ditherFloydSteinberg,
    ditherOrdered,
    ditherRiemersma
  ];

  static const Map<img.Image Function(img.Image), String>
      ditherFunctionsToAlgoNames = <img.Image Function(img.Image), String>{
    noDither: "No dither",
    ditherFloydSteinberg: "Floyd Steinberg",
    ditherOrdered: "Ordered",
    ditherRiemersma: "Riemersma"
  };

  @override
  void initState() {
    discoveredServices = [];
    widget.viewModel.connect();
    super.initState();
  }

  Future<void> discoverServices() async {
    final result = await widget.viewModel.discoverServices();
    setState(() {
      discoveredServices = result;
    });
  }

  Future<void> sendImage() async {
    FilePickerResult? pickerResult = await FilePicker.platform.pickFiles();

    while (!widget.viewModel.deviceConnected) {
      await Future.delayed(Duration(milliseconds: 100));
    }

    await discoverServices();

    final Service service = discoveredServices
        .where((service) => service.id == SERVICE_UUID)
        .single;

    final Characteristic characteristic = service.characteristics
        .where((characteristic) => characteristic.id == CHARACTERISTIC_UUID)
        .single;

    if (pickerResult != null && pickerResult.files.single.path != null) {
      setState(() {
        writeOutput = "Decoding image.";
      });

      img.Image image =
          (await img.decodeImageFile(pickerResult.files.single.path!))!;

      selectedImage = Image.memory(img.encodePng(image), fit: BoxFit.scaleDown);

      image = img.copyResize(image, width: 128);
      image = ditherFunction(image);

      ditheredImage = Image.memory(img.encodePng(image), fit: BoxFit.scaleDown);

      monoBuffer = Uint8List(image.height * (image.width / 8).ceil());
      colorBuffer = Uint8List(image.height * (image.width / 8).ceil());

      setState(() {
        writeOutput = "Converting image.";
      });
      convertImage(image.convert(format: img.Format.uint8, numChannels: 3),
          monoBuffer, colorBuffer);

      setState(() {
        writeOutput = "Sending image.";
      });
      await characteristic.write(utf8.encode("BEGIN"));

      await characteristic.write(utf8.encode("MONO BUFFER"));
      await writeInChunks(monoBuffer, 512, characteristic);

      await characteristic.write(utf8.encode("COLOR BUFFER"));
      await writeInChunks(colorBuffer, 512, characteristic);

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
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 16.0),
                  child: Wrap(
                    alignment: WrapAlignment.spaceEvenly,
                    children: <Widget>[
                      Text(
                        "Status: $writeOutput",
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: Wrap(
                    alignment: WrapAlignment.spaceEvenly,
                    children: <Widget>[
                      ElevatedButton(
                        onPressed: sendImage,
                        child: const Text("Send file"),
                      ),
                      DropdownButton<img.Image Function(img.Image)>(
                        value: ditherFunction,
                        icon: const Icon(Icons.arrow_downward),
                        elevation: 16,
                        style: const TextStyle(color: Colors.deepPurple),
                        underline: Container(
                          height: 2,
                          color: Colors.deepPurpleAccent,
                        ),
                        onChanged: (img.Image Function(img.Image)? value) {
                          // This is called when the user selects an item.
                          setState(() {
                            ditherFunction = value ?? noDither;
                          });
                        },
                        items: ditherFunctions.map<
                                DropdownMenuItem<
                                    img.Image Function(img.Image)>>(
                            (img.Image Function(img.Image) value) {
                          return DropdownMenuItem<
                              img.Image Function(img.Image)>(
                            value: value,
                            child:
                                Text(ditherFunctionsToAlgoNames[value] ?? ""),
                          );
                        }).toList(),
                      )
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 16.0),
                  child: Wrap(
                    alignment: WrapAlignment.spaceEvenly,
                    children: <Widget>[
                      if (selectedImage != null && ditheredImage != null) ...[
                        selectedImage!,
                        ditheredImage!,
                      ]
                    ],
                  ),
                ),
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
