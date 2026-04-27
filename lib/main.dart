import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:workmanager/workmanager.dart';
import 'firebase_options.dart';
import 'service/environment_service.dart';

// ==========================================
// 后台自动化引擎 (保持不变)
// ==========================================
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      EnvironmentService envService = EnvironmentService();
      final data = await envService.fetchEnvironmentalData();

      if (data != null) {
        double humidity = (data['humidity'] as num).toDouble();
        double so2 = (data['so2'] as num).toDouble();
        double hourlyRate = (humidity * 0.3) + (so2 * 0.7);

        final itemsSnapshot = await FirebaseFirestore.instance.collection('silver_items').get();
        DateTime now = DateTime.now();

        for (var doc in itemsSnapshot.docs) {
          var itemData = doc.data();
          Timestamp? rawTime = itemData['last_sync_time'] as Timestamp?;
          DateTime lastSync = rawTime?.toDate() ?? now;
          
          double hoursElapsed = now.difference(lastSync).inSeconds / 3600.0;
          if (hoursElapsed <= 0) continue;

          double increment = hourlyRate * hoursElapsed * 0.05; 
          double newTotal = (itemData['total_oxidation'] as num).toDouble() + increment;

          await doc.reference.update({
            'total_oxidation': newTotal,
            'last_sync_time': FieldValue.serverTimestamp(),
          });

          await FirebaseFirestore.instance.collection('patina_logs').add({
            'item_id': doc.id,
            'timestamp': FieldValue.serverTimestamp(),
            'cumulative_value': newTotal,
          });
        }
      }
    } catch (e) {
      print("Background Task Error: $e");
    }
    return Future.value(true);
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  Workmanager().registerPeriodicTask(
    "unique_patina_sync_1", 
    "patinaBackgroundSync",
    frequency: const Duration(hours: 1), 
    constraints: Constraints(networkType: NetworkType.connected),
  );

  runApp(const MyApp());
}

// ==========================================
// 🎨 全新 Amekaji 质感暗黑主题
// ==========================================
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Digital Patina',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212), // 极深灰背景
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFB0BEC5), // 银灰主色调
          secondary: Color(0xFFD84315), // 铁锈橙高光
          surface: Color(0xFF1E1E1E), // 卡片颜色
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF121212),
          elevation: 0,
          centerTitle: true,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 10,
        ),
      ),
      home: const InventoryScreen(), 
    );
  }
}

// ==========================================
// 1. 首页：银饰资产库 (视觉升级)
// ==========================================
class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key});

  void _addNewItem(BuildContext context) {
    TextEditingController nameController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text("Register New Silver", style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: nameController,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: "e.g., First Arrows Feather",
            hintStyle: TextStyle(color: Colors.grey),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFFB0BEC5))),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFB0BEC5), foregroundColor: Colors.black),
            onPressed: () async {
              if (nameController.text.isNotEmpty) {
                await FirebaseFirestore.instance.collection('silver_items').add({
                  'name': nameController.text,
                  'alloy_type': '950 Silver',
                  'total_oxidation': 0.0,
                  'last_sync_time': FieldValue.serverTimestamp(),
                  'created_at': FieldValue.serverTimestamp(),
                });
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: const Text("Add Item"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('MY COLLECTION', style: TextStyle(letterSpacing: 2.0, fontWeight: FontWeight.bold))),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance.collection('silver_items').orderBy('created_at', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          if (snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.diamond_outlined, size: 64, color: Colors.grey.withOpacity(0.3)),
                  const SizedBox(height: 16),
                  const Text("No pieces tracked yet.\nAdd your first silver item.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 16)),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              var doc = snapshot.data!.docs[index];
              var data = doc.data() as Map<String, dynamic>;
              double currentOxidation = (data['total_oxidation'] as num?)?.toDouble() ?? 0.0;

              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.grey.withOpacity(0.1), border: Border.all(color: Colors.grey.withOpacity(0.3))),
                    child: const Icon(Icons.blur_on, color: Colors.white70),
                  ),
                  title: Text(data['name'] ?? 'Unknown Item', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text("Patina Level: ${currentOxidation.toStringAsFixed(3)}", style: TextStyle(color: Colors.orangeAccent.withOpacity(0.8))),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => PatinaDashboard(itemId: doc.id, itemName: data['name'])));
                  },
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFFB0BEC5),
        foregroundColor: Colors.black,
        onPressed: () => _addNewItem(context),
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ==========================================
// 2. 专属仪表盘 (Bug 1: 红屏修复 & UI重绘)
// ==========================================
class PatinaDashboard extends StatefulWidget {
  final String itemId;
  final String itemName;
  const PatinaDashboard({super.key, required this.itemId, required this.itemName});

