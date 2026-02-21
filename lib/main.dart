import 'dart:async'; // NEW: Needed for the Timer
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const Automation());
}

class Automation extends StatelessWidget {
  const Automation({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Automation',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0A12),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          primary: Colors.deepPurpleAccent,
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

// ==========================================
// SPLASH SCREEN WIDGET
// ==========================================
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const LEDControlPage()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Center(
            child: Text(
              "AUTOMATION",
              style: TextStyle(
                fontSize: 22, 
                fontWeight: FontWeight.bold,
                letterSpacing: 2.0, 
                color: Colors.white,
                shadows: [
                  Shadow(
                    color: Colors.deepPurpleAccent.withOpacity(0.8),
                    blurRadius: 15,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 40.0),
              child: Text(
                "Developed by Nihal Das Ankur",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 1.5,
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// MAIN DASHBOARD WIDGET
// ==========================================
class LEDControlPage extends StatefulWidget {
  const LEDControlPage({super.key});
  @override
  State<LEDControlPage> createState() => _LEDControlPageState();
}

class _LEDControlPageState extends State<LEDControlPage> {
  // Database References
  final _ledRef = FirebaseDatabase.instance.ref("ESP32_Device/ledStatus");
  final _tempRef = FirebaseDatabase.instance.ref("ESP32_Device/temperature");
  final _humRef = FirebaseDatabase.instance.ref("ESP32_Device/humidity");
  final _brightnessRef = FirebaseDatabase.instance.ref("ESP32_Device/brightness");
  
  // NEW: Firebase reference for the ESP32 Heartbeat
  final _heartbeatRef = FirebaseDatabase.instance.ref("ESP32_Device/heartbeat");

  bool _status = false;
  double _temp = 0.0;
  double _humidity = 0.0;
  double _brightness = 0.0;
  
  // NEW: Connection tracking variables
  bool _isDeviceConnected = false;
  DateTime _lastHeartbeat = DateTime.now();
  Timer? _connectionTimer;

  @override
  void initState() {
    super.initState();
    
    // 1. Listen for the ESP32 heartbeat ping
    _heartbeatRef.onValue.listen((event) {
      _lastHeartbeat = DateTime.now(); // Update the clock every time the ESP32 pings
      if (mounted && !_isDeviceConnected) {
        setState(() => _isDeviceConnected = true);
      }
    });

    // 2. Start a timer to constantly check if the ESP32 went silent
    _connectionTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      // If 8 seconds pass without a ping, consider it disconnected
      if (DateTime.now().difference(_lastHeartbeat).inSeconds > 8) {
        if (mounted && _isDeviceConnected) {
          setState(() => _isDeviceConnected = false);
        }
      }
    });
    
    _ledRef.onValue.listen((event) {
      final val = event.snapshot.value;
      if (mounted) setState(() => _status = (val == 1));
    });

    _tempRef.onValue.listen((event) {
      final val = double.tryParse(event.snapshot.value.toString()) ?? 0.0;
      if (mounted) setState(() => _temp = val);
    });

    _humRef.onValue.listen((event) {
      final val = double.tryParse(event.snapshot.value.toString()) ?? 0.0;
      if (mounted) setState(() => _humidity = val);
    });

    _brightnessRef.onValue.listen((event) {
      final val = double.tryParse(event.snapshot.value.toString()) ?? 0.0;
      if (mounted) setState(() => _brightness = val);
    });
  }

  @override
  void dispose() {
    _connectionTimer?.cancel(); // Always clean up timers
    super.dispose();
  }

  void _toggle() => _ledRef.set(_status ? 0 : 1);

  void _updateBrightness(double value) {
    _brightnessRef.set(value.toInt());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        title: Text(
          "AUTOMATION", 
          style: TextStyle(
            fontSize: 14, 
            fontWeight: FontWeight.w300, 
            letterSpacing: 2.5, 
            color: Colors.white.withOpacity(0.4) 
          )
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView( 
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("Living Room", 
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white)),
                
                // Status Badge for ESP32 Hardware
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _isDeviceConnected ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _isDeviceConnected ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(
                          color: _isDeviceConnected ? Colors.greenAccent : Colors.redAccent,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: _isDeviceConnected ? Colors.greenAccent.withOpacity(0.5) : Colors.redAccent.withOpacity(0.5),
                              blurRadius: 5,
                            )
                          ]
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isDeviceConnected ? "Connected" : "Disconnected",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _isDeviceConnected ? Colors.greenAccent : Colors.redAccent,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 25),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildCircularSensor("Temperature", _temp, "°C", Colors.orangeAccent, 0.4), 
                _buildCircularSensor("Humidity", _humidity, "%", Colors.blueAccent, 0.01),
              ],
            ),

            const SizedBox(height: 30),
            
            GestureDetector(
              onTap: _toggle,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOut,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: _status 
                    ? const LinearGradient(
                        colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)], 
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : LinearGradient(
                        colors: [Colors.white.withOpacity(0.05), Colors.white.withOpacity(0.1)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: _status ? Colors.white24 : Colors.white10),
                  boxShadow: _status ? [
                    BoxShadow(
                      color: const Color(0xFF4A00E0).withOpacity(0.5),
                      blurRadius: 25,
                      offset: const Offset(0, 10),
                    )
                  ] : [],
                ),
                child: Row(
                  children: [
                    Container(
                      height: 60, width: 60,
                      decoration: BoxDecoration(
                        color: _status ? Colors.white.withOpacity(0.2) : Colors.black26,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.light_mode_rounded,
                        size: 32,
                        color: _status ? Colors.yellowAccent : Colors.white30,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Light", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                          Text(_status ? "ON" : "OFF", style: TextStyle(color: _status ? Colors.white70 : Colors.white24)),
                        ],
                      ),
                    ),
                    Icon(
                      _status ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
                      size: 55,
                      color: _status ? Colors.white : Colors.white24,
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 30),

            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Brightness", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                      Text("${_brightness.toInt()}%", style: const TextStyle(fontSize: 16, color: Colors.white70)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return GestureDetector(
                        onPanDown: (details) {
                          double percent = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
                          setState(() => _brightness = percent * 100);
                          _updateBrightness(_brightness);
                        },
                        onPanUpdate: (details) {
                          double percent = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0);
                          setState(() => _brightness = percent * 100);
                          _updateBrightness(_brightness);
                        },
                        child: Container(
                          height: 55, 
                          width: constraints.maxWidth,
                          decoration: BoxDecoration(
                            color: Colors.black26, 
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Stack(
                            children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 50),
                                width: constraints.maxWidth * (_brightness / 100),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              Positioned(
                                left: 15,
                                top: 0,
                                bottom: 0,
                                child: Icon(
                                  Icons.brightness_6_rounded,
                                  color: _brightness > 10 ? Colors.white : Colors.white30,
                                  size: 24,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildCircularSensor(String label, double value, String unit, Color color, double multiplier) {
    return Container(
      width: MediaQuery.of(context).size.width * 0.4,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.white60)),
          const SizedBox(height: 15),
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                height: 70, width: 70,
                child: CircularProgressIndicator(
                  value: value * multiplier, 
                  strokeWidth: 6,
                  color: color,
                  backgroundColor: Colors.white10,
                ),
              ),
              Text("${value.toInt()}$unit", 
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}