import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../utils/app_error.dart';

/// 实时天气数据
class WeatherData {
  final double temperature;     // 当前温度 °C
  final double feelsLike;       // 体感温度 °C
  final double humidity;        // 湿度 %
  final double windSpeed;       // 风速 km/h
  final int weatherCode;        // WMO 天气代码
  final String weatherDesc;     // 天气描述（中文）
  final String weatherEmoji;    // 天气 emoji
  final bool isDay;             // 是否白天
  final String city;            // 城市名（用于展示）
  final DateTime fetchTime;     // 获取时间

  const WeatherData({
    required this.temperature,
    required this.feelsLike,
    required this.humidity,
    required this.windSpeed,
    required this.weatherCode,
    required this.weatherDesc,
    required this.weatherEmoji,
    required this.isDay,
    required this.city,
    required this.fetchTime,
  });

  /// 给 AI 的天气描述字符串
  String toPromptString() {
    return '$weatherEmoji $weatherDesc，气温${temperature.round()}°C（体感${feelsLike.round()}°C），'
        '湿度${humidity.round()}%，风速${windSpeed.round()}km/h';
  }

  /// 穿搭建议提示（根据体感温度）
  String get dressHint {
    final t = feelsLike;
    if (t <= 0) return '极寒天气，必备羽绒服+加绒打底，注意面部和手部防冻';
    if (t <= 5) return '严寒，厚羽绒服或棉服必备，可叠穿毛衣打底';
    if (t <= 10) return '寒冷，厚外套+毛衣，注意保暖';
    if (t <= 15) return '凉爽，薄外套或针织衫，早晚记得加一层';
    if (t <= 20) return '舒适，轻薄外套或长袖，日差大时随时可脱';
    if (t <= 25) return '温暖，长袖为主，可备一件薄外套';
    if (t <= 30) return '偏热，短袖+防晒是主旋律';
    if (t <= 35) return '炎热，清凉透气优先，防晒必备';
    return '酷暑，最薄最透气的为主，防晒+补水最重要';
  }
}

/// 天气服务
///
/// 使用 Open-Meteo（免费、无需 API Key、CORS 友好）
/// + 城市地理编码（Open-Meteo Geocoding API）
class WeatherService {
  WeatherService._();
  static final WeatherService to = WeatherService._();

  // ── 缓存（30分钟内同城市不重复请求）──────────────────────────────
  static final Map<String, _CacheEntry> _cache = {};
  static const _cacheTtl = Duration(minutes: 30);

  // ── 常用城市经纬度预置（减少 geocoding 请求）─────────────────────
  static const Map<String, _LatLon> _cityCoords = {
    '北京': _LatLon(39.9042, 116.4074),
    '上海': _LatLon(31.2304, 121.4737),
    '广州': _LatLon(23.1291, 113.2644),
    '深圳': _LatLon(22.5431, 114.0579),
    '杭州': _LatLon(30.2741, 120.1551),
    '成都': _LatLon(30.5728, 104.0668),
    '重庆': _LatLon(29.5630, 106.5516),
    '武汉': _LatLon(30.5928, 114.3055),
    '西安': _LatLon(34.3416, 108.9398),
    '南京': _LatLon(32.0603, 118.7969),
    '天津': _LatLon(39.3434, 117.3616),
    '苏州': _LatLon(31.2990, 120.5853),
    '长沙': _LatLon(28.2282, 112.9388),
    '郑州': _LatLon(34.7466, 113.6254),
    '青岛': _LatLon(36.0671, 120.3826),
    '沈阳': _LatLon(41.8057, 123.4315),
    '哈尔滨': _LatLon(45.8038, 126.5349),
    '大连': _LatLon(38.9140, 121.6147),
    '昆明': _LatLon(25.0389, 102.7183),
    '厦门': _LatLon(24.4798, 118.0894),
    '福州': _LatLon(26.0745, 119.2965),
    '合肥': _LatLon(31.8206, 117.2272),
    '济南': _LatLon(36.6512, 117.1201),
    '太原': _LatLon(37.8706, 112.5489),
    '石家庄': _LatLon(38.0428, 114.5149),
    '长春': _LatLon(43.8171, 125.3235),
    '呼和浩特': _LatLon(40.8415, 111.7519),
    '乌鲁木齐': _LatLon(43.8256, 87.6168),
    '兰州': _LatLon(36.0611, 103.8343),
    '银川': _LatLon(38.4681, 106.2731),
    '西宁': _LatLon(36.6171, 101.7782),
    '贵阳': _LatLon(26.6477, 106.6302),
    '南宁': _LatLon(22.8170, 108.3665),
    '海口': _LatLon(20.0440, 110.1999),
    '南昌': _LatLon(28.6820, 115.8579),
    '朝阳': _LatLon(41.5711, 120.4503),   // 辽宁朝阳
    '北票': _LatLon(41.7957, 120.7584),   // 辽宁北票
    '锦州': _LatLon(41.0956, 121.1268),
    '营口': _LatLon(40.6672, 122.2354),
    '鞍山': _LatLon(41.1109, 122.9955),
    '抚顺': _LatLon(41.8785, 123.9573),
    '本溪': _LatLon(41.2940, 123.7654),
    '丹东': _LatLon(40.1290, 124.3953),
    '辽阳': _LatLon(41.2692, 123.2360),
  };