  @override
  State<PatinaDashboard> createState() => _PatinaDashboardState();
}

class _PatinaDashboardState extends State<PatinaDashboard> {
  final EnvironmentService _envService = EnvironmentService();
  bool _isLoading = false;
  String _displayText = "Awaiting environmental scan...";

  void _fetchData(double currentOxidation, DateTime lastSync) async {
    setState(() {
      _isLoading = true;
      _displayText = "Intercepting London atmospheric data...";
    });

    final data = await _envService.fetchEnvironmentalData();

    if (data != null) {
      double humidity = (data['humidity'] as num).toDouble();
      double so2 = (data['so2'] as num).toDouble();
      double hourlyRate = (humidity * 0.3) + (so2 * 0.7);

      DateTime now = DateTime.now();
      double hoursElapsed = now.difference(lastSync).inSeconds / 3600.0;
      
      double increment = hourlyRate * (hoursElapsed > 0 ? hoursElapsed : 0.0001) * 0.05; 
      double newTotal = currentOxidation + increment;

      try {
        await FirebaseFirestore.instance.collection('silver_items').doc(widget.itemId).update({
          'total_oxidation': newTotal,
          'last_sync_time': FieldValue.serverTimestamp(),
        });
        
        await FirebaseFirestore.instance.collection('patina_logs').add({
          'item_id': widget.itemId,
          'timestamp': FieldValue.serverTimestamp(),
          'cumulative_value': newTotal,
        });
      } catch (e) {
        print("Sync failed: $e");
      }

      setState(() {
        _isLoading = false;
        _displayText = "✅ Atmospheric Sync Complete\n\n"
            "Exposure: ${(hoursElapsed * 60).toStringAsFixed(1)} mins\n"
            "Hum: $humidity% | SO2: $so2 μg/m³\n"
            "Micro-Patina: +${increment.toStringAsFixed(6)}";
      });
    } else {
      setState(() { _isLoading = false; _displayText = "❌ Sensor failure. Check connection."; });
    }
  }

  void _resetPatina() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text("Polish Silver", style: TextStyle(color: Colors.white)),
        content: const Text("This acts like a silver polishing cloth. Oxidation will reset to 0.", style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel", style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD84315)),
            onPressed: () async {
              await FirebaseFirestore.instance.collection('silver_items').doc(widget.itemId).update({
                'total_oxidation': 0.0,
                'last_sync_time': FieldValue.serverTimestamp(),
              });
              if (context.mounted) Navigator.pop(context);
              setState(() { _displayText = "✨ Polished. Patina reset to 0."; });
            },
            child: const Text("Polish", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.itemName.toUpperCase(), style: const TextStyle(letterSpacing: 1.5, fontSize: 16)),
        actions: [
          IconButton(icon: const Icon(Icons.cleaning_services_rounded, color: Colors.grey), onPressed: _resetPatina)
        ],
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('silver_items').doc(widget.itemId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator(color: Color(0xFFB0BEC5)));
          
          var data = snapshot.data!.data() as Map<String, dynamic>;
          double totalOxidation = (data['total_oxidation'] as num?)?.toDouble() ?? 0.0;
          
          // 🚀 Bug 1 终极防御：安全解析时间戳，杜绝红屏
          Timestamp? rawTime = data['last_sync_time'] as Timestamp?;
          DateTime lastSync = rawTime?.toDate() ?? DateTime.now();

          double oxidationProgress = (totalOxidation / 100).clamp(0.0, 1.0);
          Color brightSilver = const Color(0xFFF5F5F5);
          Color oxidizedBlack = const Color(0xFF1C1F22);
          Color currentSilverColor = Color.lerp(brightSilver, oxidizedBlack, oxidationProgress)!;

          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40),
              child: Column(
                children: [
                  // 🎨 视觉升级：金属质感徽章
                  Container(
                    width: 140, height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [currentSilverColor.withOpacity(0.7), currentSilverColor],
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 20, offset: const Offset(0, 10)),
                        BoxShadow(color: Colors.white.withOpacity(0.1), blurRadius: 10, spreadRadius: -5), // 金属反光
                      ],
                      border: Border.all(color: Colors.white.withOpacity(0.2), width: 1.5),
                    ),
                    child: Center(
                      child: Text("950\nAg", textAlign: TextAlign.center,
                        style: TextStyle(
                          color: oxidationProgress > 0.6 ? Colors.white70 : const Color(0xFF333333), 
                          fontWeight: FontWeight.w900, fontSize: 24, letterSpacing: 2
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  
                  Text("PATINA ACCUMULATION", style: TextStyle(fontSize: 12, letterSpacing: 2, color: Colors.grey.withOpacity(0.8))),
                  const SizedBox(height: 8),
                  Text(totalOxidation.toStringAsFixed(4), style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w300, color: Colors.white)),
                  
                  const SizedBox(height: 40),
                  
                  Container(
                    padding: const EdgeInsets.all(20), width: double.infinity,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E), 
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.05))
                    ),
                    child: Text(_displayText, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, height: 1.8, color: Colors.white70)),
                  ),

                  const SizedBox(height: 40),
                  
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : () => _fetchData(totalOxidation, lastSync),
                      icon: _isLoading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)) : const Icon(Icons.radar),
                      label: Text(_isLoading ? 'SCANNING...' : 'ENVIRONMENT SCAN', style: const TextStyle(letterSpacing: 1.5)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFB0BEC5), foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                  
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => ChartScreen(itemId: widget.itemId))),
                      icon: const Icon(Icons.show_chart, color: Colors.white),
                      label: const Text('GROWTH ANALYTICS', style: TextStyle(letterSpacing: 1.5, color: Colors.white)),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Colors.white.withOpacity(0.3)),
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      ),
    );
  }
}

