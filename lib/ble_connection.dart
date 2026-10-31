import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

typedef BleDevicePicker = Future<BleDevice?> Function(
  Stream<BleDevice> devices,
  List<BleDevice> initialDevices,
);

class BleConnection {
  BleConnection({
    required this.onStatusChanged,
    required this.onConnected,
    required this.onDisconnected,
    required this.onMeasurement,
    required this.onError,
    required this.onSelectDevice,
  });

  static const serviceUuid = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
  static const characteristicUuid = 'beb5483e-36e1-4688-b7f5-ea07361b26a8';

  final ValueChanged<String> onStatusChanged;
  final VoidCallback onConnected;
  final VoidCallback onDisconnected;
  final ValueChanged<double> onMeasurement;
  final ValueChanged<Object> onError;
  final BleDevicePicker onSelectDevice;

  StreamSubscription<BleDevice>? _scanSubscription;
  StreamSubscription<bool>? _connectionSubscription;
  StreamSubscription<Uint8List>? _valueSubscription;
  final StreamController<BleDevice> _discoveredDevices =
      StreamController<BleDevice>.broadcast();
  final Map<String, BleDevice> _devicesById = {};
  String? _deviceId;
  bool _isConnecting = false;
  bool _isSelectingDevice = false;
  bool _manualDisconnect = false;

  Future<void> connect() async {
    if (_isConnecting || _deviceId != null) return;
    _isConnecting = true;

    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
        await UniversalBle.requestPermissions();
        _devicesById.clear();
        _isSelectingDevice = true;
        _scanSubscription ??= UniversalBle.scanStream.listen(
          _onScanResult,
          onError: (Object error) => _fail(error),
        );
        await UniversalBle.startScan(
          scanFilter: ScanFilter(withServices: [serviceUuid]),
          skipDuplicates: true,
        );
        final device = await onSelectDevice(
          _discoveredDevices.stream,
          List.unmodifiable(_devicesById.values),
        );
        _isSelectingDevice = false;
        await _stopScan();
        if (device == null) {
          _isConnecting = false;
          onDisconnected();
          return;
        }
        await _connectToDevice(device.deviceId);
        return;
      }

