import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

// --- GLOBAL VARIABLES ---
String currentFirebaseAppName = '';
late void Function(Color) globalChangeTheme;
bool globalVibrationEnabled = true;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AutomationAppRoot());
}

// ==========================================
// DATA MODEL: THE GADGET
// ==========================================
class Gadget {
  final String id;
  final String name;
  final String type; 
  final String path;
  final String unit; 

  Gadget({required this.id, required this.name, required this.type, required this.path, this.unit = ''});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'type': type, 'path': path, 'unit': unit};

  factory Gadget.fromJson(Map<String, dynamic> json) => Gadget(
    id: json['id'], name: json['name'], type: json['type'], path: json['path'], unit: json['unit'] ?? ''
  );
}

// ==========================================
// ROOT WIDGET (MANAGES THEME STATE)
// ==========================================
class AutomationAppRoot extends StatefulWidget {
  const AutomationAppRoot({super.key});

  @override
  State<AutomationAppRoot> createState() => _AutomationAppRootState();
}

class _AutomationAppRootState extends State<AutomationAppRoot> {
  Color _currentThemeColor = Colors.deepPurpleAccent;

  @override
  void initState() {
    super.initState();
    _loadThemeAndVibrationSettings();
    globalChangeTheme = changeThemeColor;
  }

  Future<void> _loadThemeAndVibrationSettings() async {
    final prefs = await SharedPreferences.getInstance();
    globalVibrationEnabled = prefs.getBool('vibration_enabled') ?? true;
    int? colorVal = prefs.getInt('theme_color_value');
    if (colorVal != null) {
      setState(() { _currentThemeColor = Color(colorVal); });
    }
  }

  void changeThemeColor(Color color) async {
    setState(() { _currentThemeColor = color; });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_color_value', color.value);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Automation',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0A12), 
        canvasColor: const Color(0xFF0A0A12), 
        primaryColor: _currentThemeColor,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _currentThemeColor, 
          primary: _currentThemeColor,
          brightness: Brightness.dark,
          surface: const Color(0xFF1E1E28), 
        ),
        switchTheme: SwitchThemeData(
          thumbColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.selected)) return _currentThemeColor;
            return Colors.grey;
          }),
          trackColor: MaterialStateProperty.resolveWith((states) {
            if (states.contains(MaterialState.selected)) return _currentThemeColor.withOpacity(0.5);
            return Colors.grey.withOpacity(0.5);
          }),
        ),
        appBarTheme: const AppBarTheme(backgroundColor: Colors.transparent, elevation: 0)
      ),
      home: const SplashScreen(),
    );
  }
}

// ==========================================
// HELPER: VIBRATE FUNCTION
// ==========================================
void triggerVibration() {
  if (globalVibrationEnabled) {
    HapticFeedback.vibrate(); 
  }
}

