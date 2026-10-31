import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:universal_ble/universal_ble.dart';

import 'ble_connection.dart';
import 'ble_device_picker_dialog.dart';
import 'force_format.dart';

const _backgroundColor = Color(0xFF080B10);
const _panelColor = Color(0xFF111720);
const _cardColor = Color(0xFF151E29);
const _borderColor = Color(0xFF283443);
const _buttonColor = Color(0xFF1B2735);
const _buttonBorderColor = Color(0xFF344357);
const _textColor = Color(0xFFE6EDF5);
const _mutedColor = Color(0xFF8290A2);
const _accentColor = Color(0xFF35BFF2);
const _inactiveDisplayColor = Color(0xFF1B232D);
const _accentTextGlow = Shadow(color: Color(0x6635BFF2), blurRadius: 2);
const _accentIconGlow = Shadow(color: Color(0x6635BFF2), blurRadius: 3);
const _forceTextGlow = Shadow(color: Color(0xAA35BFF2), blurRadius: 6);

class WawaCellApp extends StatelessWidget {
  const WawaCellApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WawaCell',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: false,
        scaffoldBackgroundColor: _backgroundColor,
        fontFamily: 'monospace',
        colorScheme: const ColorScheme.dark(
          primary: _accentColor,
          surface: _cardColor,
        ),
      ),
      home: const WawaCellPanel(),
    );
  }
}

class WawaCellPanel extends StatefulWidget {
  const WawaCellPanel({super.key});

  @override
  State<WawaCellPanel> createState() => _WawaCellPanelState();
}

class _WawaCellPanelState extends State<WawaCellPanel> {
  late final BleConnection _bleConnection;
  late final Timer _graphRefreshTimer;
  late final Timer _peakAgeTimer;
  late final TextEditingController _graphRangeController;
  late final TextEditingController _peakMaximumThresholdController;
  late final TextEditingController _peakMinimumThresholdController;
  final ValueNotifier<DateTime> _graphFrameTime = ValueNotifier(DateTime.now());

  String _connectionStatus = 'Disconnected';
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _hasConnected = false;
  bool _showRelativeForce = true;
  double _zeroForce = 0;
  double? _absoluteForce;
  double? _peakMaximumForce;
  double? _peakMinimumForce;
  DateTime? _peakMaximumTime;
  DateTime? _peakMinimumTime;
  bool _peakMaximumAlertEnabled = false;
  bool _peakMinimumAlertEnabled = false;
  double _peakMaximumThreshold = 0;
  double _peakMinimumThreshold = 0;
  final List<_ForceSample> _graphSamples = [];
  double _graphRangeSeconds = 10;
  bool _isRecording = false;
  bool _showAutoRecordSettings = false;

  String _timeFormat = '24-hour';
  String _dateFormat = 'dd.mm.yyyy';
  String _unit = 'kN';
  String _sampleRate = '100 Hz';

  @override
  void initState() {
    super.initState();
    _graphRangeController = TextEditingController(text: '10');
    _peakMaximumThresholdController = TextEditingController(text: '0');
    _peakMinimumThresholdController = TextEditingController(text: '0');
    _graphRefreshTimer = Timer.periodic(const Duration(milliseconds: 20), (_) {
      _graphFrameTime.value = DateTime.now();
    });
    _peakAgeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    _bleConnection = BleConnection(
      onStatusChanged: (status) {
        if (!mounted) return;
        setState(() {
          _connectionStatus = status == 'Scanning...'
              ? 'Connecting...'
              : status;
          _isConnecting = status == 'Scanning...' || status == 'Connecting...';
        });
      },
      onConnected: () {
        if (!mounted) return;
        setState(() {
          _isConnected = true;
          _isConnecting = false;
          _hasConnected = true;
          _zeroForce = 0;
          _absoluteForce = null;
          _peakMaximumForce = null;
          _peakMinimumForce = null;
          _peakMaximumTime = null;
          _peakMinimumTime = null;
          _graphSamples.clear();
          _connectionStatus = 'Connected';
        });
      },
      onDisconnected: () {
        if (!mounted) return;
        setState(() {
          _isConnected = false;
          _isConnecting = false;
          _connectionStatus = 'Disconnected';
        });
      },
      onMeasurement: (force) {
        if (!mounted) return;
        setState(() {
          _absoluteForce = force;
          if (!force.isFinite) return;
          final timestamp = DateTime.now();
          _graphSamples.add(_ForceSample(timestamp, force));
          final oldestSample = timestamp.subtract(const Duration(seconds: 60));
          _graphSamples.removeWhere(
            (sample) => sample.timestamp.isBefore(oldestSample),
          );
          if (_peakMaximumForce == null || force > _peakMaximumForce!) {
            _peakMaximumForce = force;
            _peakMaximumTime = timestamp;
          }
          if (_peakMinimumForce == null || force < _peakMinimumForce!) {
            _peakMinimumForce = force;
            _peakMinimumTime = timestamp;
          }
        });
      },
      onError: _showBleError,
      onSelectDevice: (devices, initialDevices) => showDialog<BleDevice>(
        context: context,
        builder: (context) => BleDevicePickerDialog(
          devices: devices,
          initialDevices: initialDevices,
        ),
      ),
    );
  }