      if (!kIsWeb) {
        await UniversalBle.requestPermissions();
      }
      _scanSubscription ??= UniversalBle.scanStream.listen(
        _onScanResult,
        onError: (Object error) => _fail(error),
      );
      await UniversalBle.startScan(
        scanFilter: ScanFilter(withServices: [serviceUuid]),
        skipDuplicates: true,
      );
    } on Object catch (error) {
      _isSelectingDevice = false;
      _isConnecting = false;
      await _stopScan();
      onDisconnected();
      onError(error);
    }
  }

  void _onScanResult(BleDevice device) {
    if (!_isConnecting) return;
    if (_isSelectingDevice) {
      _devicesById[device.deviceId] = device;
      _discoveredDevices.add(device);
      return;
    }
    if (_deviceId != null) return;
    unawaited(_connectToDevice(device.deviceId));
  }

  Future<void> _connectToDevice(String deviceId) async {
    _deviceId = deviceId;
    onStatusChanged('Connecting...');
    await _stopScan();

    var linkEstablished = false;
    _connectionSubscription = UniversalBle.connectionStream(deviceId)
        .listen((isConnected) {
          if (isConnected) {
            linkEstablished = true;
          } else if (linkEstablished && !_manualDisconnect) {
            unawaited(_handleUnexpectedDisconnect(deviceId));
          }
        }, onError: (Object error) => _fail(error));

    try {
      await UniversalBle.connect(
        deviceId,
        timeout: const Duration(seconds: 20),
      );
      linkEstablished = true;
      await UniversalBle.discoverServices(deviceId);
      _valueSubscription = UniversalBle.characteristicValueStream(
        deviceId,
        characteristicUuid,
      ).listen(_handleValue, onError: (Object error) => _fail(error));
      await UniversalBle.subscribeNotifications(
        deviceId,
        serviceUuid,
        characteristicUuid,
      );
      _isConnecting = false;
      onConnected();
    } on Object catch (error) {
      await _failConnection(deviceId, error);
    }
  }

  void _handleValue(Uint8List value) {
    try {
      onMeasurement(decodeLoadCellMeasurement(value));
    } on FormatException catch (error) {
      onError(error);
    }
  }

  Future<void> _handleUnexpectedDisconnect(String deviceId) async {
    if (_deviceId != deviceId) return;
    await _cancelDeviceSubscriptions();
    _deviceId = null;
    _isConnecting = false;
    onDisconnected();
  }

  Future<void> _fail(Object error) async {
    final deviceId = _deviceId;
    if (deviceId == null) {
      _isConnecting = false;
      if (_isSelectingDevice) {
        _discoveredDevices.addError(error);
        _isSelectingDevice = false;
      }
      await _stopScan();
      onDisconnected();
      onError(error);
      return;
    }
    await _failConnection(deviceId, error);
  }

  Future<void> _failConnection(String deviceId, Object error) async {
    _isConnecting = false;
    _manualDisconnect = true;
    _isSelectingDevice = false;
    await _stopScan();
    try {
      await UniversalBle.disconnect(deviceId);
    } on Object catch (cleanupError) {
      debugPrint('BLE cleanup after connection failure failed: $cleanupError');
    }
    await _cancelDeviceSubscriptions();
    _deviceId = null;
    _manualDisconnect = false;
    onDisconnected();
    onError(error);
  }

  Future<void> disconnect() async {
    final deviceId = _deviceId;
    _manualDisconnect = true;
    await _stopScan();
    Object? unsubscribeError;
    Object? disconnectError;
    if (deviceId != null) {
      try {
        await UniversalBle.unsubscribe(
          deviceId,
          serviceUuid,
          characteristicUuid,
        );
      } on Object catch (error) {
        unsubscribeError = error;
      }
      try {
        await UniversalBle.disconnect(deviceId);
      } on Object catch (error) {
        disconnectError = error;
      }
    }

    await _cancelDeviceSubscriptions();
    _deviceId = null;
    _isConnecting = false;
    _manualDisconnect = false;
    onDisconnected();

    if (disconnectError != null) {
      throw StateError(
        'Could not disconnect from the load cell: $disconnectError',
      );
    }
    if (unsubscribeError != null) {
      throw StateError(
        'Disconnected, but could not stop notifications cleanly: $unsubscribeError',
      );
    }
  }

  Future<void> _stopScan() async {
    try {
      await UniversalBle.stopScan();
    } on Object catch (error) {
      debugPrint('Could not stop BLE scan: $error');
    }
  }

  Future<void> _cancelDeviceSubscriptions() async {
    await _connectionSubscription?.cancel();
    await _valueSubscription?.cancel();
    _connectionSubscription = null;
    _valueSubscription = null;
  }

  Future<void> dispose() async {
    await _stopScan();
    final deviceId = _deviceId;
    if (deviceId != null) {
      try {
        await UniversalBle.unsubscribe(
          deviceId,
          serviceUuid,
          characteristicUuid,
        );
      } on Object catch (error) {
        debugPrint('Could not stop BLE notifications during shutdown: $error');
      }
      try {
        await UniversalBle.disconnect(deviceId);
      } on Object catch (error) {
        debugPrint('Could not disconnect BLE device during shutdown: $error');
      }
    }
    await _scanSubscription?.cancel();
    await _cancelDeviceSubscriptions();
    await _discoveredDevices.close();
  }
}

double decodeLoadCellMeasurement(Uint8List value) {
  if (value.length < 4) {
    throw FormatException(
      'Load cell sent ${value.length} bytes; expected at least 4.',
    );
  }
  return ByteData.sublistView(value).getFloat32(0, Endian.little);
}
