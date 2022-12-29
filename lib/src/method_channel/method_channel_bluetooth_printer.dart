part of flutter_bluetooth_printer;

class UnknownState extends DiscoveryState {}

class PermissionRestrictedState extends DiscoveryState {}

class BluetoothDisabledState extends DiscoveryState {}

class BluetoothEnabledState extends DiscoveryState {}

class _MethodChannelBluetoothPrinter extends FlutterBluetoothPrinterPlatform {
  final channel = const MethodChannel('maseka.dev/flutter_bluetooth_printer');
  final discoveryChannel =
      const EventChannel('maseka.dev/flutter_bluetooth_printer/discovery');

  ProgressCallback? _progressCallback;

  bool _isInitialized = false;
  void _init() {
    if (_isInitialized) return;
    _isInitialized = true;
    channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'didUpdateState':
          final index = call.arguments as int;
          connectionStateNotifier.value =
              BluetoothConnectionState.values[index];
          break;

        case 'onPrintingProgress':
          final total = call.arguments['total'] as int;
          final progress = call.arguments['progress'] as int;
          _progressCallback?.call(total, progress);
          break;
      }
      return true;
    });
  }

  BluetoothState _intToState(int value) {
    switch (value) {
      case 0:
        return BluetoothState.unknown;

      case 1:
        return BluetoothState.disabled;

      case 2:
        return BluetoothState.enabled;

      case 3:
        return BluetoothState.notPermitted;

      case 4:
        return BluetoothState.permitted;
    }

    return BluetoothState.unknown;
  }

  Stream<DiscoveryState> _discovery() async* {
    final result = await channel.invokeMethod('getState');
    final state = _intToState(result);
    if (state == BluetoothState.notPermitted) {
      yield PermissionRestrictedState();
    }

    if (state == BluetoothState.disabled) {
      yield BluetoothDisabledState();
    }

    yield* discoveryChannel
        .receiveBroadcastStream(DateTime.now().millisecondsSinceEpoch)
        .map(
      (data) {
        final code = data['code'];
        final state = _intToState(code);

        if (state == BluetoothState.notPermitted) {
          return PermissionRestrictedState();
        }

        if (state == BluetoothState.disabled) {
          return BluetoothDisabledState();
        }

        if (state == BluetoothState.enabled) {
          return BluetoothEnabledState();
        }

        if (state == BluetoothState.permitted) {
          return BluetoothDevice(
            address: data['address'],
            name: data['name'],
            type: data['type'],
          );
        }

        return UnknownState();
      },
    );
  }

  @override
  Stream<DiscoveryState> get discovery => _discovery();

  bool _isBusy = false;

  @override
  Future<void> write({
    required String address,
    required Uint8List data,
    bool keepConnected = false,
    ProgressCallback? onProgress,
  }) async {
    try {
      if (_isBusy) {
        throw busyDeviceException;
      }

      _isBusy = true;
      _init();

      // ensure device is available
      await discovery
          .firstWhere((element) =>
              element is BluetoothDevice && element.address == address)
          .timeout(const Duration(seconds: 10));

      _progressCallback = onProgress;

      await channel.invokeMethod('write', {
        'address': address,
        'data': data,
        'keep_connected': keepConnected,
      });

      _progressCallback = null;
    } finally {
      _isBusy = false;
    }
  }

  @override
  Future<bool> disconnect(String address) async {
    final res = await channel.invokeMethod('disconnect', {
      'address': address,
    });

    if (res is bool) {
      return res;
    }

    return false;
  }
}
