import 'dart:async';
import 'package:app1/FAB.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class BluetoothLedPage extends StatefulWidget {
  const BluetoothLedPage({super.key});

  @override
  _BluetoothLedPageState createState() => _BluetoothLedPageState();
}

class _BluetoothLedPageState extends State<BluetoothLedPage> {
  BluetoothDevice? device;
  BluetoothCharacteristic? characteristic;
  StreamSubscription<List<ScanResult>>? _scanSubscription;

  final String deviceName = "ESP32_RGB";
  final String serviceUuid = "4848FFEE-525A-4B7B-89E2-7D7371AC4C0D";
  final String characteristicUuid = "1A2B3C4D-5E6F-7890-ABCD-EF0123456789";

  double _redValue = 0;
  double _greenValue = 0;
  double _blueValue = 0;

  bool isWriting = false;
  DateTime lastSendTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    _initBluetooth();
  }

  Future<void> _initBluetooth() async {
    await requestPermissions(); // 권한 묻기
    checkAdapterState(); // 블루투스 상태 확인 및 스캔
  }

  Future<void> requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.microphone,
    ].request();

    // 권한 상태 디버깅용 로그
    print("권한 상태: $statuses");
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    device?.disconnect();
    super.dispose();
  }

  // ====================== 연결 끊기 ======================
  Future<void> powerOffAndDisconnect() async {
    if (!mounted) return;
    if (characteristic != null) {
      try {
        await characteristic!.write([255, 255, 255], withoutResponse: true);
      } catch (e) {}
    }
    setState(() {
      _redValue = 0;
      _greenValue = 0;
      _blueValue = 0;
    });
    await Future.delayed(const Duration(milliseconds: 150));
    await device?.disconnect();
    setState(() {
      device = null;
      characteristic = null;
    });
  }

  // ====================== 블루투스 초기화 ======================
  Future<void> checkAdapterState() async {
    // 지원 여부 확인
    if (!(await FlutterBluePlus.isSupported)) return;

    // 블루투스가 꺼져있으면 켜기
    BluetoothAdapterState state = await FlutterBluePlus.adapterState.first;
    if (state == BluetoothAdapterState.off) {
      try {
        await FlutterBluePlus.turnOn();
      } catch (e) {
        print("블루투스 켜기 실패 (사용자가 거부함): $e");
      }
    }
    // 스캔 시작
    scanForDevice();
  }

  // ====================== 스캔 ======================
  Future<void> scanForDevice() async {
    if (device != null) return;

    await FlutterBluePlus.stopScan();
    _scanSubscription?.cancel();

    try {
      // 스캔 시작
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 10),
        withServices: [Guid(serviceUuid)], // 특정 UUID만 찾기
      );
    } catch (e) {
      print("스캔 시작 실패: $e");
    }

    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        // 이름이나 ID가 맞으면 연결
        if (r.device.platformName == deviceName ||
            r.device.remoteId.toString().contains(deviceName)) {
          FlutterBluePlus.stopScan();
          _scanSubscription?.cancel();
          connectToDevice(r.device);
          return;
        }
      }
    });
  }

  // ====================== 연결 ======================
  Future<void> connectToDevice(BluetoothDevice d) async {
    try {
      await d.connect(timeout: const Duration(seconds: 10));
      setState(() => device = d);
      await discoverServices();
    } catch (e) {
      print("연결 실패, 재스캔: $e");
      scanForDevice();
    }
  }

  // ====================== 서비스 탐색 ======================
  Future<void> discoverServices() async {
    if (device == null) return;

    List<BluetoothService> services = await device!.discoverServices();
    for (var service in services) {
      if (service.uuid.toString().toLowerCase() == serviceUuid.toLowerCase()) {
        for (var char in service.characteristics) {
          if (char.uuid.toString().toLowerCase() ==
              characteristicUuid.toLowerCase()) {
            setState(() => characteristic = char);
            return;
          }
        }
      }
    }
  }

  // ====================== 색상 전송 ======================
  Future<void> sendRGB(int r, int g, int b) async {
    if (characteristic == null || isWriting) return;
    if (DateTime.now().difference(lastSendTime).inMilliseconds < 30) return;

    try {
      isWriting = true;
      lastSendTime = DateTime.now();
      // Active Low (255 - 값)
      List<int> data = [255 - r, 255 - g, 255 - b];
      await characteristic!.write(data, withoutResponse: true);
    } catch (e) {
      print(e);
    } finally {
      isWriting = false;
    }
  }

  void updateColor() =>
      sendRGB(_redValue.toInt(), _greenValue.toInt(), _blueValue.toInt());

  // ====================== UI (변경 없음) ======================
  @override
  Widget build(BuildContext context) {
    bool isConnected = device != null && characteristic != null;

    return Scaffold(
      backgroundColor: Colors.grey.shade900,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(
                children: [
                  const Align(
                    alignment: Alignment.topCenter,
                    child: Text(
                      "MOOD LIGHT",
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.topRight,
                    child: IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      onPressed: () {
                        // 새로고침 시에도 권한 체크 후 스캔
                        powerOffAndDisconnect().then((_) {
                          requestPermissions().then((_) => scanForDevice());
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isConnected
                        ? Colors.green.withOpacity(0.2)
                        : Colors.red.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isConnected ? Colors.green : Colors.red,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isConnected
                            ? Icons.bluetooth_connected
                            : Icons.bluetooth_searching,
                        color: isConnected ? Colors.green : Colors.red,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isConnected ? "Connected" : "Scanning...",
                        style: TextStyle(
                          color: isConnected ? Colors.green : Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 40),
              if (!isConnected)
                const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              else
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        _buildModernSlider("RED", Colors.redAccent, _redValue, (
                          v,
                        ) {
                          setState(() => _redValue = v);
                          updateColor();
                        }),
                        const SizedBox(height: 20),
                        _buildModernSlider(
                          "GREEN",
                          Colors.greenAccent,
                          _greenValue,
                          (v) {
                            setState(() => _greenValue = v);
                            updateColor();
                          },
                        ),
                        const SizedBox(height: 20),
                        _buildModernSlider(
                          "BLUE",
                          Colors.blueAccent,
                          _blueValue,
                          (v) {
                            setState(() => _blueValue = v);
                            updateColor();
                          },
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      floatingActionButton: FABPage(
        onColorChange: (r, g, b) {
          setState(() {
            _redValue = r.toDouble();
            _greenValue = g.toDouble();
            _blueValue = b.toDouble();
          });
          updateColor();
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  Widget _buildModernSlider(
    String label,
    Color color,
    double value,
    ValueChanged<double> onChanged,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              Text(
                "${(value / 255 * 100).toInt()}%",
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: color,
              thumbColor: Colors.white,
              overlayColor: color.withOpacity(0.2),
            ),
            child: Slider(value: value, min: 0, max: 255, onChanged: onChanged),
          ),
        ],
      ),
    );
  }
}