  /// 获取城市实时天气
  ///
  /// [cityName] 城市名（中文，如"北票"或"辽宁省朝阳市北票市"）
  /// 返回 null 时说明获取失败（网络问题或找不到城市）
  Future<WeatherData?> fetchWeather(String? cityName) async {
    if (cityName == null || cityName.isEmpty) return null;

    // 规范化城市名（取最后一个市级名称）
    final normalizedCity = _normalizeCity(cityName);

    // 检查缓存
    final cached = _cache[normalizedCity];
    if (cached != null && DateTime.now().difference(cached.time) < _cacheTtl) {
      return cached.data;
    }

    try {
      // 1. 获取经纬度
      final coords = await _getCoords(normalizedCity);
      if (coords == null) return null;

      // 2. 拉取实时天气
      final weather = await _fetchFromOpenMeteo(coords.lat, coords.lon, normalizedCity);

      if (weather != null) {
        _cache[normalizedCity] = _CacheEntry(weather, DateTime.now());
      }
      return weather;
    } catch (e) {
      AppLogger.w('WeatherService', 'fetchWeather 失败', e);
      return null;
    }
  }

  // ── 内部方法 ─────────────────────────────────────────────────────

  /// 规范化城市名（提取最细粒度的城市名）
  static String _normalizeCity(String raw) {
    // 先尝试在预置表中直接查找精确匹配
    for (final key in _cityCoords.keys) {
      if (raw.contains(key)) return key;
    }
    // 移除省/自治区/直辖市后缀
    String city = raw
        .replaceAll('省', '')
        .replaceAll('自治区', '')
        .replaceAll('直辖市', '')
        .trim();
    // 取最后两个字（通常是城市名）
    if (city.length > 4) {
      city = city.substring(city.length - 4).replaceAll('市', '').trim();
    }
    city = city.replaceAll('市', '').trim();
    return city.isEmpty ? raw : city;
  }

  /// 获取城市经纬度（先查预置表，再走 geocoding API）
  Future<_LatLon?> _getCoords(String city) async {
    // 预置表命中
    if (_cityCoords.containsKey(city)) {
      return _cityCoords[city];
    }

    // 调用 Open-Meteo Geocoding API
    try {
      final uri = Uri.parse(
        'https://geocoding-api.open-meteo.com/v1/search'
        '?name=${Uri.encodeComponent(city)}&count=1&language=zh&format=json',
      );
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final results = json['results'] as List?;
      if (results == null || results.isEmpty) return null;

      final first = results.first as Map<String, dynamic>;
      return _LatLon(
        (first['latitude'] as num).toDouble(),
        (first['longitude'] as num).toDouble(),
      );
    } catch (e) {
      AppLogger.w('WeatherService', 'Geocoding 失败', e);
      return null;
    }
  }

  /// 从 Open-Meteo 获取实时天气数据
  Future<WeatherData?> _fetchFromOpenMeteo(double lat, double lon, String city) async {
    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$lat&longitude=$lon'
        '&current=temperature_2m,apparent_temperature,relative_humidity_2m,'
        'wind_speed_10m,weather_code,is_day'
        '&wind_speed_unit=kmh'
        '&timezone=Asia%2FShanghai',
      );

      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final current = json['current'] as Map<String, dynamic>;

      final weatherCode = (current['weather_code'] as num).toInt();
      final isDay = (current['is_day'] as num).toInt() == 1;

      return WeatherData(
        temperature: (current['temperature_2m'] as num).toDouble(),
        feelsLike: (current['apparent_temperature'] as num).toDouble(),
        humidity: (current['relative_humidity_2m'] as num).toDouble(),
        windSpeed: (current['wind_speed_10m'] as num).toDouble(),
        weatherCode: weatherCode,
        weatherDesc: _describeWeatherCode(weatherCode, isDay),
        weatherEmoji: _emojiWeatherCode(weatherCode, isDay),
        isDay: isDay,
        city: city,
        fetchTime: DateTime.now(),
      );
    } catch (e) {
      AppLogger.w('WeatherService', 'Open-Meteo 请求失败', e);
      return null;
    }
  }

  // ── WMO 天气代码翻译 ─────────────────────────────────────────────

  static String _describeWeatherCode(int code, bool isDay) {
    if (code == 0) return isDay ? '晴天' : '晴夜';
    if (code == 1) return isDay ? '大晴天' : '晴夜';
    if (code == 2) return '多云';
    if (code == 3) return '阴天';
    if (code <= 49) {
      if (code <= 19) return '有雾';
      if (code <= 29) return '轻雾/霾';
      return '沙尘';
    }
    if (code <= 59) {
      if (code <= 53) return '毛毛雨';
      return '冻毛毛雨';
    }
    if (code <= 69) {
      if (code == 61) return '小雨';
      if (code == 63) return '中雨';
      if (code == 65) return '大雨';
      if (code == 66) return '冻雨（小）';
      return '冻雨（大）';
    }
    if (code <= 79) {
      if (code == 71) return '小雪';
      if (code == 73) return '中雪';
      if (code == 75) return '大雪';
      return '冰粒';
    }
    if (code <= 82) return '阵雨';
    if (code == 85 || code == 86) return '阵雪';
    if (code <= 99) return '雷阵雨';
    return '未知天气';
  }

  static String _emojiWeatherCode(int code, bool isDay) {
    if (code == 0 || code == 1) return isDay ? '☀️' : '🌙';
    if (code == 2) return '⛅';
    if (code == 3) return '☁️';
    if (code <= 49) return '🌫️';
    if (code <= 69) {
      if (code <= 53) return '🌦️';
      if (code == 61 || code == 63) return '🌧️';
      if (code == 65) return '⛈️';
      return '🌧️';
    }
    if (code <= 79) return '❄️';
    if (code <= 82) return '🌧️';
    if (code <= 86) return '🌨️';
    return '⛈️';
  }
}

// ── 内部数据类 ───────────────────────────────────────────────────────

class _LatLon {
  final double lat;
  final double lon;
  const _LatLon(this.lat, this.lon);
}

class _CacheEntry {
  final WeatherData data;
  final DateTime time;
  _CacheEntry(this.data, this.time);
}