// ==========================================
// SPLASH SCREEN
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
    _checkSavedCredentials();
  }

  Future<void> _checkSavedCredentials() async {
    await Future.delayed(const Duration(seconds: 2));
    final prefs = await SharedPreferences.getInstance();
    final dbUrl = prefs.getString('dbUrl');

    if (mounted) {
      if (dbUrl != null && dbUrl.isNotEmpty) {
        await _initializeFirebase(prefs);
        Navigator.of(context).pushReplacement(PageRouteBuilder(pageBuilder: (context, a1, a2) => const DashboardPage(), transitionDuration: Duration.zero));
      } else {
        Navigator.of(context).pushReplacement(PageRouteBuilder(pageBuilder: (context, a1, a2) => const FirebaseSetupPage(), transitionDuration: Duration.zero));
      }
    }
  }

  Future<void> _initializeFirebase(SharedPreferences prefs) async {
    final dbUrl = prefs.getString('dbUrl');
    final apiKey = prefs.getString('apiKey');
    final appId = prefs.getString('appId');
    final projectId = prefs.getString('projectId');
    try {
      currentFirebaseAppName = 'IoTApp_${DateTime.now().millisecondsSinceEpoch}';
      await Firebase.initializeApp(
        name: currentFirebaseAppName,
        options: FirebaseOptions(apiKey: apiKey!, appId: appId!, messagingSenderId: '0000000000', projectId: projectId!, databaseURL: dbUrl!),
      );
    } catch (e) { debugPrint("Firebase Init Error: $e"); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Center(
            child: Text("AUTOMATION", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, letterSpacing: 2.0, color: Colors.white, shadows: [Shadow(color: Theme.of(context).primaryColor.withOpacity(0.8), blurRadius: 15, offset: const Offset(0, 3))])),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(padding: const EdgeInsets.only(bottom: 40.0), child: Text("Developed by Nihal Das Ankur", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, letterSpacing: 1.5, color: Colors.white.withOpacity(0.5)))),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// MAIN DASHBOARD WIDGET
// ==========================================
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});
  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  DatabaseReference? _pingRef;
  StreamSubscription? _pingSub;
  bool _isDeviceConnected = false;
  DateTime _lastHeartbeat = DateTime.now();
  Timer? _connectionTimer;
  int? _lastPingValue; // Tracks the ping to prevent cache bugs
  List<Gadget> _gadgets = [];
  bool get _isAppReady => currentFirebaseAppName.isNotEmpty && Firebase.apps.any((app) => app.name == currentFirebaseAppName);

  @override
  void initState() {
    super.initState();
    _loadGadgets();
    _initFirebaseConnections();
  }

  void _initFirebaseConnections() {
    _pingSub?.cancel();
    _connectionTimer?.cancel();
    _lastPingValue = null;
    setState(() { _isDeviceConnected = false; });

    if (_isAppReady) {
      final db = FirebaseDatabase.instanceFor(app: Firebase.app(currentFirebaseAppName));
      // NEW LOGIC: We listen to a live ping counter instead of a raw status string
      _pingRef = db.ref("ESP32_Device/ping");
      
      _pingSub = _pingRef?.onValue.listen((event) {
        final val = int.tryParse(event.snapshot.value.toString());
        if (val != null) {
          if (_lastPingValue == null) {
            // This is the initial cached read from memory. DO NOT set as connected yet.
            _lastPingValue = val;
          } else if (_lastPingValue != val) {
            // The value physically changed! The ESP32 is actively online.
            _lastPingValue = val;
            _lastHeartbeat = DateTime.now(); 
            if (mounted && !_isDeviceConnected) setState(() { _isDeviceConnected = true; }); 
          }
        }
      });
      
      // If 12 seconds pass without the ping counter changing, consider it dead
      _connectionTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
        if (DateTime.now().difference(_lastHeartbeat).inSeconds > 12) {
          if (mounted && _isDeviceConnected) setState(() { _isDeviceConnected = false; }); 
        }
      });
    }
  }

  @override
  void dispose() { _pingSub?.cancel(); _connectionTimer?.cancel(); super.dispose(); }

  Future<void> _loadGadgets() async {
    final prefs = await SharedPreferences.getInstance();
    final String? gadgetsJson = prefs.getString('saved_gadgets');
    if (gadgetsJson != null) {
      final List<dynamic> decoded = jsonDecode(gadgetsJson);
      setState(() { _gadgets = decoded.map((item) => Gadget.fromJson(item)).toList(); });
    }
  }

  Future<void> _saveGadgets() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(_gadgets.map((g) => g.toJson()).toList());
    await prefs.setString('saved_gadgets', encoded);
  }

  void _addNewGadget(Gadget gadget) { setState(() { _gadgets.add(gadget); }); _saveGadgets(); }
  void _updateGadget(Gadget updatedGadget) { setState(() { final index = _gadgets.indexWhere((g) => g.id == updatedGadget.id); if (index != -1) _gadgets[index] = updatedGadget; }); _saveGadgets(); }
  void _deleteGadget(String id) { setState(() { _gadgets.removeWhere((g) => g.id == id); }); _saveGadgets(); }

  void _showCodeExampleDialog() {
    // The raw ESP32 code to copy
    const String espCode = r'''
#include <Arduino.h>
#include <WiFi.h>
#include <Firebase_ESP_Client.h>

// Provide the RTDB payload info
#include "addons/RTDBHelper.h"

/* ---------------- WIFI ---------------- */
#define WIFI_SSID "YOUR WIFI NAME"
#define WIFI_PASSWORD "YOUR WIFI PASSWORD"

/* ---------------- FIREBASE ---------------- */
#define DATABASE_URL "PASTE_YOUR_DATABASE_URL_HERE" // e.g. https://your-project-id-default-rtdb.firebaseio.com/
#define DATABASE_SECRET "PASTE_YOUR_DATABASE_SECRET_HERE"

// --- HARDWARE PINS ---
#define TOGGLE_LED_PIN 2  // Standard On/Off LED
#define PWM_LED_PIN 23     // Fading Brightness LED

FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

// --- DUAL TIMERS ---
unsigned long sendDataPrevMillis = 0; // Slow timer for sending sensors
unsigned long readDataPrevMillis = 0; // Fast timer for reading buttons
int pingCounter = 0;

void setup() {
  Serial.begin(115200);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  
  Serial.print("Connecting to Wi-Fi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(300);
    Serial.print(".");
  }
  Serial.println("\nConnected to Wi-Fi!");

  // --- Bulletproof Firebase Setup ---
  config.database_url = DATABASE_URL;
  config.signer.tokens.legacy_token = DATABASE_SECRET;

  Firebase.begin(&config, &auth);
  Firebase.reconnectWiFi(true);
  
  Serial.println("Firebase Connected via Secret!");
  
  // Set up both pins
  pinMode(TOGGLE_LED_PIN, OUTPUT); 
  pinMode(PWM_LED_PIN, OUTPUT); 
}

void loop() {
  if (Firebase.ready()) {

    // ==============================================================
    // 1. FAST TIMER: INSTANT READS (Runs every 200 milliseconds)
    // ==============================================================
    if (millis() - readDataPrevMillis > 200 || readDataPrevMillis == 0) {
      readDataPrevMillis = millis();
      
      // A. Read Toggle Data (ON/OFF)
      if (Firebase.RTDB.getInt(&fbdo, "Room/light1")) {
         int ledState = fbdo.intData();
         if (ledState == 1) {
           digitalWrite(TOGGLE_LED_PIN, HIGH); 
         } else {
           digitalWrite(TOGGLE_LED_PIN, LOW);  
         }
      }

      // B. Read Brightness Data (SLIDER)
      if (Firebase.RTDB.getInt(&fbdo, "Room/brightness")) {
         int brightnessPercent = fbdo.intData(); // App sends 0 to 100
         
         // The ESP32 needs a number from 0 to 255. The map() function handles the math!
         int pwmValue = map(brightnessPercent, 0, 100, 0, 255);
         
         analogWrite(PWM_LED_PIN, pwmValue); // This smoothly fades the LED
      }
    }

    // ==============================================================
    // 2. SLOW TIMER: SENSORS & PING (Runs every 5000 milliseconds)
    // ==============================================================
    if (millis() - sendDataPrevMillis > 5000 || sendDataPrevMillis == 0) {
      sendDataPrevMillis = millis();

      // Send Ping Counter so the App shows "Connected"
      pingCounter++;
      Firebase.RTDB.setInt(&fbdo, "ESP32_Device/ping", pingCounter);
      Firebase.RTDB.setString(&fbdo, "ESP32_Device/status", "connected");

      // Write Fake Sensor Data
      Firebase.RTDB.setInt(&fbdo, "ESP32_Device/temperature", random(20, 35));
      Firebase.RTDB.setInt(&fbdo, "ESP32_Device/humidity", random(40, 70));
    }
    
  }
}
''';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E28),
        title: const Text("ESP32 C++ Code", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Container(
          width: double.maxFinite,
          height: MediaQuery.of(context).size.height * 0.5,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
          child: const SingleChildScrollView(
            child: SelectableText(espCode, style: TextStyle(fontFamily: 'monospace', color: Colors.greenAccent, fontSize: 12)),
          ),
        ),
        actions: [
          TextButton(onPressed: () { Navigator.pop(context); }, child: const Text("CLOSE", style: TextStyle(color: Colors.white70))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).primaryColor),
            onPressed: () {
              Clipboard.setData(const ClipboardData(text: espCode));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Code copied to clipboard!"), backgroundColor: Colors.green));
            },
            child: const Text("COPY CODE", style: TextStyle(color: Colors.white)),
          ),
        ],
      )
    );
  }

  void _handleMenuSelection(String value) async {
    switch (value) {
      case 'Firebase Setup':
        final didChange = await Navigator.push(context, MaterialPageRoute(builder: (context) => const FirebaseSetupPage()));
        if (didChange == true && mounted) { _initFirebaseConnections(); setState(() {}); }
        break;
      case 'Settings':
        Navigator.push(context, MaterialPageRoute(builder: (context) => const NewSettingsPage()));
        break;
      case 'Code Example':
        _showCodeExampleDialog();
        break;
      case 'Share':
        Share.share('Check out this custom IoT Automation App I built!');
        break;
      case 'Exit':
        if (Platform.isAndroid) { SystemNavigator.pop(); } else if (Platform.isIOS) { exit(0); }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    double horizontalPadding = 48.0; 
    double wrapSpacing = 16.0; 
    double availableWidth = MediaQuery.of(context).size.width - horizontalPadding;
    double fullWidth = availableWidth;
    double halfWidth = (availableWidth - wrapSpacing - 1.0) / 2.0; 

    return Scaffold(
      appBar: AppBar(
        title: Text("AUTOMATION", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w300, letterSpacing: 2.5, color: Colors.white.withOpacity(0.4))), centerTitle: true,
        leading: IconButton(icon: Icon(Icons.add_box_rounded, color: Colors.white.withOpacity(0.8)), onPressed: () { _showGadgetModal(); }),
        actions: [
          PopupMenuButton<String>(
            onSelected: _handleMenuSelection,
            icon: Icon(Icons.more_vert, color: Colors.white.withOpacity(0.8)),
            color: const Color(0xFF1E1E28),
            itemBuilder: (BuildContext context) {
              return {'Firebase Setup', 'Settings', 'Code Example', 'Share', 'Exit'}.map((String choice) {
                return PopupMenuItem<String>(value: choice, child: Text(choice, style: const TextStyle(color: Colors.white)));
              }).toList();
            },
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: SingleChildScrollView( 
        padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("My Dashboard", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: _isDeviceConnected ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: _isDeviceConnected ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3))),
                  child: Row(
                    children: [
                      Container(width: 8, height: 8, decoration: BoxDecoration(color: _isDeviceConnected ? Colors.greenAccent : Colors.redAccent, shape: BoxShape.circle, boxShadow: [BoxShadow(color: _isDeviceConnected ? Colors.greenAccent.withOpacity(0.5) : Colors.redAccent.withOpacity(0.5), blurRadius: 5)])),
                      const SizedBox(width: 8), Text(_isDeviceConnected ? "Connected" : "Disconnected", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _isDeviceConnected ? Colors.greenAccent : Colors.redAccent)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 25),

            if (_gadgets.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 50.0),
                  child: Column(
                    children: [
                      Icon(Icons.widgets_outlined, size: 60, color: Colors.white.withOpacity(0.2)), const SizedBox(height: 15),
                      Text("Your dashboard is empty.\nTap the + icon to create a gadget!", textAlign: TextAlign.center, style: TextStyle(color: Colors.white.withOpacity(0.4))),
                    ],
                  ),
                ),
              ),

            Wrap(
              spacing: wrapSpacing,
              runSpacing: 20,
              children: _gadgets.asMap().entries.map((entry) {
                int index = entry.key;
                Gadget gadget = entry.value;
                double currentWidth = gadget.type == 'sensor' ? halfWidth : fullWidth;
                return DragTarget<int>(
                  onWillAcceptWithDetails: (details) => details.data != index,
                  onAcceptWithDetails: (details) {
                    int draggedIndex = details.data;
                    setState(() { final temp = _gadgets[index]; _gadgets[index] = _gadgets[draggedIndex]; _gadgets[draggedIndex] = temp; });
                    _saveGadgets();
                    triggerVibration();
                  },
                  builder: (context, candidateData, rejectedData) {
                    bool isHovered = candidateData.isNotEmpty;
                    return LongPressDraggable<int>(
                      data: index,
                      onDragStarted: () => triggerVibration(),
                      feedback: Material(color: Colors.transparent, child: SizedBox(width: currentWidth, child: Opacity(opacity: 0.8, child: _buildDynamicGadget(gadget, currentWidth)))),
                      childWhenDragging: SizedBox(width: currentWidth, child: Opacity(opacity: 0.2, child: _buildDynamicGadget(gadget, currentWidth))),
                      child: AnimatedContainer(duration: const Duration(milliseconds: 200), width: currentWidth, decoration: isHovered ? BoxDecoration(border: Border.all(color: Theme.of(context).primaryColor, width: 2), borderRadius: BorderRadius.circular(28)) : null, child: _buildDynamicGadget(gadget, currentWidth)),
                    );
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildDynamicGadget(Gadget gadget, double definedWidth) {
    if (!_isAppReady) return const SizedBox();
    VoidCallback handleOptions = () { _showGadgetOptions(gadget); };
    switch (gadget.type) {
      case 'toggle': return ToggleGadgetWidget(gadget: gadget, onOptionsTap: handleOptions);
      case 'slider': return SliderGadgetWidget(gadget: gadget, onOptionsTap: handleOptions);
      case 'sensor': return SizedBox(width: definedWidth, child: SensorGadgetWidget(gadget: gadget, onOptionsTap: handleOptions));
      default: return const SizedBox();
    }
  }

  void _showGadgetOptions(Gadget gadget) {
    showModalBottomSheet(context: context, backgroundColor: const Color(0xFF1E1E28), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))), builder: (ctx) {
        return SafeArea(child: Padding(padding: const EdgeInsets.symmetric(vertical: 20), child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(gadget.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)), const SizedBox(height: 20),
                ListTile(leading: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Theme.of(context).primaryColor.withOpacity(0.1), shape: BoxShape.circle), child: Icon(Icons.edit_rounded, color: Theme.of(context).primaryColor)), title: const Text('Edit Gadget', style: TextStyle(color: Colors.white, fontSize: 16)), onTap: () { Navigator.pop(ctx); _showGadgetModal(existingGadget: gadget); }),
                ListTile(leading: Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.1), shape: BoxShape.circle), child: const Icon(Icons.delete_rounded, color: Colors.redAccent)), title: const Text('Delete Gadget', style: TextStyle(color: Colors.white, fontSize: 16)), onTap: () { Navigator.pop(ctx); _deleteGadget(gadget.id); triggerVibration(); }),
        ])));
    });
  }

  void _showGadgetModal({Gadget? existingGadget}) {
    String selectedType = existingGadget?.type ?? 'toggle';
    final nameCtrl = TextEditingController(text: existingGadget?.name ?? '');
    final pathCtrl = TextEditingController(text: existingGadget?.path ?? '');
    final unitCtrl = TextEditingController(text: existingGadget?.unit ?? '');
    final isEditing = existingGadget != null;
    showModalBottomSheet(context: context, isScrollControlled: true, backgroundColor: const Color(0xFF1E1E28), shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))), builder: (context) {
        return StatefulBuilder(builder: (context, setModalState) {
            return Padding(padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 24, right: 24, top: 24), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(isEditing ? "Edit Gadget" : "Add New Gadget", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)), const SizedBox(height: 20),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 16), decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(16)), child: DropdownButtonHideUnderline(child: DropdownButton<String>(value: selectedType, isExpanded: true, dropdownColor: const Color(0xFF2A2A35), items: const [DropdownMenuItem(value: 'toggle', child: Text("Toggle Button (On/Off)", style: TextStyle(color: Colors.white))), DropdownMenuItem(value: 'slider', child: Text("Slider (Brightness/Speed)", style: TextStyle(color: Colors.white))), DropdownMenuItem(value: 'sensor', child: Text("Sensor Reading (Temp/Humidity)", style: TextStyle(color: Colors.white)))], onChanged: (val) { setModalState(() { selectedType = val!; }); }))),
                  const SizedBox(height: 15), TextField(controller: nameCtrl, style: const TextStyle(color: Colors.white), decoration: _inputDeco("Gadget Name (e.g. Bed Light)")), const SizedBox(height: 15), TextField(controller: pathCtrl, style: const TextStyle(color: Colors.white), decoration: _inputDeco("Firebase Path (e.g. Room1/light)")),
                  const SizedBox(height: 15), if (selectedType == 'sensor') ...[TextField(controller: unitCtrl, style: const TextStyle(color: Colors.white), decoration: _inputDeco("Unit (e.g. °C, %)")), const SizedBox(height: 15)],
                  SizedBox(width: double.infinity, height: 50, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).primaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), onPressed: () async {
                        if (nameCtrl.text.isNotEmpty && pathCtrl.text.isNotEmpty) {
                          final newGadget = Gadget(id: existingGadget?.id ?? DateTime.now().millisecondsSinceEpoch.toString(), name: nameCtrl.text, type: selectedType, path: pathCtrl.text, unit: unitCtrl.text);
                          if (_isAppReady && (selectedType == 'toggle' || selectedType == 'slider')) { try { final db = FirebaseDatabase.instanceFor(app: Firebase.app(currentFirebaseAppName)); final snapshot = await db.ref(pathCtrl.text).get(); if (!snapshot.exists) await db.ref(pathCtrl.text).set(0); } catch (e) { debugPrint("Firebase error: $e"); } }
                          isEditing ? _updateGadget(newGadget) : _addNewGadget(newGadget);
                          if (context.mounted) Navigator.pop(context);
                        }
                      }, child: Text(isEditing ? "SAVE CHANGES" : "CREATE GADGET", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
                  const SizedBox(height: 30)]));
        });
    });
  }
  InputDecoration _inputDeco(String hint) { return InputDecoration(hintText: hint, hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)), filled: true, fillColor: Colors.white.withOpacity(0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)); }
}

