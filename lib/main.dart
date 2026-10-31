import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'wawa_cell_app.dart';

export 'wawa_cell_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(
    const [DeviceOrientation.portraitUp],
  );
  runApp(const WawaCellApp());
}
