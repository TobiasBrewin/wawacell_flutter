import 'dart:async';

import 'package:flutter/material.dart';
import 'package:universal_ble/universal_ble.dart';

const _pickerBackgroundColor = Color(0xFF111720);
const _pickerBorderColor = Color(0xFF283443);
const _pickerTextColor = Color(0xFFE6EDF5);
const _pickerMutedColor = Color(0xFF8290A2);
const _pickerAccentColor = Color(0xFF35BFF2);

class BleDevicePickerDialog extends StatefulWidget {
  const BleDevicePickerDialog({
    required this.devices,
    required this.initialDevices,
    super.key,
  });

  final Stream<BleDevice> devices;
  final List<BleDevice> initialDevices;

  @override
  State<BleDevicePickerDialog> createState() => _BleDevicePickerDialogState();
}

class _BleDevicePickerDialogState extends State<BleDevicePickerDialog> {
  late final StreamSubscription<BleDevice> _subscription;
  final Map<String, BleDevice> _devices = {};
  Object? _scanError;

  @override
  void initState() {
    super.initState();
    for (final device in widget.initialDevices) {
      _devices[device.deviceId] = device;
    }
    _subscription = widget.devices.listen(
      (device) {
        if (!mounted) return;
        setState(() => _devices[device.deviceId] = device);
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() => _scanError = error);
      },
    );
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final devices = _devices.values.toList(growable: false);
    return AlertDialog(
      backgroundColor: _pickerBackgroundColor,
      title: const Text(
        'CONNECT TO DEVICE',
        style: TextStyle(
          color: _pickerTextColor,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
        ),
      ),
      content: SizedBox(
        width: 360,
        height: 280,
        child: _scanError != null
            ? Center(
                child: Text(
                  'Bluetooth scan failed: $_scanError',
                  style: const TextStyle(color: _pickerTextColor),
                ),
              )
            : devices.isEmpty
            ? const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: _pickerAccentColor),
                  SizedBox(height: 16),
                  Text(
                    'Searching for WawaCell...',
                    style: TextStyle(color: _pickerMutedColor),
                  ),
                ],
              )
            : ListView.separated(
                itemCount: devices.length,
                separatorBuilder: (_, _) =>
                    const Divider(color: _pickerBorderColor, height: 1),
                itemBuilder: (context, index) {
                  final device = devices[index];
                  final name = device.name?.isNotEmpty == true
                      ? device.name!
                      : 'Bluetooth device';
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.bluetooth,
                      color: _pickerAccentColor,
                    ),
                    title: Text(
                      name,
                      style: const TextStyle(color: _pickerTextColor),
                    ),
                    subtitle: device.rssi == null
                        ? null
                        : Text(
                            '${device.rssi} dBm',
                            style: const TextStyle(color: _pickerMutedColor),
                          ),
                    onTap: () => Navigator.of(context).pop(device),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'CANCEL',
            style: TextStyle(color: _pickerAccentColor),
          ),
        ),
      ],
    );
  }
}