// ==========================================
// 3. 专属图表页 (Bug 2: 本地排序修复)
// ==========================================
class ChartScreen extends StatelessWidget {
  final String itemId;
  const ChartScreen({super.key, required this.itemId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('GROWTH CURVE', style: TextStyle(letterSpacing: 1.5, fontSize: 16))),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("OXIDATION TIMELINE", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5, color: Colors.white)),
            const SizedBox(height: 8),
            Text("Powered by London Atmospheric Data", style: TextStyle(fontSize: 12, color: Colors.grey.withOpacity(0.8))),
            const SizedBox(height: 40),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                // 🚀 Bug 2 终极修复：去掉了 orderBy，避免复合索引报错
                stream: FirebaseFirestore.instance.collection('patina_logs').where('item_id', isEqualTo: itemId).snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: Color(0xFFB0BEC5)));
                  if (snapshot.hasError) return Center(child: Text('Data Error: ${snapshot.error}', style: const TextStyle(color: Colors.red)));
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) return const Center(child: Text('No atmospheric logs yet.', style: TextStyle(color: Colors.grey)));

                  // 🚀 在 Dart 本地层进行时间排序 (完美绕过 Firebase 复合索引限制)
                  final docs = snapshot.data!.docs.toList();
                  docs.sort((a, b) {
                    Timestamp? tA = (a.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
                    Timestamp? tB = (b.data() as Map<String, dynamic>)['timestamp'] as Timestamp?;
                    if (tA == null && tB == null) return 0;
                    if (tA == null) return 1;
                    if (tB == null) return -1;
                    return tA.compareTo(tB);
                  });

                  List<FlSpot> spots = [];
                  for (int i = 0; i < docs.length; i++) {
                    var data = docs[i].data() as Map<String, dynamic>;
                    double cumulative = (data['cumulative_value'] as num?)?.toDouble() ?? 0.0;
                    spots.add(FlSpot(i.toDouble(), cumulative)); 
                  }

                  return LineChart(
                    LineChartData(
                      gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (value) => FlLine(color: Colors.white.withOpacity(0.1), strokeWidth: 1)),
                      titlesData: const FlTitlesData(
                        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      ),
                      borderData: FlBorderData(show: false),
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots, isCurved: true, color: const Color(0xFFD84315), barWidth: 3,
                          isStrokeCapRound: true, dotData: const FlDotData(show: true),
                          belowBarData: BarAreaData(
                            show: true, 
                            gradient: LinearGradient(
                              colors: [const Color(0xFFD84315).withOpacity(0.4), Colors.transparent],
                              begin: Alignment.topCenter, end: Alignment.bottomCenter,
                            )
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}