// ==========================================
// NEW SETTINGS PAGE (THEME & VIBRATION)
// ==========================================
class NewSettingsPage extends StatefulWidget {
  const NewSettingsPage({super.key});
  @override
  State<NewSettingsPage> createState() => _NewSettingsPageState();
}

class _NewSettingsPageState extends State<NewSettingsPage> {
  bool _vibrationEnabled = globalVibrationEnabled;

  void _showThemePickerDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E28),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text("Select Theme Color", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildThemeOption(ctx, "Purple", Colors.deepPurpleAccent),
              _buildThemeOption(ctx, "Green", Colors.greenAccent),
              _buildThemeOption(ctx, "Cyan", Colors.cyanAccent),
              _buildThemeOption(ctx, "Blue", Colors.blueAccent),
            ],
          ),
        );
      }
    );
  }

  Widget _buildThemeOption(BuildContext ctx, String name, Color color) {
    bool isSelected = Theme.of(context).primaryColor == color;
    return ListTile(
      leading: CircleAvatar(backgroundColor: color, radius: 12),
      title: Text(name, style: TextStyle(color: isSelected ? color : Colors.white)),
      trailing: isSelected ? Icon(Icons.check, color: color) : null,
      onTap: () {
        globalChangeTheme(color);
        triggerVibration();
        Navigator.pop(ctx);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(title: const Text("Settings"), centerTitle: true),
      body: ListView(
        children: [
          _buildSectionHeader("General"),
          ListTile(
            leading: const Icon(Icons.palette_outlined, color: Colors.white70),
            title: const Text("Theme", style: TextStyle(color: Colors.white, fontSize: 16)),
            subtitle: Text(_getColorName(primaryColor), style: TextStyle(color: primaryColor)),
            onTap: _showThemePickerDialog,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.vibration, color: Colors.white70),
            title: const Text("Vibration", style: TextStyle(color: Colors.white, fontSize: 16)),
            subtitle: const Text("On/Off vibration for button press", style: TextStyle(color: Colors.white54)),
            value: _vibrationEnabled,
            activeColor: primaryColor,
            onChanged: (bool value) async {
              setState(() => _vibrationEnabled = value);
              globalVibrationEnabled = value; 
              final prefs = await SharedPreferences.getInstance();
              prefs.setBool('vibration_enabled', value);
              if (value) triggerVibration(); 
            },
          ),
          const Divider(color: Colors.white24, height: 40),
          _buildSectionHeader("Feedback"),
          ListTile(
            leading: const Icon(Icons.help_outline, color: Colors.white70),
            title: const Text("Help & Feedback", style: TextStyle(color: Colors.white, fontSize: 16)),
            subtitle: const Text("Questions or suggestions? We'd love to hear them.", style: TextStyle(color: Colors.white54)),
            onTap: () { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Opening help page..."))); },
          ),
           ListTile(
            leading: const Icon(Icons.star_rate_rounded, color: Colors.white70),
            title: const Text("Rate App", style: TextStyle(color: Colors.white, fontSize: 16)),
            subtitle: const Text("Please let us know how we're doing!", style: TextStyle(color: Colors.white54)),
            onTap: () { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Opening app store..."))); },
          ),
           const Divider(color: Colors.white24, height: 40),
          _buildSectionHeader("About"),
           ListTile(
            leading: const Icon(Icons.privacy_tip_outlined, color: Colors.white70),
            title: const Text("Privacy Policy", style: TextStyle(color: Colors.white, fontSize: 16)),
            onTap: () { },
          ),
           ListTile(
            leading: const Icon(Icons.info_outline, color: Colors.white70),
            title: const Text("About", style: TextStyle(color: Colors.white, fontSize: 16)),
            subtitle: const Text("Version 1.0.0", style: TextStyle(color: Colors.white54)),
            onTap: () { },
          ),
          const SizedBox(height: 50),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 24, top: 20, bottom: 10),
      child: Text(title, style: TextStyle(color: Theme.of(context).primaryColor, fontSize: 14, fontWeight: FontWeight.bold)),
    );
  }

  String _getColorName(Color color) {
    if (color == Colors.deepPurpleAccent) return "Purple";
    if (color == Colors.greenAccent) return "Green";
    if (color == Colors.cyanAccent) return "Cyan";
    if (color == Colors.blueAccent) return "Blue";
    return "Custom";
  }
}

// ==========================================
// FIREBASE SETUP PAGE
// ==========================================
class FirebaseSetupPage extends StatefulWidget {
  const FirebaseSetupPage({super.key});
  @override
  State<FirebaseSetupPage> createState() => _FirebaseSetupPageState();
}

class _FirebaseSetupPageState extends State<FirebaseSetupPage> {
  final _dbUrlCtrl = TextEditingController(); final _apiKeyCtrl = TextEditingController(); final _appIdCtrl = TextEditingController(); bool _isLoading = false;
  @override
  void initState() { super.initState(); _loadExistingCredentials(); }
  Future<void> _loadExistingCredentials() async { final prefs = await SharedPreferences.getInstance(); _dbUrlCtrl.text = prefs.getString('dbUrl') ?? ""; _apiKeyCtrl.text = prefs.getString('apiKey') ?? ""; _appIdCtrl.text = prefs.getString('appId') ?? ""; }
  Future<void> _saveAndConnect() async {
    setState(() { _isLoading = true; });
    String dbUrl = _dbUrlCtrl.text.trim(); if (dbUrl.isNotEmpty && !dbUrl.startsWith('http')) dbUrl = 'https://$dbUrl';
    String apiKey = _apiKeyCtrl.text.trim(); String appId = _appIdCtrl.text.trim();
    String? projectId; final match1 = RegExp(r'https:\/\/([a-zA-Z0-9-]+)-default-rtdb').firstMatch(dbUrl); final match2 = RegExp(r'https:\/\/([a-zA-Z0-9-]+)\.firebaseio\.com').firstMatch(dbUrl); if (match1 != null) projectId = match1.group(1); else if (match2 != null) projectId = match2.group(1);
    if (apiKey.isEmpty || appId.isEmpty || projectId == null || dbUrl.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error: Bad Credentials"), backgroundColor: Colors.redAccent)); setState(() { _isLoading = false; }); return; }
    final prefs = await SharedPreferences.getInstance(); await prefs.setString('dbUrl', dbUrl); await prefs.setString('apiKey', apiKey); await prefs.setString('appId', appId); await prefs.setString('projectId', projectId);
    try { if (currentFirebaseAppName.isNotEmpty) { try { await Firebase.app(currentFirebaseAppName).delete(); } catch (_) {} }
      currentFirebaseAppName = 'IoTApp_${DateTime.now().millisecondsSinceEpoch}';
      await Firebase.initializeApp(name: currentFirebaseAppName, options: FirebaseOptions(apiKey: apiKey, appId: appId, messagingSenderId: '0000000000', projectId: projectId, databaseURL: dbUrl));
      if (mounted) { if (Navigator.canPop(context)) { Navigator.pop(context, true); } else { Navigator.of(context).pushReplacement(PageRouteBuilder(pageBuilder: (context, a1, a2) => const DashboardPage(), transitionDuration: Duration.zero)); } } 
    } catch (e) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: ${e.toString()}"), backgroundColor: Colors.redAccent)); setState(() { _isLoading = false; }); }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(leading: Navigator.canPop(context) ? IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () { Navigator.pop(context); }) : null, title: Text("FIREBASE SETUP", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w300, letterSpacing: 2.5, color: Colors.white.withOpacity(0.4))), centerTitle: true),
      body: SingleChildScrollView(padding: const EdgeInsets.all(24.0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text("Link Database", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)), const SizedBox(height: 10), Text("Paste your Firebase details below.", style: TextStyle(color: Colors.white.withOpacity(0.5))), const SizedBox(height: 30), _buildTextField("Database URL", _dbUrlCtrl, "https://your-project.firebaseio.com"), const SizedBox(height: 20), _buildTextField("Web API Key", _apiKeyCtrl, "AIzaSy..."), const SizedBox(height: 20), _buildTextField("App ID", _appIdCtrl, "1:123456789:web:..."), const SizedBox(height: 40), SizedBox(width: double.infinity, height: 55, child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Theme.of(context).primaryColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))), onPressed: _isLoading ? null : () { _saveAndConnect(); }, child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("SAVE & CONNECT", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.5))))])),
    );
  }
  Widget _buildTextField(String label, TextEditingController controller, String hint) { return TextField(controller: controller, style: const TextStyle(color: Colors.white), decoration: InputDecoration(labelText: label, labelStyle: TextStyle(color: Colors.white.withOpacity(0.5)), hintText: hint, hintStyle: TextStyle(color: Colors.white.withOpacity(0.2)), filled: true, fillColor: Colors.white.withOpacity(0.05), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none))); }
}