  void _showBleError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Bluetooth error: $error'),
          backgroundColor: const Color(0xFF6D2020),
        ),
      );
  }

  Future<void> _toggleConnection() async {
    if (_isConnecting) return;
    if (_isConnected) {
      try {
        await _bleConnection.disconnect();
      } catch (error) {
        _showBleError(error);
      }
      return;
    }

    setState(() {
      _isConnecting = true;
      _connectionStatus = 'Scanning...';
    });
    await _bleConnection.connect();
  }

  void _setZero() {
    final force = _absoluteForce;
    if (force == null) return;
    setState(() => _zeroForce = force);
  }

  void _removeZero() {
    setState(() => _zeroForce = 0);
  }

  void _resetPeak({required bool maximum}) {
    setState(() {
      if (maximum) {
        _peakMaximumForce = null;
        _peakMaximumTime = null;
      } else {
        _peakMinimumForce = null;
        _peakMinimumTime = null;
      }
    });
  }

  void _setPeakThreshold({
    required bool maximum,
    required double value,
    bool updateController = true,
  }) {
    final threshold = value.clamp(0, 1000).toDouble();
    final controller = maximum
        ? _peakMaximumThresholdController
        : _peakMinimumThresholdController;
    setState(() {
      if (maximum) {
        _peakMaximumThreshold = threshold;
      } else {
        _peakMinimumThreshold = threshold;
      }
      if (updateController) {
        final text = threshold == threshold.roundToDouble()
            ? threshold.toInt().toString()
            : threshold.toStringAsFixed(2);
        controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
    });
  }

  String _elapsedSince(DateTime? timestamp) {
    if (timestamp == null) return 'NO PEAK';
    final elapsed = DateTime.now().difference(timestamp);
    if (elapsed.inDays > 0) return '${elapsed.inDays}d ago';
    if (elapsed.inHours > 0) return '${elapsed.inHours}h ago';
    if (elapsed.inMinutes > 0) return '${elapsed.inMinutes}m ago';
    return '${elapsed.inSeconds}s ago';
  }

  void _cycleUnit() {
    const units = ['kN', 'kg', 'Lb'];
    setState(() {
      _unit = units[(units.indexOf(_unit) + 1) % units.length];
    });
  }

  void _setGraphRange(double seconds) {
    final clampedSeconds = seconds.round().clamp(1, 60);
    setState(() {
      _graphRangeSeconds = clampedSeconds.toDouble();
      _graphRangeController.value = TextEditingValue(
        text: clampedSeconds.toString(),
        selection: TextSelection.collapsed(
          offset: clampedSeconds.toString().length,
        ),
      );
    });
  }

  void _submitGraphRange(String value) {
    final seconds = int.tryParse(value);
    if (seconds == null || seconds < 1 || seconds > 60) {
      _graphRangeController.text = _graphRangeSeconds.round().toString();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Graph range must be between 1 and 60 seconds.'),
          ),
        );
      return;
    }
    _setGraphRange(seconds.toDouble());
  }

  double? _inSelectedUnits(double? forceInKilonewtons) {
    if (forceInKilonewtons == null) return null;
    return switch (_unit) {
      'kg' => forceInKilonewtons * 101.9716213,
      'Lb' => forceInKilonewtons * 224.8089431,
      _ => forceInKilonewtons,
    };
  }

  String _formattedForce(double? force) {
    if (!_hasConnected) return '';
    return formatForceValue(_inSelectedUnits(force), unit: _unit);
  }

  @override
  void dispose() {
    _graphRefreshTimer.cancel();
    _peakAgeTimer.cancel();
    _graphFrameTime.dispose();
    _graphRangeController.dispose();
    _peakMaximumThresholdController.dispose();
    _peakMinimumThresholdController.dispose();
    _bleConnection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: _backgroundColor,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: _backgroundColor,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) {
            final panelWidth = math.min(
              constraints.maxWidth,
              constraints.maxHeight * 9 / 16,
            );
            final panelHeight = panelWidth * 16 / 9;
            return Center(
              child: SizedBox(
                width: panelWidth,
                height: panelHeight,
                child: DefaultTabController(
                  length: 4,
                  child: Column(
                    children: [
                      Expanded(
                        child: TabBarView(
                          children: [
                            _buildLiveTab(),
                            _buildPeakTab(),
                            _buildGraphTab(),
                            _buildSettingsTab(),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: panelWidth * .17,
                        child: const _AppTabBar(),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLiveTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final panelGap = constraints.maxWidth * .025;
        final flexHeight = constraints.maxHeight - panelGap * 4;
        final mainForceFontSize = math.min(
          (constraints.maxWidth - panelGap * 2) * .29,
          flexHeight * 54 / 85 * .3,
        );
        final relativeForce = _absoluteForce == null
            ? null
            : _absoluteForce! - _zeroForce;
        final mainForce = _showRelativeForce ? relativeForce : _absoluteForce;

        return Container(
          key: const ValueKey('live-panel-area'),
          color: _panelColor,
          padding: EdgeInsets.all(panelGap),
          child: Column(
            children: [
              Expanded(
                flex: 12,
                child: SizedBox(
                  key: const ValueKey('live-header-panel'),
                  child: _buildHeader(panelGap),
                ),
              ),
              SizedBox(height: panelGap),
              Expanded(
                flex: 54,
                child: SizedBox(
                  key: const ValueKey('live-main-panel'),
                  child: _buildLiveForceCard(mainForce),
                ),
              ),
              SizedBox(height: panelGap),
              Expanded(
                flex: 19,
                child: SizedBox(
                  key: const ValueKey('live-footer-panels'),
                  child: Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          key: const ValueKey('live-zero-panel'),
                          child: _buildLiveReadingActionCard(
                            label: 'RELATIVE ZERO',
                            force: _zeroForce,
                            fontSize: mainForceFontSize / 2,
                            actionLabel: 'REMOVE ZERO',
                            icon: Icons.exposure_zero,
                            onPressed: _removeZero,
                          ),
                        ),
                      ),
                      SizedBox(width: panelGap),
                      Expanded(
                        child: SizedBox(
                          key: const ValueKey('live-secondary-panel'),
                          child: _buildLiveReadingActionCard(
                            label: 'ABSOLUTE FORCE',
                            force: _absoluteForce,
                            fontSize: mainForceFontSize / 2,
                            actionLabel: 'SET AS ZERO',
                            icon: Icons.center_focus_strong,
                            onPressed: _setZero,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPeakTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final panelGap = constraints.maxWidth * .025;
        final flexHeight = constraints.maxHeight - panelGap * 4;
        final forceFontSize = math.min(
          (constraints.maxWidth - panelGap * 2) * .29,
          flexHeight * 54 / 85 * .3,
        );

        return Container(
          key: const ValueKey('peak-panel-area'),
          color: _panelColor,
          padding: EdgeInsets.all(panelGap),
          child: Column(
            children: [
              Expanded(
                flex: 12,
                child: SizedBox(
                  key: const ValueKey('peak-header-panel'),
                  child: _buildHeader(panelGap),
                ),
              ),
              SizedBox(height: panelGap),
              Expanded(
                flex: 36,
                child: SizedBox(
                  key: const ValueKey('peak-maximum-panel'),
                  child: _buildPeakCard(
                    maximum: true,
                    force: _peakMaximumForce,
                    timestamp: _peakMaximumTime,
                    forceFontSize: forceFontSize,
                    alertEnabled: _peakMaximumAlertEnabled,
                    threshold: _peakMaximumThreshold,
                    thresholdController: _peakMaximumThresholdController,
                    onThresholdChanged: (value) =>
                        _setPeakThreshold(maximum: true, value: value),
                    onReset: () => _resetPeak(maximum: true),
                    onAlertChanged: (enabled) =>
                        setState(() => _peakMaximumAlertEnabled = enabled),
                  ),
                ),
              ),
              SizedBox(height: panelGap),
              Expanded(
                flex: 36,
                child: SizedBox(
                  key: const ValueKey('peak-minimum-panel'),
                  child: _buildPeakCard(
                    maximum: false,
                    force: _peakMinimumForce,
                    timestamp: _peakMinimumTime,
                    forceFontSize: forceFontSize,
                    alertEnabled: _peakMinimumAlertEnabled,
                    threshold: _peakMinimumThreshold,
                    thresholdController: _peakMinimumThresholdController,
                    onThresholdChanged: (value) =>
                        _setPeakThreshold(maximum: false, value: value),
                    onReset: () => _resetPeak(maximum: false),
                    onAlertChanged: (enabled) =>
                        setState(() => _peakMinimumAlertEnabled = enabled),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPeakCard({
    required bool maximum,
    required double? force,
    required DateTime? timestamp,
    required double forceFontSize,
    required bool alertEnabled,
    required double threshold,
    required TextEditingController thresholdController,
    required ValueChanged<double> onThresholdChanged,
    required VoidCallback onReset,
    required ValueChanged<bool> onAlertChanged,
  }) {
    final mode = _showRelativeForce ? 'RELATIVE' : 'ABSOLUTE';
    final label = '$mode PEAK ${maximum ? 'MAXIMUM' : 'MINIMUM'}';
    final displayedForce = _showRelativeForce && force != null
        ? force - _zeroForce
        : force;

    return LayoutBuilder(
      builder: (context, constraints) {
        return _PanelCard(
          inset: 12,
          child: Column(
            children: [
              _FitText(
                label,
                style: const TextStyle(
                  color: _mutedColor,
                  fontSize: 11,
                  letterSpacing: .5,
                ),
              ),
              Expanded(
                child: Center(
                  child: _SevenSegmentDisplay(
                    _formattedForce(displayedForce),
                    style: TextStyle(
                      color: _accentColor,
                      fontFamily: 'DSEG7',
                      fontSize: forceFontSize,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      shadows: const [_forceTextGlow],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 82,
                child: Row(
                  children: [
                    Expanded(
                      child: _buildPeakControlCard(
                        keyName:
                            'peak-${maximum ? 'maximum' : 'minimum'}-time-card',
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const _FitText(
                              'TIME SINCE',
                              style: TextStyle(color: _mutedColor, fontSize: 8),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _elapsedSince(timestamp),
                              key: ValueKey(
                                'peak-${maximum ? 'maximum' : 'minimum'}-elapsed',
                              ),
                              style: const TextStyle(
                                color: _textColor,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _buildPeakControlCard(
                        keyName:
                            'peak-${maximum ? 'maximum' : 'minimum'}-reset-card',
                        child: SizedBox.expand(
                          child: TextButton(
                            key: ValueKey(
                              'peak-${maximum ? 'maximum' : 'minimum'}-reset',
                            ),
                            onPressed: onReset,
                            child: const Text('RESET'),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 2,
                      child: _buildPeakControlCard(
                        keyName:
                            'peak-${maximum ? 'maximum' : 'minimum'}-threshold-card',
                        child: Column(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  IconButton(
                                    key: ValueKey(
                                      'peak-${maximum ? 'maximum' : 'minimum'}-alert',
                                    ),
                                    tooltip: alertEnabled
                                        ? 'Disable alert'
                                        : 'Enable alert',
                                    onPressed: () =>
                                        onAlertChanged(!alertEnabled),
                                    color: alertEnabled
                                        ? _accentColor
                                        : _mutedColor,
                                    visualDensity: VisualDensity.compact,
                                    icon: Icon(
                                      alertEnabled
                                          ? Icons.notifications_active
                                          : Icons.notifications_off,
                                    ),
                                  ),
                                  const Expanded(
                                    child: _FitText(
                                      'ALERT THRESHOLD',
                                      style: TextStyle(
                                        color: _mutedColor,
                                        fontSize: 8,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 42,
                                    child: TextField(
                                      key: ValueKey(
                                        'peak-${maximum ? 'maximum' : 'minimum'}-threshold',
                                      ),
                                      controller: thresholdController,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      inputFormatters: [
                                        FilteringTextInputFormatter.allow(
                                          RegExp(r'^\d*\.?\d{0,2}'),
                                        ),
                                      ],
                                      onChanged: (text) {
                                        final value = double.tryParse(text);
                                        if (value != null &&
                                            value >= 0 &&
                                            value <= 1000) {
                                          _setPeakThreshold(
                                            maximum: maximum,
                                            value: value,
                                            updateController: false,
                                          );
                                        }
                                      },
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: _textColor,
                                        fontSize: 10,
                                      ),
                                      decoration: const InputDecoration(
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 2,
                                          vertical: 4,
                                        ),
                                        isDense: true,
                                        enabledBorder: UnderlineInputBorder(
                                          borderSide: BorderSide(
                                            color: _borderColor,
                                          ),
                                        ),
                                        focusedBorder: UnderlineInputBorder(
                                          borderSide: BorderSide(
                                            color: _accentColor,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              height: 24,
                              child: Slider(
                                key: ValueKey(
                                  'peak-${maximum ? 'maximum' : 'minimum'}-threshold-slider',
                                ),
                                min: 0,
                                max: 1000,
                                value: threshold,
                                onChanged: onThresholdChanged,
                                padding: EdgeInsets.zero,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPeakControlCard({
    required String keyName,
    required Widget child,
  }) {
    return Container(
      key: ValueKey(keyName),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _panelColor,
        border: Border.all(color: _borderColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }

  Widget _buildGraphTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final panelGap = width * .025;
        final flexHeight = height - panelGap * 4;
        final recordTop = panelGap * 3 + flexHeight * 66 / 85;
        final collapsedOverlayTop = recordTop + flexHeight * 19 / 85 / 2 - 24;
        final expandedOverlayTop = panelGap + flexHeight * 12 / 85 + panelGap;
        final expandedOverlayWidth = width - panelGap * 2;
        return Stack(
          key: const ValueKey('graph-panel-area'),
          clipBehavior: Clip.none,
          children: [
            Container(
              color: _panelColor,
              padding: EdgeInsets.all(panelGap),
              child: Column(
                children: [
                  Expanded(
                    flex: 12,
                    child: SizedBox(
                      key: const ValueKey('graph-header-panel'),
                      child: _buildHeader(panelGap),
                    ),
                  ),
                  SizedBox(height: panelGap),
                  Expanded(
                    flex: 54,
                    child: SizedBox(
                      key: const ValueKey('graph-plot-panel'),
                      child: _buildGraphCard(),
                    ),
                  ),
                  SizedBox(height: panelGap),
                  Expanded(
                    flex: 19,
                    child: SizedBox(
                      key: const ValueKey('graph-record-panel'),
                      child: _buildRecordCard(),
                    ),
                  ),
                ],
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              left: _showAutoRecordSettings ? panelGap : panelGap + 8,
              top: _showAutoRecordSettings
                  ? expandedOverlayTop
                  : collapsedOverlayTop,
              width: _showAutoRecordSettings ? expandedOverlayWidth : 100,
              bottom: _showAutoRecordSettings ? panelGap : null,
              height: _showAutoRecordSettings ? null : 48,
              child: IgnorePointer(
                ignoring: !_showAutoRecordSettings,
                child: ExcludeSemantics(
                  excluding: !_showAutoRecordSettings,
                  child: AnimatedOpacity(
                    key: const ValueKey('auto-settings-opacity'),
                    duration: const Duration(milliseconds: 150),
                    opacity: _showAutoRecordSettings ? 1 : 0,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _cardColor,
                        border: Border.all(color: _borderColor),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x66000000),
                            blurRadius: 16,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'Auto Record Settings',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: _textColor,
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              IconButton(
                                key: const ValueKey('close-auto-settings'),
                                tooltip: 'Close auto record settings',
                                icon: const Icon(Icons.close),
                                color: _mutedColor,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints.tightFor(
                                  width: 28,
                                  height: 28,
                                ),
                                onPressed: () => setState(
                                  () => _showAutoRecordSettings = false,
                                ),
                              ),
                            ],
                          ),
                          const Expanded(child: SizedBox.expand()),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGraphCard() {
    return _PanelCard(
      child: Column(
        children: [
          _FitText(
            '${_showRelativeForce ? 'RELATIVE' : 'ABSOLUTE'} FORCE  |  $_unit',
            style: const TextStyle(
              color: _mutedColor,
              fontSize: 10,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: ValueListenableBuilder<DateTime>(
                valueListenable: _graphFrameTime,
                builder: (context, frameTime, child) {
                  final samples = List<_ForceSample>.unmodifiable(
                    _graphSamples,
                  );
                  return CustomPaint(
                    key: const ValueKey('force-history-graph'),
                    painter: _ForceGraphPainter(
                      samples: samples,
                      now: frameTime,
                      rangeSeconds: _graphRangeSeconds,
                      zeroForce: _zeroForce,
                      showRelativeForce: _showRelativeForce,
                      unit: _unit,
                    ),
                    child: child,
                  );
                },
                child: Center(
                  child: _graphSamples.isEmpty
                      ? const Text(
                          'WAITING FOR DATA',
                          style: TextStyle(color: _mutedColor, fontSize: 10),
                        )
                      : const SizedBox.expand(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text(
                'RANGE',
                style: TextStyle(color: _mutedColor, fontSize: 9),
              ),
              Expanded(
                child: Slider(
                  key: const ValueKey('graph-range-slider'),
                  min: 1,
                  max: 60,
                  divisions: 59,
                  value: _graphRangeSeconds,
                  onChanged: _setGraphRange,
                ),
              ),
              SizedBox(
                width: 48,
                height: 36,
                child: TextField(
                  key: const ValueKey('graph-range-input'),
                  controller: _graphRangeController,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onSubmitted: _submitGraphRange,
                  style: const TextStyle(color: _textColor, fontSize: 12),
                  decoration: InputDecoration(
                    suffixText: 's',
                    suffixStyle: const TextStyle(
                      color: _mutedColor,
                      fontSize: 10,
                    ),
                    filled: true,
                    fillColor: _panelColor,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 6,
                    ),
                    isDense: true,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: _borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(color: _accentColor),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRecordCard() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final buttonExtent = math.max(
          24.0,
          math.min(48.0, constraints.maxHeight - 24),
        );
        return _PanelCard(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: _PanelActionButton(
                  label: 'AUTO',
                  onPressed: () => setState(
                    () => _showAutoRecordSettings = !_showAutoRecordSettings,
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('graph-record-toggle'),
                tooltip: _isRecording ? 'Stop recording' : 'Start recording',
                icon: Icon(
                  _isRecording ? Icons.stop_circle : Icons.fiber_manual_record,
                  size: math.min(38, buttonExtent * .8),
                ),
                padding: EdgeInsets.zero,
                constraints: BoxConstraints.tightFor(
                  width: buttonExtent,
                  height: buttonExtent,
                ),
                color: const Color(0xFFFF453A),
                onPressed: () => setState(() => _isRecording = !_isRecording),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(double gap) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 48;
        return Row(
          children: [
            Expanded(
              child: SizedBox(
                key: const ValueKey('header-bluetooth-card'),
                child: _buildBluetoothCard(compact: compact),
              ),
            ),
            SizedBox(width: gap),
            Expanded(
              child: SizedBox(
                key: const ValueKey('header-unit-card'),
                child: _buildHeaderValueCard(
                  label: 'UNIT',
                  value: _unit,
                  compact: compact,
                  onTap: _cycleUnit,
                ),
              ),
            ),
            SizedBox(width: gap),
            Expanded(
              child: SizedBox(
                key: const ValueKey('header-zero-card'),
                child: _buildHeaderValueCard(
                  label: 'ZERO',
                  value: _showRelativeForce ? 'REL' : 'ABS',
                  compact: compact,
                  onTap: () =>
                      setState(() => _showRelativeForce = !_showRelativeForce),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBluetoothCard({required bool compact}) {
    return Material(
      color: _cardColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: _toggleConnection,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 2 : 6,
            vertical: compact ? 1 : 4,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: _borderColor),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _FitText(
                'BLE STATUS',
                style: TextStyle(
                  color: _mutedColor,
                  fontSize: compact ? 8 : 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: compact ? 0 : 2),
              _FitText(
                _connectionStatus.toUpperCase(),
                style: TextStyle(
                  color: _textColor,
                  fontSize: compact ? 8 : 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderValueCard({
    required String label,
    required String value,
    required bool compact,
    required VoidCallback onTap,
  }) {
    return Material(
      color: _cardColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 2 : 6,
            vertical: compact ? 1 : 4,
          ),
          decoration: BoxDecoration(
            border: Border.all(color: _borderColor),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _FitText(
                label,
                style: TextStyle(
                  color: _mutedColor,
                  fontSize: compact ? 8 : 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: compact ? 0 : 2),
              _FitText(
                value,
                style: TextStyle(
                  color: _textColor,
                  fontSize: compact ? 9 : 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLiveForceCard(double? force) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final displayFontSize = math.min(
          constraints.maxWidth * .29,
          constraints.maxHeight * .3,
        );
        return _PanelCard(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              children: [
                _FitText(
                  _showRelativeForce ? 'RELATIVE FORCE' : 'ABSOLUTE FORCE',
                  style: const TextStyle(
                    color: _mutedColor,
                    fontSize: 12,
                    letterSpacing: 1.2,
                  ),
                ),
                Expanded(
                  flex: 5,
                  child: Center(
                    child: Transform.translate(
                      key: const ValueKey('live-main-force-digits'),
                      offset: const Offset(0, -20),
                      child: _SevenSegmentDisplay(
                        _formattedForce(force),
                        style: TextStyle(
                          color: _accentColor,
                          fontFamily: 'DSEG7',
                          fontSize: displayFontSize,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          shadows: const [_forceTextGlow],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLiveReadingActionCard({
    required String label,
    required double? force,
    required double fontSize,
    required String actionLabel,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: _cardColor,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: _borderColor),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _FitText(
                label,
                style: const TextStyle(color: _mutedColor, fontSize: 9),
              ),
              _forceText(_formattedForce(force), fontSize: fontSize),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    color: _accentColor,
                    size: 15,
                    shadows: const [_accentIconGlow],
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: _FitText(
                      actionLabel,
                      style: const TextStyle(
                        color: _textColor,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _forceText(String value, {required double fontSize}) {
    return _SevenSegmentDisplay(
      value,
      style: TextStyle(
        color: _textColor,
        fontFamily: 'DSEG7',
        fontSize: fontSize,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }

  Widget _buildSettingsTab() {
    return Container(
      color: _panelColor,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Text(
              'DISPLAY & SENSOR',
              style: TextStyle(
                color: _mutedColor,
                fontSize: 11,
                letterSpacing: 1.2,
              ),
            ),
          ),
          _SettingDropdown(
            label: 'Time format',
            value: _timeFormat,
            options: const ['24-hour', '12-hour'],
            onChanged: (value) => setState(() => _timeFormat = value),
          ),
          _SettingDropdown(
            label: 'Date format',
            value: _dateFormat,
            options: const ['dd.mm.yyyy', 'yyyy-mm-dd', 'mm/dd/yyyy'],
            onChanged: (value) => setState(() => _dateFormat = value),
          ),
          _SettingDropdown(
            label: 'Units',
            value: _unit,
            options: const ['kN', 'kg', 'Lb'],
            onChanged: (value) => setState(() => _unit = value),
          ),
          _SettingDropdown(
            label: 'Sample rate',
            value: _sampleRate,
            options: const ['10 Hz', '50 Hz', '100 Hz', '500 Hz', '1000 Hz'],
            onChanged: (value) => setState(() => _sampleRate = value),
          ),
        ],
      ),
    );
  }
}

class _AppTabBar extends StatelessWidget {
  const _AppTabBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _backgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: TabBar(
        indicator: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _accentColor, width: 2)),
        ),
        indicatorWeight: 2,
        labelColor: _accentColor,
        unselectedLabelColor: _mutedColor,
        labelStyle: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          shadows: [_accentTextGlow],
        ),
        unselectedLabelStyle: const TextStyle(fontSize: 9),
        tabs: const [
          Tab(icon: _TabIcon(Icons.sensors), text: 'LIVE'),
          Tab(icon: _TabIcon(Icons.trending_up), text: 'PEAK'),
          Tab(icon: _TabIcon(Icons.show_chart), text: 'GRAPH'),
          Tab(icon: _TabIcon(Icons.settings), text: 'SETTINGS'),
        ],
      ),
    );
  }
}

class _ForceSample {
  const _ForceSample(this.timestamp, this.forceInKilonewtons);

  final DateTime timestamp;
  final double forceInKilonewtons;
}

class _ForceGraphPainter extends CustomPainter {
  const _ForceGraphPainter({
    required this.samples,
    required this.now,
    required this.rangeSeconds,
    required this.zeroForce,
    required this.showRelativeForce,
    required this.unit,
  });

  final List<_ForceSample> samples;
  final DateTime now;
  final double rangeSeconds;
  final double zeroForce;
  final bool showRelativeForce;
  final String unit;

  double _displayValue(double forceInKilonewtons) {
    final force = showRelativeForce
        ? forceInKilonewtons - zeroForce
        : forceInKilonewtons;
    return switch (unit) {
      'kg' => force * 101.9716213,
      'Lb' => force * 224.8089431,
      _ => force,
    };
  }

  @override
  void paint(Canvas canvas, Size size) {
    final plot = Offset.zero & size;
    final gridPaint = Paint()
      ..color = _borderColor.withValues(alpha: 0.65)
      ..strokeWidth = 1;
    for (var index = 0; index <= 4; index++) {
      final y = plot.top + plot.height * index / 4;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
    }
    for (var index = 0; index <= 4; index++) {
      final x = plot.left + plot.width * index / 4;
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), gridPaint);
    }

    final rangeStart = now.subtract(
      Duration(milliseconds: (rangeSeconds * 1000).round()),
    );
    final visibleSamples = samples
        .where(
          (sample) =>
              !sample.timestamp.isBefore(rangeStart) &&
              !sample.timestamp.isAfter(now),
        )
        .toList(growable: false);
    if (visibleSamples.isEmpty) return;

    final values = visibleSamples
        .map((sample) => _displayValue(sample.forceInKilonewtons))
        .toList(growable: false);
    var minimum = values.reduce(math.min);
    var maximum = values.reduce(math.max);
    if (maximum == minimum) {
      final padding = math.max(maximum.abs() * 0.1, 1);
      minimum -= padding;
      maximum += padding;
    } else {
      final padding = (maximum - minimum) * 0.08;
      minimum -= padding;
      maximum += padding;
    }

    final rangeMilliseconds = rangeSeconds * 1000;
    final path = Path();
    for (var index = 0; index < visibleSamples.length; index++) {
      final sample = visibleSamples[index];
      final elapsed = sample.timestamp.difference(rangeStart).inMilliseconds;
      final x = plot.left + plot.width * elapsed / rangeMilliseconds;
      final y =
          plot.bottom -
          plot.height * (values[index] - minimum) / (maximum - minimum);
      final point = Offset(x, y);
      if (index == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }

    final glowPaint = Paint()
      ..color = _accentColor.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    final linePaint = Paint()
      ..color = _accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, glowPaint);
    canvas.drawPath(path, linePaint);
    if (visibleSamples.length == 1) {
      final point = Offset(
        plot.left +
            plot.width *
                visibleSamples.single.timestamp
                    .difference(rangeStart)
                    .inMilliseconds /
                rangeMilliseconds,
        plot.bottom -
            plot.height * (values.single - minimum) / (maximum - minimum),
      );
      canvas.drawCircle(point, 3, Paint()..color = _accentColor);
    }
  }

  @override
  bool shouldRepaint(covariant _ForceGraphPainter oldDelegate) {
    return oldDelegate.samples != samples ||
        oldDelegate.now != now ||
        oldDelegate.rangeSeconds != rangeSeconds ||
        oldDelegate.zeroForce != zeroForce ||
        oldDelegate.showRelativeForce != showRelativeForce ||
        oldDelegate.unit != unit;
  }
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({required this.child, this.inset = 10});

  final Widget child;
  final double inset;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(inset),
      decoration: BoxDecoration(
        color: _cardColor,
        border: Border.all(color: _borderColor),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

class _PanelActionButton extends StatelessWidget {
  const _PanelActionButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _buttonColor,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: _buttonBorderColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: _FitText(
                  label,
                  style: const TextStyle(color: _textColor, fontSize: 10),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingDropdown extends StatelessWidget {
  const _SettingDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.fromLTRB(14, 4, 10, 4),
      decoration: BoxDecoration(
        color: _cardColor,
        border: Border.all(color: _borderColor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: _textColor, fontSize: 12),
            ),
          ),
          SizedBox(
            width: 135,
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                isExpanded: true,
                dropdownColor: _cardColor,
                iconEnabledColor: _accentColor,
                icon: const Icon(
                  Icons.arrow_drop_down,
                  color: _accentColor,
                  shadows: [_accentIconGlow],
                ),
                style: const TextStyle(
                  color: _accentColor,
                  fontSize: 11,
                  shadows: [_accentTextGlow],
                ),
                items: options
                    .map(
                      (option) => DropdownMenuItem(
                        value: option,
                        child: Text(option, textAlign: TextAlign.end),
                      ),
                    )
                    .toList(),
                onChanged: (selection) {
                  if (selection != null) onChanged(selection);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SevenSegmentDisplay extends StatelessWidget {
  const _SevenSegmentDisplay(this.value, {required this.style});

  final String value;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final inactiveStyle = style.copyWith(
      color: _inactiveDisplayColor,
      shadows: const [],
    );
    return Stack(
      alignment: Alignment.center,
      children: [
        _FitText('8.8.8.8.', style: inactiveStyle),
        _FitText(value, style: style),
      ],
    );
  }
}

class _TabIcon extends StatelessWidget {
  const _TabIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final isSelected = IconTheme.of(context).color == _accentColor;
    return Icon(
      icon,
      size: 19,
      shadows: isSelected ? const [_accentIconGlow] : null,
    );
  }
}

class _FitText extends StatelessWidget {
  const _FitText(this.text, {required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(text, textAlign: TextAlign.center, style: style),
    );
  }
}
