import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class EnvironmentService {
  final String apiKey = '7b76f1aa7e83e89b907cb62fabaed97d';

  // 1. 获取设备当前 GPS 坐标
  Future<Position?> getCurrentLocation() async {
    bool serviceEnabled;
    LocationPermission permission;

    // 检查定位服务是否开启
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      print('Location services are disabled.');
      return null;
    }

    // 检查并请求定位权限
    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        print('Location permissions are denied');
        return null;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      print('Location permissions are permanently denied.');
      return null;
    } 

    // 获取高精度经纬度
    return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
  }

  // 2. 根据经纬度请求天气与污染数据
  Future<Map<String, dynamic>?> fetchEnvironmentalData() async {
    Position? position = await getCurrentLocation();
    if (position == null) return null;

    double lat = position.latitude;
    double lon = position.longitude;
    
    print('Current coordinates: Lat $lat, Lon $lon');

    try {
      // 接口A：获取当前湿度
      final weatherUrl = Uri.parse(
          'https://api.openweathermap.org/data/2.5/weather?lat=$lat&lon=$lon&appid=$apiKey');
      final weatherResponse = await http.get(weatherUrl);
      
      // 接口B：获取空气污染指数 (特别是 SO2)
      final pollutionUrl = Uri.parse(
          'https://api.openweathermap.org/data/2.5/air_pollution?lat=$lat&lon=$lon&appid=$apiKey');
      final pollutionResponse = await http.get(pollutionUrl);

      if (weatherResponse.statusCode == 200 && pollutionResponse.statusCode == 200) {
        var weatherData = json.decode(weatherResponse.body);
        var pollutionData = json.decode(pollutionResponse.body);

        // 提取我们需要计算氧化的核心指标
        int humidity = weatherData['main']['humidity'];
        double so2 = pollutionData['list'][0]['components']['so2'];

        print('Data fetched -> Humidity: $humidity%, SO2: $so2 μg/m3');

        return {
          'humidity': humidity,
          'so2': so2,
        };
      } else {
        print('Failed to load API data.');
        return null;
      }
    } catch (e) {
      print('Error calling APIs: $e');
      return null;
    }
  }
  // 核心算法：计算当日包浆（氧化）指数
  // 传入我们刚才抓取到的 湿度 (humidity) 和 二氧化硫浓度 (so2)
  double calculatePatinaIndex(double humidity, double so2, {double alloyCoefficient = 1.0}) {
    // 1. 设定权重 (你可以根据后期答辩的物理模型调整)
    double w1 = 0.3; // 湿度对银氧化的权重
    double w2 = 0.7; // SO2 硫化物对银氧化的核心权重

    // 2. 计算基础增量公式: PatinaIncrement = (Humidity * W1) + (SO2 * W2)
    double patinaIncrement = (humidity * w1) + (so2 * w2);

    // 3. 乘上合金系数: DailyPatina = PatinaIncrement * AlloyCoefficient
    double dailyPatina = patinaIncrement * alloyCoefficient;

    // 保留两位小数返回，让界面显示更美观
    return double.parse(dailyPatina.toStringAsFixed(2));
  }
}