// ==========================================
// UI: GADGET WIDGETS
// ==========================================
class ToggleGadgetWidget extends StatelessWidget {
  final Gadget gadget; final VoidCallback onOptionsTap;
  const ToggleGadgetWidget({super.key, required this.gadget, required this.onOptionsTap});
  @override
  Widget build(BuildContext context) {
    final db = FirebaseDatabase.instanceFor(app: Firebase.app(currentFirebaseAppName));
    final ref = db.ref(gadget.path);
    return StreamBuilder(stream: ref.onValue, builder: (context, snapshot) {
        bool status = false; if (snapshot.hasData && snapshot.data!.snapshot.value != null) { status = (snapshot.data!.snapshot.value.toString() == "1" || snapshot.data!.snapshot.value == true); }
        final primaryColor = Theme.of(context).primaryColor;
        return GestureDetector(
          onTap: () { ref.set(status ? 0 : 1); triggerVibration(); }, 
          child: AnimatedContainer(duration: const Duration(milliseconds: 400), curve: Curves.easeInOut, decoration: BoxDecoration(
              gradient: status ? LinearGradient(colors: [primaryColor.withOpacity(0.8), primaryColor], begin: Alignment.topLeft, end: Alignment.bottomRight) : LinearGradient(colors: [Colors.white.withOpacity(0.05), Colors.white.withOpacity(0.1)], begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(28), border: Border.all(color: status ? Colors.white24 : Colors.white10),
              boxShadow: status ? [BoxShadow(color: primaryColor.withOpacity(0.5), blurRadius: 25, offset: const Offset(0, 10))] : []),
            child: Stack(children: [Padding(padding: const EdgeInsets.only(left: 24, right: 24, top: 32, bottom: 24), child: Row(children: [
                      Container(height: 60, width: 60, decoration: BoxDecoration(color: status ? Colors.white.withOpacity(0.2) : Colors.black26, shape: BoxShape.circle), child: Icon(Icons.power_settings_new_rounded, size: 32, color: status ? Colors.white : Colors.white30)),
                      const SizedBox(width: 20), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(gadget.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)), Text(status ? "ON" : "OFF", style: TextStyle(color: status ? Colors.white70 : Colors.white24))])),
                      Icon(status ? Icons.toggle_on_rounded : Icons.toggle_off_rounded, size: 55, color: status ? Colors.white : Colors.white24)])),
                Positioned(top: 10, right: 10, child: GestureDetector(onTap: onOptionsTap, child: Container(padding: const EdgeInsets.all(8), color: Colors.transparent, child: const Icon(Icons.more_vert_rounded, color: Colors.white54, size: 20))))])));
      });
  }
}

