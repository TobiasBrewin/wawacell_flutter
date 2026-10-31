# WawaCell

Flutter recreation of the WawaCell control panel for Android, iOS, and Web.

## Run

```shell
flutter pub get
flutter run
```

The app connects to the load cell using the existing service and characteristic
UUIDs and decodes each notification as a little-endian 32-bit float.

Web Bluetooth requires a supported browser (for example, Chrome or Edge) and a
secure context such as HTTPS or localhost. Browser Bluetooth support and
permissions vary; iOS Safari does not provide Web Bluetooth.

To test with the physical load cell, power on the WawaCell device, allow the
requested Bluetooth permissions, and tap **CONNECT**. The device must be
advertising the existing WawaCell service.