class SensorGadgetWidget extends StatelessWidget {
  final Gadget gadget; final VoidCallback onOptionsTap;
  const SensorGadgetWidget({super.key, required this.gadget, required this.onOptionsTap});
  @override
  Widget build(BuildContext context) {
    final db = FirebaseDatabase.instanceFor(app: Firebase.app(currentFirebaseAppName));
    return StreamBuilder(stream: db.ref(gadget.path).onValue, builder: (context, snapshot) {
        double value = 0.0; if (snapshot.hasData && snapshot.data!.snapshot.value != null) { value = double.tryParse(snapshot.data!.snapshot.value.toString()) ?? 0.0; }
        Color ringColor = Theme.of(context).primaryColor;
        if (gadget.unit.contains('C') || gadget.unit.contains('F')) ringColor = Colors.orangeAccent;
        if (gadget.unit.contains('%') && !gadget.name.toLowerCase().contains('bright')) ringColor = Colors.blueAccent;
        return Container(decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(24)), child: Stack(children: [
              SizedBox(width: double.infinity, child: Padding(padding: const EdgeInsets.only(left: 16, right: 16, top: 24, bottom: 20), child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
                      Text(gadget.name, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: Colors.white70), overflow: TextOverflow.ellipsis), const SizedBox(height: 15),
                      Stack(alignment: Alignment.center, children: [SizedBox(height: 70, width: 70, child: CircularProgressIndicator(value: (value / 100.0).clamp(0.0, 1.0), strokeWidth: 6, color: ringColor, backgroundColor: Colors.white10)),
                          Text("${value.toInt()}${gadget.unit}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))])]))),
              Positioned(top: 8, right: 8, child: GestureDetector(onTap: onOptionsTap, child: Container(padding: const EdgeInsets.all(8), color: Colors.transparent, child: const Icon(Icons.more_vert_rounded, color: Colors.white54, size: 18))))]));
      });
  }
}

class SliderGadgetWidget extends StatefulWidget {
  final Gadget gadget; final VoidCallback onOptionsTap;
  const SliderGadgetWidget({super.key, required this.gadget, required this.onOptionsTap});
  @override
  State<SliderGadgetWidget> createState() => _SliderGadgetWidgetState();
}
class _SliderGadgetWidgetState extends State<SliderGadgetWidget> {
  double _localValue = 0; bool _isDragging = false;
  @override
  Widget build(BuildContext context) {
    final db = FirebaseDatabase.instanceFor(app: Firebase.app(currentFirebaseAppName)); final ref = db.ref(widget.gadget.path);
    final primaryColor = Theme.of(context).primaryColor;
    return StreamBuilder(stream: ref.onValue, builder: (context, snapshot) {
        if (!_isDragging && snapshot.hasData && snapshot.data!.snapshot.value != null) { _localValue = double.tryParse(snapshot.data!.snapshot.value.toString()) ?? 0.0; }
        return Container(decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(28), border: Border.all(color: Colors.white10)), child: Stack(children: [
              Padding(padding: const EdgeInsets.only(left: 24, right: 24, top: 32, bottom: 24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Text(widget.gadget.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white))), Text("${_localValue.toInt()}%", style: const TextStyle(fontSize: 16, color: Colors.white70))]), const SizedBox(height: 20),
                    LayoutBuilder(builder: (context, constraints) {
                        return GestureDetector(
                          onPanDown: (details) { setState(() { _isDragging = true; _localValue = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0) * 100; }); ref.set(_localValue.toInt()); triggerVibration(); },
                          onPanUpdate: (details) { setState(() { _localValue = (details.localPosition.dx / constraints.maxWidth).clamp(0.0, 1.0) * 100; }); ref.set(_localValue.toInt()); },
                          onPanEnd: (details) { setState(() { _isDragging = false; }); triggerVibration(); }, onPanCancel: () { setState(() { _isDragging = false; }); },
                          child: Container(height: 55, width: constraints.maxWidth, decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(16)), child: Stack(children: [
                                AnimatedContainer(duration: _isDragging ? Duration.zero : const Duration(milliseconds: 100), width: constraints.maxWidth * (_localValue / 100), decoration: BoxDecoration(gradient: LinearGradient(colors: [primaryColor.withOpacity(0.8), primaryColor], begin: Alignment.centerLeft, end: Alignment.centerRight), borderRadius: BorderRadius.circular(16))),
                                Positioned(left: 15, top: 0, bottom: 0, child: Icon(Icons.tune_rounded, color: _localValue > 10 ? Colors.white : Colors.white30, size: 24))])));
                      })])),
              Positioned(top: 10, right: 10, child: GestureDetector(onTap: widget.onOptionsTap, child: Container(padding: const EdgeInsets.all(8), color: Colors.transparent, child: const Icon(Icons.more_vert_rounded, color: Colors.white54, size: 20))))]));
      });
  }
}